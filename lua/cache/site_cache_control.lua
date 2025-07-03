local cache_lib = require "cache_lib"

-- 解析请求参数
local uri = ngx.var.uri
local args = ngx.req.get_uri_args()
local method = ngx.req.get_method()

-- 只缓存GET请求
if method ~= "GET" then
    return
end

-- 检查是否跳过缓存
if args["_no_cache"] == "1" then
    ngx.ctx.skip_cache = true
    return
end

-- 为不同类型的文件设置不同的缓存策略
local file_ext = string.match(uri, [[\.([\.^]*)$]])
if file_ext then
    file_ext = string.lower(file_ext)
    
    -- 图片文件缓存时间更长
    if file_ext == "jpg" or file_ext == "jpeg" or file_ext == "png" or file_ext == "gif" or file_ext == "webp" then
        ngx.ctx.cache_ttl = 604800  -- 7天
    -- CSS和JS文件中等缓存时间
    elseif file_ext == "css" or file_ext == "js" then
        ngx.ctx.cache_ttl = 86400  -- 1天
    -- HTML文件较短缓存时间
    elseif file_ext == "html" or file_ext == "htm" then
        ngx.ctx.cache_ttl = 3600  -- 1小时
    -- 其他文件默认缓存时间
    else
        ngx.ctx.cache_ttl = 43200  -- 12小时
    end
end

-- 生成缓存键
local cache_key = cache_lib.generate_key(uri, args)
ngx.ctx.cache_key = cache_key

-- 尝试从缓存获取
local cached_value, metadata, cache_level = cache_lib.get(cache_key)

if cached_value then
    -- 设置缓存命中标记
    ngx.ctx.cache_hit = true
    ngx.ctx.cache_level = cache_level
    ngx.ctx.cache_metadata = metadata
    
    -- 直接返回缓存内容
    ngx.header["Content-Type"] = metadata.content_type or "application/octet-stream"
    ngx.header["X-Cache"] = "HIT"
    ngx.header["X-Cache-Level"] = cache_level == cache_lib.CACHE_LEVEL.MEMORY and "MEMORY" or "REDIS"
    
    if metadata.headers then
        for k, v in pairs(metadata.headers) do
            ngx.header[k] = v
        end
    end
    
    ngx.print(cached_value)
    ngx.exit(ngx.HTTP_OK)
else
    -- 缓存未命中
    ngx.ctx.cache_hit = false
    ngx.header["X-Cache"] = "MISS"
end