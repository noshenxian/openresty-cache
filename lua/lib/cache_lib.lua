local redis_conn = require "redis_conn"
local cjson = require "cjson"

-- 在文件开头的共享内存区域声明下方添加
local cache_metadata = ngx.shared.cache_metadata
local cache_locks = ngx.shared.cache_locks
local cache_stats = ngx.shared.cache_stats

-- 添加这一行
local miss_urls = ngx.shared.miss_urls  -- 存储未命中的URL

local _M = {}

-- 缓存级别定义
local CACHE_LEVEL = {
    MEMORY = 1,  -- 内存缓存(shared dict)
    REDIS = 2,   -- Redis缓存
    BACKEND = 3  -- 后端存储
}

_M.CACHE_LEVEL = CACHE_LEVEL

-- 生成缓存键
function _M.generate_key(uri, args, headers)
    local key = uri
    
    -- 可以根据需要添加更多参数到缓存键
    -- 例如：查询参数、特定请求头等
    if args and next(args) then
        local args_str = ""
        local args_arr = {}
        
        for k, v in pairs(args) do
            if type(v) == "table" then
                for _, val in ipairs(v) do
                    table.insert(args_arr, k .. "=" .. val)
                end
            else
                table.insert(args_arr, k .. "=" .. v)
            end
        end
        
        table.sort(args_arr)  -- 排序以确保一致性
        args_str = table.concat(args_arr, "&")
        
        if args_str ~= "" then
            key = key .. "?" .. args_str
        end
    end
    
    -- 可以添加基于请求头的缓存变体
    -- 例如：根据Accept-Language、User-Agent等
    
    return ngx.md5(key)  -- 使用MD5哈希缩短键长度
end

-- 获取缓存锁
function _M.acquire_lock(key, timeout, exptime)
    timeout = timeout or 5  -- 默认等待5秒
    exptime = exptime or 60  -- 默认锁过期时间60秒
    
    local lock_key = "lock:" .. key
    local elapsed = 0
    local step = 0.001  -- 1ms
    
    while elapsed < timeout do
        local success = cache_locks:add(lock_key, 1, exptime)
        if success then
            return true
        end
        
        ngx.sleep(step)
        elapsed = elapsed + step
        step = math.min(step * 2, 0.5)  -- 指数退避，最大500ms
    end
    
    return false
end

-- 释放缓存锁
function _M.release_lock(key)
    local lock_key = "lock:" .. key
    cache_locks:delete(lock_key)
end

-- 从内存缓存获取数据
function _M.get_from_memory(key)
    local value, flags = cache_metadata:get(key)
    if not value then
        return nil
    end
    
    -- 检查是否过期
    local metadata = cjson.decode(value)
    if metadata.expire_time and metadata.expire_time < ngx.time() then
        cache_metadata:delete(key)
        return nil
    end
    
    -- 更新访问统计
    _M.update_stats(key, "memory_hit")
    
    return metadata.value, metadata
end

-- 从Redis缓存获取数据
function _M.get_from_redis(key)
    local red, err = redis_conn.get_connection()
    if not red then
        return nil, err
    end
    
    local redis_key = "cache:" .. key
    local value, err = red:get(redis_key)
    
    if not value or value == ngx.null then
        redis_conn.close_connection(red)
        return nil
    end
    
    -- 获取元数据
    local metadata_key = "metadata:" .. key
    local metadata_json, err = red:get(metadata_key)
    
    local metadata = {}
    if metadata_json and metadata_json ~= ngx.null then
        metadata = cjson.decode(metadata_json)
        
        -- 检查是否过期
        if metadata.expire_time and metadata.expire_time < ngx.time() then
            red:del(redis_key)
            red:del(metadata_key)
            redis_conn.close_connection(red)
            return nil
        end
    end
    
    redis_conn.close_connection(red)
    
    -- 更新访问统计
    _M.update_stats(key, "redis_hit")
    
    -- 同时更新内存缓存
    if metadata.cacheable_memory ~= false then
        _M.set_to_memory(key, value, metadata)
    end
    
    return value, metadata
end

