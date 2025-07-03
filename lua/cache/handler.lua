local cache_lib = require "cache_lib"

-- 如果已经缓存命中，这个处理器不会被执行

-- 检查是否需要跳过缓存
if ngx.ctx.skip_cache then
    -- 转发到后端服务
    return
end

-- 获取缓存键
local cache_key = ngx.ctx.cache_key
if not cache_key then
    -- 如果没有缓存键，生成一个
    local uri = ngx.var.uri
    local args = ngx.req.get_uri_args()
    cache_key = cache_lib.generate_key(uri, args)
    ngx.ctx.cache_key = cache_key
end

-- 尝试获取缓存锁，避免缓存穿透
local lock_acquired = cache_lib.acquire_lock(cache_key)
if not lock_acquired then
    -- 如果无法获取锁，说明有其他请求正在处理相同的缓存键
    -- 等待一段时间后再次尝试从缓存获取
    ngx.sleep(0.1)
    local cached_value, metadata, cache_level = cache_lib.get(cache_key)
    
    if cached_value then
        -- 设置缓存命中标记
        ngx.ctx.cache_hit = true
        ngx.ctx.cache_level = cache_level
        ngx.ctx.cache_metadata = metadata
        
        -- 返回缓存内容
        ngx.header["Content-Type"] = metadata.content_type or "application/json"
        ngx.header["X-Cache"] = "HIT"
        ngx.header["X-Cache-Level"] = cache_level == cache_lib.CACHE_LEVEL.MEMORY and "MEMORY" or "REDIS"
        
        if metadata.headers then
            for k, v in pairs(metadata.headers) do
                ngx.header[k] = v
            end
        end
        
        ngx.print(cached_value)
        ngx.exit(ngx.HTTP_OK)
    end
    
    -- 如果仍然未命中，返回临时服务不可用
    ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
    ngx.header["Retry-After"] = "1"
    ngx.say("Service temporarily unavailable, please retry")
    ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

-- 获取到锁，继续处理
-- 注意：这里不再生成模拟数据，而是让请求继续传递给后端
-- 后端响应会被OpenResty的代理模块处理

-- 释放锁
cache_lib.release_lock(cache_key)