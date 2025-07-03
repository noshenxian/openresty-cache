# OpenResty缓存管理系统
## 项目简介
自娱自乐的项目，仅供娱乐。

OpenResty缓存管理系统是一个基于OpenResty（Nginx + Lua）构建的高性能、多级缓存解决方案，提供了完整的缓存管理功能和可视化界面。该系统实现了内存缓存和Redis缓存的多级缓存架构，适用于高流量网站和API服务的性能优化。

## 功能特点
- 多级缓存架构 ：结合内存缓存(shared dict)和Redis缓存，提供高效的缓存访问
- 可视化管理界面 ：直观的Web界面，轻松监控和管理缓存
- 实时统计 ：缓存命中率、内存使用情况等关键指标的实时监控
- 灵活的缓存策略 ：支持按URL、查询参数等条件进行缓存，可自定义缓存TTL
- 未命中URL记录 ：记录并展示缓存未命中的URL，帮助优化缓存策略
## 系统架构
系统基于OpenResty构建，主要组件包括：

- Nginx核心 ：处理HTTP请求和响应
- Lua脚本 ：实现缓存逻辑和API
- 共享内存 ：存储缓存数据和元数据
- Redis ：提供持久化的二级缓存
- Web界面 ：基于Bootstrap构建的管理界面
## 安装要求
- OpenResty 1.19.3.1+
- Redis 5.0+
- 现代浏览器（支持ES6和Fetch API）
## 快速开始
### 安装
1. 克隆仓库：
```
git clone https://github.com/noshenxian/
openresty-cache.git
cd openresty-cache
```
2. 配置Redis连接（编辑 conf/nginx.conf ）：
```
init_by_lua_block {
    require "resty.core"
    local redis_config = {
        host = "127.0.0.1",  -- 修改为你的Redis服务器
        地址
        port = 6379,         -- 修改为你的Redis端口
        timeout = 1000,
        pool_size = 100,
        idle_timeout = 10000
    }
    _G.REDIS_CONFIG = redis_config
}
```
3. 启动服务：
```
openresty -p $PWD/ -c conf/nginx.conf
```
4. 访问管理界面：
在浏览器中打开 http://localhost:8080/dashboard/

## 主要功能
### 仪表盘
仪表盘提供了缓存系统的整体视图，包括：

- 缓存命中率统计图表
- 内存使用情况图表
- 详细的缓存统计信息
### 缓存键管理
- 查看最近访问的缓存键列表
- 搜索特定的缓存键
- 查看缓存内容和元数据
- 删除特定的缓存项
### 未命中URL列表
- 查看缓存未命中的URL列表
- 显示未命中次数和时间信息
- 搜索特定的未命中URL
### 缓存清除
- 按前缀清除缓存
- 清除所有缓存
## 配置说明
系统的主要配置位于 conf/nginx.conf 文件中，包括：

- 共享内存区域大小配置
- Redis连接配置
- 缓存服务器配置
- 代理缓存配置
## 开发指南
### 目录结构
```
├── conf/                # Nginx配置文件
├── dashboard/           # Web管理界面
│   ├── css/             # 样式文件
│   ├── js/              # JavaScript文件
│   └── index.html       # 主页面
├── lua/                 # Lua脚本
│   ├── api/             # API处理
│   ├── cache/           # 缓存处理逻辑
│   └── lib/             # 库文件
└── logs/                # 日志文件
```
### 核心模块
- cache_lib.lua ：缓存操作的核心库，实现了多级缓存的获取、设置、删除等功能
- router.lua ：API路由处理，提供缓存统计、缓存键管理等API
- access.lua ：请求处理的入口，实现缓存命中判断和处理
## 许可证
MIT License

## 贡献指南
欢迎提交问题和功能请求！

## 联系方式
如有任何问题或建议，请通过以下方式联系我们：
