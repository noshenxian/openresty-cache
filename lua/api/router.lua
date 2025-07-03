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
    },
    ["/api/cache/miss_urls"] = {
        GET = function()
            local cache_lib = require "cache_lib"
            local miss_urls = cache_lib.get_miss_urls()
            return { urls = miss_urls }
        end
    },  -- 在这里添加逗号
    -- 在路由表中添加
    ["/api/cache/status"] = {
        GET = function()
            local redis_conn = require "redis_conn"
            local redis_ok, redis_err = redis_conn.check_connection()
            
            return {
                redis_connected = redis_ok,
                redis_error = redis_err,
                server_time = ngx.time()
            }
        end
    },  -- 在这里添加逗号
    ["/api/cache/batch_delete"] = {
        POST = function()
            ngx.req.read_body()
            local data = ngx.req.get_body_data()
            local args = data and cjson.decode(data) or {}
            
            local keys = args.keys or {}
            local success_count = 0
            local errors = {}
            
            local cache_lib = require "cache_lib"
            
            for _, key in ipairs(keys) do
                local success, err = cache_lib.delete(key)
                if success then
                    success_count = success_count + 1
                else
                    table.insert(errors, { key = key, error = err })
                end
            end
            
            return { 
                success = #errors == 0, 
                message = success_count .. " 个缓存键已删除", 
                deleted_count = success_count,
                errors = errors
            }
        end
    },
    -- 在routes表中添加新的路由
    ["/api/cache/search"] = {
        GET = function()
            local args = ngx.req.get_uri_args()
            local keyword = args.keyword
            
            if not keyword then
                ngx.status = 400
                return { error = "Missing keyword parameter" }
            end
            
            local cache_lib = require "cache_lib"
            local results = cache_lib.search_cache_content(keyword)
            
            return { keys = results }
        end
    },
    -- 在routes表中添加新的路由
    ["api/cache/force_cache"] = {
        POST = function()
            ngx.req.read_body()
            local data = ngx.req.get_body_data()
            local args = data and cjson.decode(data) or {}
            
            local url = args.url
            local content = args.content
            local ttl = args.ttl
            
            if not url then
                ngx.status = 400
                return { error = "Missing URL parameter" }
            end
            
            local cache_lib = require "cache_lib"
            local success = cache_lib.force_cache_url(url, content, ttl)
            
            if success then
                -- 从未命中URL列表中移除
                cache_lib.remove_miss_url(url)
                return { success = true, message = "URL has been force cached" }
            else
                ngx.status = 500
                return { error = "Failed to force cache URL" }
            end
        end
    },
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