-- 设置内存缓存
-- 在set_to_memory函数中添加
function _M.set_to_memory(key, value, metadata)
    -- 检查内存使用情况
    local free_space = cache_metadata:free_space()
    local capacity = cache_metadata:capacity()
    local usage_ratio = (capacity - free_space) / capacity
    
    -- 如果内存使用率超过90%，主动清理低优先级内容
    if usage_ratio > 0.9 then
        -- 获取所有键
        local keys = cache_metadata:get_keys(0)
        local to_delete = {}
        
        -- 找出可以删除的低优先级键
        for _, k in ipairs(keys) do
            local meta_str, flags = cache_metadata:get(k)
            if meta_str then
                local meta = cjson.decode(meta_str)
                -- 如果是低优先级内容（例如大文件或较少访问的内容）
                if meta.low_priority then
                    table.insert(to_delete, k)
                    if #to_delete >= 10 then  -- 最多删除10个
                        break
                    end
                end
            end
        end
        
        -- 删除低优先级键
        for _, k in ipairs(to_delete) do
            cache_metadata:delete(k)
        end
    end
    
    -- 原有的设置逻辑
    metadata = metadata or {}
    metadata.value = value
    metadata.updated_at = ngx.time()
    
    local expire_ttl = metadata.memory_ttl or 60  -- 默认60秒
    local success, err, forcible = cache_metadata:set(
        key, 
        cjson.encode(metadata),
        expire_ttl
    )
    
    if forcible then
        ngx.log(ngx.WARN, "Shared dict is full, removed items forcibly")
    end
    
    return success, err
end

-- 设置Redis缓存
function _M.set_to_redis(key, value, metadata)
    local red, err = redis_conn.get_connection()
    if not red then
        return nil, err
    end
    
    metadata = metadata or {}
    metadata.updated_at = ngx.time()
    
    local redis_key = "cache:" .. key
    local metadata_key = "metadata:" .. key
    
    -- 设置缓存值
    local expire_ttl = metadata.redis_ttl or 3600  -- 默认1小时
    local ok, err = red:setex(redis_key, expire_ttl, value)
    if not ok then
        redis_conn.close_connection(red)
        return nil, err
    end
    
    -- 设置元数据
    local metadata_json = cjson.encode(metadata)
    ok, err = red:setex(metadata_key, expire_ttl, metadata_json)
    
    redis_conn.close_connection(red)
    return ok, err
end

-- 多级缓存获取
function _M.get(key, options)
    options = options or {}
    
    -- 尝试从内存缓存获取
    if options.skip_memory ~= true then
        local value, metadata = _M.get_from_memory(key)
        if value then
            return value, metadata, CACHE_LEVEL.MEMORY
        end
    end
    
    -- 尝试从Redis缓存获取
    if options.skip_redis ~= true then
        local value, metadata = _M.get_from_redis(key)
        if value then
            return value, metadata, CACHE_LEVEL.REDIS
        end
    end
    
    -- 更新未命中统计
    _M.update_stats(key, "miss")
    
    return nil, nil, nil
end

-- 多级缓存设置
function _M.set(key, value, metadata)
    metadata = metadata or {}
    
    -- 设置过期时间
    if metadata.ttl then
        metadata.expire_time = ngx.time() + metadata.ttl
    end
    
    -- 保存原始URL
    if not metadata.url and ngx.var then
        local uri = ngx.var.uri
        local args = ngx.req.get_uri_args()
        local url = uri
        
        -- 添加查询参数到URL
        if args and next(args) then
            local args_str = ""
            local args_arr = {}
            
            for k, v in pairs(args) do
                if type(v) == "table" then
                    for _, val in ipairs(v) do
                        table.insert(args_arr, k .. "=" .. val)
                    end
                else
                    table.insert(args_arr, k .. "=" .. v)
                end
            end
            
            table.sort(args_arr)  -- 排序以确保一致性
            args_str = table.concat(args_arr, "&")
            
            if args_str ~= "" then
                url = url .. "?" .. args_str
            end
        end
        
        metadata.url = url
    end
    
    -- 设置内存缓存
    if metadata.cacheable_memory ~= false then
        _M.set_to_memory(key, value, metadata)
    end
    
    -- 设置Redis缓存
    if metadata.cacheable_redis ~= false then
        _M.set_to_redis(key, value, metadata)
    end
    
    return true
end

-- 删除缓存
function _M.delete(key)
    -- 删除内存缓存
    cache_metadata:delete(key)
    
    -- 删除Redis缓存
    local red, err = redis_conn.get_connection()
    if not red then
        return false, err
    end
    
    local redis_key = "cache:" .. key
    local metadata_key = "metadata:" .. key
    
    red:del(redis_key)
    red:del(metadata_key)
    
    redis_conn.close_connection(red)
    
    -- 从recent_keys列表中移除该键
    local recent_keys = cache_stats:get("recent_keys") or "{}"
    local keys = cjson.decode(recent_keys)
    local new_keys = {}
    
    -- 过滤掉要删除的键
    for _, item in ipairs(keys) do
        if item.key ~= key then
            table.insert(new_keys, item)
        end
    end
    
    -- 更新recent_keys列表
    cache_stats:set("recent_keys", cjson.encode(new_keys))
    
    return true
end

