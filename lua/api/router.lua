local cjson = require "cjson"

-- 简单的API路由器
local uri = ngx.var.uri
local method = ngx.req.get_method()

-- 设置JSON响应头
ngx.header["Content-Type"] = "application/json"

-- 路由表
local routes = {
    ["/api/cache/stats"] = {
        GET = function()
            local cache_lib = require "cache_lib"
            local stats = cache_lib.get_stats()
            return stats
        end
    },
    ["/api/cache/keys"] = {
        GET = function()
            local cache_lib = require "cache_lib"
            local stats = cache_lib.get_stats()
            return { keys = stats.recent_keys }
        end
    },
    ["/api/cache/item"] = {
        GET = function()
            local args = ngx.req.get_uri_args()
            local key = args.key
            
            if not key then
                ngx.status = 400
                return { error = "Missing key parameter" }
            end
            
            local cache_lib = require "cache_lib"
            local value, metadata = cache_lib.get(key)
            
            if not value then
                ngx.status = 404
                return { error = "Cache key not found" }
            end
            
            return {
                key = key,
                metadata = metadata,
                value = value
            }
        end,
        DELETE = function()
            local args = ngx.req.get_uri_args()
            local key = args.key
            
            if not key then
                ngx.status = 400
                return { error = "Missing key parameter" }
            end
            
            local cache_lib = require "cache_lib"
            local success, err = cache_lib.delete(key)
            
            if not success then
                ngx.status = 500
                return { error = err or "Failed to delete cache key" }
            end
            
            return { success = true, message = "Cache key deleted" }
        end
    },
    ["/api/cache/flush"] = {
        POST = function()
            ngx.req.read_body()
            local data = ngx.req.get_body_data()
            local args = data and cjson.decode(data) or {}
            
            local prefix = args.prefix or ""
            
            local cache_lib = require "cache_lib"
            local success, count = cache_lib.delete_by_prefix(prefix)
            
            if not success then
                ngx.status = 500
                return { error = count or "Failed to flush cache" }
            end
            
            return { 
                success = true, 
                message = "Cache flushed", 
                count = count 
            }
        end
    }
}

-- 处理请求
local handler = routes[uri] and routes[uri][method]

if handler then
    local response = handler()
    ngx.say(cjson.encode(response))
else
    ngx.status = 404
    ngx.say(cjson.encode({ error = "API endpoint not found" }))
end