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

-- 添加Redis连接状态检查函数
function _M.check_connection()
    local red = redis:new()
    red:set_timeout(REDIS_CONFIG.timeout)
    
    local ok, err = red:connect(REDIS_CONFIG.host, REDIS_CONFIG.port)
    if not ok then
        ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
        return false, err
    end
    
    -- 尝试执行一个简单的PING命令
    local res, err = red:ping()
    if not res then
        ngx.log(ngx.ERR, "Failed to ping Redis: ", err)
        red:close()
        return false, err
    end
    
    -- 关闭连接
    _M.close_connection(red)
    
    return true
end

return _M