-- 按前缀删除缓存
function _M.delete_by_prefix(prefix)
    local red, err = redis_conn.get_connection()
    if not red then
        return false, err
    end
    
    -- 使用Redis的SCAN命令查找匹配的键
    local cursor = "0"
    local count = 0
    
    repeat
        local res, err = red:scan(cursor, "MATCH", "cache:" .. prefix .. "*", "COUNT", 100)
        
        if not res then
            redis_conn.close_connection(red)
            return false, err
        end
        
        cursor = res[1]
        local keys = res[2]
        
        if #keys > 0 then
            -- 删除找到的键
            red:del(unpack(keys))
            count = count + #keys
            
            -- 同时删除元数据键
            local metadata_keys = {}
            for _, key in ipairs(keys) do
                table.insert(metadata_keys, key:gsub("^cache:", "metadata:"))
            end
            if #metadata_keys > 0 then
                red:del(unpack(metadata_keys))
            end
        end
    until cursor == "0"
    
    redis_conn.close_connection(red)
    
    -- 获取当前recent_keys
    local recent_keys = cache_stats:get("recent_keys") or "{}"
    local keys = cjson.decode(recent_keys)
    
    -- 清空recent_keys列表，但保留URL信息
    local new_keys = {}
    for _, item in ipairs(keys) do
        -- 保留URL信息，但重置命中计数
        table.insert(new_keys, {
            key = item.key,
            url = item.url,  -- 保留URL信息
            hit_count = 0,   -- 重置命中计数
            time = ngx.time() -- 更新时间
        })
    end
    
    -- 保存更新后的recent_keys
    cache_stats:set("recent_keys", cjson.encode(new_keys))
    
    return true, count
end

-- 更新缓存统计信息
function _M.update_stats(key, stat_type)
    local stats_key = stat_type .. "_count"
    local current = cache_stats:get(stats_key) or 0
    cache_stats:set(stats_key, current + 1)
    
    -- 更新最近访问的键
    if stat_type ~= "miss" then
        local recent_keys = cache_stats:get("recent_keys") or "{}"
        local keys = cjson.decode(recent_keys)
        
        -- 检查键是否已存在
        local exists = false
        for i, item in ipairs(keys) do
            if item.key == key then
                -- 键已存在，更新计数和时间
                item.hit_count = (item.hit_count or 0) + 1
                item.time = ngx.time()
                exists = true
                break
            end
        end
        
        -- 如果键不存在，添加到列表
        if not exists then
            -- 尝试从元数据中获取URL
            local url = key
            local metadata_value = cache_metadata:get(key)
            if metadata_value then
                local metadata = cjson.decode(metadata_value)
                if metadata.url then
                    url = metadata.url
                end
            end
            
            table.insert(keys, 1, {
                key = key,
                url = url,
                hit_count = 1,
                time = ngx.time()
            })
        end
        
        -- 保持最近访问的键列表（最多100个）
        if #keys > 100 then
            table.remove(keys)
        end
        
        cache_stats:set("recent_keys", cjson.encode(keys))
    else
        -- 记录未命中的URL
        local uri = ngx.var.uri
        local args = ngx.req.get_uri_args()
        local url = uri
        
        -- 添加查询参数到URL
        if args and next(args) then
            local args_str = ""
            local args_arr = {}
            
            for k, v in pairs(args) do
                if type(v) == "table" then
                    for _, val in ipairs(v) do
                        table.insert(args_arr, k .. "=" .. val)
                    end
                else
                    table.insert(args_arr, k .. "=" .. v)
                end
            end
            
            table.sort(args_arr)  -- 排序以确保一致性
            args_str = table.concat(args_arr, "&")
            
            if args_str ~= "" then
                url = url .. "?" .. args_str
            end
        end
        
        -- 获取当前未命中URL列表
        local miss_urls_json = miss_urls:get("urls") or "{}"
        local urls = cjson.decode(miss_urls_json)
        
        -- 检查URL是否已存在
        local exists = false
        for i, item in ipairs(urls) do
            if item.url == url then
                -- URL已存在，更新计数和时间
                item.count = item.count + 1
                item.last_time = ngx.time()
                exists = true
                break
            end
        end
        
        -- 如果URL不存在，添加到列表
        if not exists then
            table.insert(urls, 1, {
                url = url,
                count = 1,
                first_time = ngx.time(),
                last_time = ngx.time()
            })
            
            -- 保持列表不超过100个
            if #urls > 100 then
                table.remove(urls)
            end
        end
        
        -- 保存更新后的列表
        miss_urls:set("urls", cjson.encode(urls))
    end
end

