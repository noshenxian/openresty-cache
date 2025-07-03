#!/bin/bash

# 确保目录存在
mkdir -p logs

# 检查Redis是否运行
redis-cli ping > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "启动Redis..."
    # 如果Redis未安装，提示安装
    which redis-server > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Redis未安装，请先安装Redis"
        echo "可以使用以下命令安装：brew install redis"
        exit 1
    fi
    
    # 启动Redis
    redis-server --daemonize yes
fi

# 启动OpenResty
echo "启动OpenResty缓存服务..."
openresty -p `pwd` -c conf/nginx.conf

echo "服务已启动，访问 http://localhost:8080/dashboard/ 查看管理后台"