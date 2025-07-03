local redis = require "resty.redis"

local _M = {}

function _M.get_connection()
    local red = redis:new()
    red:set_timeout(REDIS_CONFIG.timeout)
    
    local ok, err = red:connect(REDIS_CONFIG.host, REDIS_CONFIG.port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        return nil, err
    end
    
    -- 如果需要密码认证
    -- local auth_ok, auth_err = red:auth("password")
    -- if not auth_ok then
    --     ngx.log(ngx.ERR, "Failed to authenticate with Redis: ", auth_err)
    --     return nil, auth_err
    -- end
    
    return red
end

function _M.close_connection(red)
    if not red then
        return
    end
    
    -- 将连接放回连接池
    local ok, err = red:set_keepalive(
        REDIS_CONFIG.idle_timeout, 
        REDIS_CONFIG.pool_size
    )
    
    if not ok then
        ngx.log(ngx.ERR, "Failed to set Redis keepalive: ", err)
        red:close()
    end
end

return _M