-- 获取缓存统计信息
function _M.get_stats()
    local stats = {
        memory_hit_count = cache_stats:get("memory_hit_count") or 0,
        redis_hit_count = cache_stats:get("redis_hit_count") or 0,
        miss_count = cache_stats:get("miss_count") or 0,
        memory_usage = cache_metadata:capacity() - cache_metadata:free_space(),
        memory_capacity = cache_metadata:capacity()
    }
    
    -- 计算命中率
    local total_requests = stats.memory_hit_count + stats.redis_hit_count + stats.miss_count
    if total_requests > 0 then
        stats.hit_ratio = (stats.memory_hit_count + stats.redis_hit_count) / total_requests
    else
        stats.hit_ratio = 0
    end
    
    -- 获取最近访问的键
    local recent_keys = cache_stats:get("recent_keys") or "{}"
    stats.recent_keys = cjson.decode(recent_keys)
    
    -- 获取Redis信息
    local red, err = redis_conn.get_connection()
    if red then
        local info, err = red:info("memory")
        if info then
            local redis_used_memory = string.match(info, "used_memory:(%d+)")
            if redis_used_memory then
                stats.redis_used_memory = tonumber(redis_used_memory)
            end
        end
        redis_conn.close_connection(red)
    end
    
    return stats
end

-- 添加获取未命中URL的函数
function _M.get_miss_urls()
    local miss_urls_json = miss_urls:get("urls") or "{}"
    return cjson.decode(miss_urls_json)
end

-- 搜索缓存内容
function _M.search_cache_content(keyword)
    if not keyword or keyword == "" then
        return {}
    end
    
    local result = {}
    keyword = string.lower(keyword)
    
    -- 首先搜索内存缓存
    local memory_keys = cache_metadata:get_keys(0)
    for _, key in ipairs(memory_keys) do
        local metadata_value = cache_metadata:get(key)
        if metadata_value then
            local metadata = cjson.decode(metadata_value)
            local value = metadata.value
            
            -- 检查缓存内容是否包含关键字
            if value and type(value) == "string" and string.find(string.lower(value), keyword) then
                local url = metadata.url or key
                table.insert(result, {
                    key = key,
                    url = url,
                    hit_count = metadata.hit_count or 0,
                    time = metadata.updated_at or ngx.time(),
                    source = "memory"
                })
            end
        end
    end
    
    -- 然后搜索Redis缓存
    local red, err = redis_conn.get_connection()
    if red then
        local cursor = "0"
        repeat
            local res, err = red:scan(cursor, "MATCH", "cache:*", "COUNT", 100)
            if not res then
                break
            end
            
            cursor = res[1]
            local keys = res[2]
            
            for _, redis_key in ipairs(keys) do
                local value, err = red:get(redis_key)
                if value and value ~= ngx.null then
                    -- 检查缓存内容是否包含关键字
                    if string.find(string.lower(value), keyword) then
                        local key = redis_key:gsub("^cache:", "")
                        local metadata_key = "metadata:" .. key
                        local metadata_json, err = red:get(metadata_key)
                        
                        local url = key
                        local hit_count = 0
                        local updated_at = ngx.time()
                        
                        if metadata_json and metadata_json ~= ngx.null then
                            local metadata = cjson.decode(metadata_json)
                            url = metadata.url or key
                            hit_count = metadata.hit_count or 0
                            updated_at = metadata.updated_at or ngx.time()
                        end
                        
                        table.insert(result, {
                            key = key,
                            url = url,
                            hit_count = hit_count,
                            time = updated_at,
                            source = "redis"
                        })
                    end
                end
            end
        until cursor == "0"
        
        redis_conn.close_connection(red)
    end
    
    -- 按最后访问时间排序
    table.sort(result, function(a, b) return a.time > b.time end)
    
    return result
end

-- 强制缓存URL到Redis
function _M.force_cache_url(url, content, ttl)
    -- 生成缓存键
    local key = ngx.md5(url)
    
    -- 设置元数据
    local metadata = {
        url = url,
        force_cached = true,
        redis_ttl = ttl or 3600, -- 默认1小时
        memory_ttl = 60,         -- 内存缓存60秒
        updated_at = ngx.time()
    }
    
    -- 如果没有提供内容，使用默认内容
    content = content or "This is a force cached content for URL: " .. url
    
    -- 设置缓存
    return _M.set(key, content, metadata)
end

-- 从未命中URL列表中移除URL
function _M.remove_miss_url(url)
    local miss_urls_json = miss_urls:get("urls") or "{}"
    local urls = cjson.decode(miss_urls_json)
    local new_urls = {}
    
    -- 过滤掉要删除的URL
    for _, item in ipairs(urls) do
        if item.url ~= url then
            table.insert(new_urls, item)
        end
    end
    
    -- 保存更新后的列表
    miss_urls:set("urls", cjson.encode(new_urls))
    
    return true
end

return _M