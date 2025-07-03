#!/bin/bash

# 定义颜色输出
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # 恢复默认颜色

echo -e "${YELLOW}正在重启OpenResty缓存服务...${NC}"

# 获取当前目录
CURRENT_DIR=$(pwd)

# 检查OpenResty进程并停止
echo -e "${YELLOW}停止当前运行的OpenResty服务...${NC}"
PID=$(ps -ef | grep "openresty" | grep -v grep | awk '{print $2}')
if [ -n "$PID" ]; then
    echo -e "${YELLOW}找到OpenResty进程 PID: $PID，正在停止...${NC}"
    kill -QUIT $PID
    sleep 2
    
    # 检查进程是否已经停止
    if ps -p $PID > /dev/null; then
        echo -e "${RED}OpenResty进程未能正常停止，尝试强制终止...${NC}"
        kill -9 $PID
        sleep 1
    fi
    
    echo -e "${GREEN}OpenResty服务已停止${NC}"
else
    echo -e "${YELLOW}未发现运行中的OpenResty进程${NC}"
fi

# 确保目录存在
mkdir -p logs

# 检查Redis是否运行
echo -e "${YELLOW}检查Redis服务...${NC}"
redis-cli ping > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}启动Redis...${NC}"
    # 如果Redis未安装，提示安装
    which redis-server > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Redis未安装，请先安装Redis${NC}"
        echo -e "${YELLOW}可以使用以下命令安装：brew install redis${NC}"
        exit 1
    fi
    
    # 启动Redis
    redis-server --daemonize yes
    echo -e "${GREEN}Redis服务已启动${NC}"
else
    echo -e "${GREEN}Redis服务已在运行${NC}"
fi

# 启动OpenResty
echo -e "${YELLOW}启动OpenResty缓存服务...${NC}"
openresty -p "$CURRENT_DIR" -c conf/nginx.conf

# 检查启动是否成功
sleep 2
PID=$(ps -ef | grep "openresty" | grep -v grep | awk '{print $2}')
if [ -n "$PID" ]; then
    echo -e "${GREEN}OpenResty服务已成功重启，PID: $PID${NC}"
    echo -e "${GREEN}服务已启动，访问 http://localhost:8080/dashboard/ 查看管理后台${NC}"
else
    echo -e "${RED}OpenResty服务启动失败，请检查错误日志${NC}"
    echo -e "${YELLOW}查看错误日志: cat logs/error.log${NC}"
    exit 1
fi