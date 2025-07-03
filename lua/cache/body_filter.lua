local cache_lib = require "cache_lib"

-- 如果已经缓存命中，不需要再次存储
if ngx.ctx.cache_hit then
    return
end

-- 如果设置了跳过缓存，不进行存储
if ngx.ctx.skip_cache then
    return
end

-- 获取缓存键
local cache_key = ngx.ctx.cache_key
if not cache_key then
    return
end

-- 收集响应体
local chunk = ngx.arg[1]
local is_last_chunk = ngx.arg[2]

-- 初始化或追加到当前块
if not ngx.ctx.response_body then
    ngx.ctx.response_body = ""
end

if chunk then
    ngx.ctx.response_body = ngx.ctx.response_body .. chunk
end

-- 如果在存储到缓存前添加大小检查
if is_last_chunk then
    local body = ngx.ctx.response_body
    
    -- 只缓存成功的响应且大小合适的内容
    if ngx.status >= 200 and ngx.status < 300 and body and #body > 0 then
        -- 不缓存过大的文件（例如超过10MB的文件）
        if #body > 10 * 1024 * 1024 then
            return
        end
        
        -- 准备元数据
        local metadata = {
            content_type = ngx.header["Content-Type"],
            headers = {},
            status = ngx.status
        }
        
        -- 复制需要缓存的响应头
        local headers_to_cache = {
            "Content-Type", "Content-Encoding", "Content-Language",
            "Last-Modified", "ETag", "Cache-Control", "Expires"
        }
        
        for _, header_name in ipairs(headers_to_cache) do
            if ngx.header[header_name] then
                metadata.headers[header_name] = ngx.header[header_name]
            end
        end
        
        -- 设置缓存TTL
        if ngx.ctx.cache_ttl then
            metadata.ttl = ngx.ctx.cache_ttl
            metadata.memory_ttl = math.min(ngx.ctx.cache_ttl, 1800)  -- 内存缓存最多30分钟（从1小时减少到30分钟）
            metadata.redis_ttl = ngx.ctx.cache_ttl
        else
            -- 默认缓存时间
            metadata.ttl = 3600  -- 1小时
            metadata.memory_ttl = 300  -- 内存缓存5分钟（从10分钟减少到5分钟）
            metadata.redis_ttl = 3600  -- Redis缓存1小时
        end
        
        -- 根据内容大小调整缓存策略
        local body_size = #body
        if body_size > 1 * 1024 * 1024 then  -- 大于1MB的内容
            metadata.memory_ttl = math.min(metadata.memory_ttl or 600, 300)  -- 最多缓存5分钟
        end
        
        if body_size > 5 * 1024 * 1024 then  -- 大于5MB的内容
            metadata.cacheable_memory = false  -- 不缓存到内存，只缓存到Redis
        end
        
        -- 存储到内存缓存（可以在body_filter阶段直接操作）
        if metadata.cacheable_memory ~= false then
            cache_lib.set_to_memory(cache_key, body, metadata)
        end
        
        -- Redis缓存需要异步处理
        if metadata.cacheable_redis ~= false then
            local redis_metadata = metadata
            local redis_key = cache_key
            local redis_body = body
            
            -- 使用定时器异步存储到Redis
            ngx.timer.at(0, function()
                cache_lib.set_to_redis(redis_key, redis_body, redis_metadata)
            end)
        end
    end
end