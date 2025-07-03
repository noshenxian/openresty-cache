-- 获取静态缓存TTL
local static_cache_ttl = tonumber(ngx.var.static_cache_ttl) or 3600  -- 默认1小时

-- 如果设置了静态缓存TTL，则使用它
if static_cache_ttl and static_cache_ttl > 0 then
    ngx.ctx.cache_ttl = static_cache_ttl
end

-- 设置响应头
if ngx.ctx.cache_hit then
    local cache_level = ngx.ctx.cache_level
    local cache_lib = require "cache_lib"
    
    if cache_level == cache_lib.CACHE_LEVEL.MEMORY then
        ngx.header["X-Cache-From"] = "1"
        ngx.header["X-Cache-Level"] = "1"
    elseif cache_level == cache_lib.CACHE_LEVEL.REDIS then
        ngx.header["X-Cache-From"] = "2"
        ngx.header["X-Cache-Level"] = "2"
    end
end