-- 记录缓存访问日志
local cache_key = ngx.ctx.cache_key
if not cache_key then
    return
end

local cache_hit = ngx.ctx.cache_hit
local cache_level = ngx.ctx.cache_level

local log_info = {
    time = ngx.time(),
    uri = ngx.var.uri,
    args = ngx.req.get_uri_args(),
    cache_key = cache_key,
    cache_hit = cache_hit,
    cache_level = cache_level,
    status = ngx.status
}

-- 这里可以将日志写入文件或发送到日志系统
ngx.log(ngx.INFO, require("cjson").encode(log_info))