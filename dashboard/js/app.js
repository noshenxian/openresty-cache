// 全局变量
let currentSection = 'dashboard';
let hitRatioChart = null;
let memoryUsageChart = null;
let currentCacheKey = null;

// 初始化页面
document.addEventListener('DOMContentLoaded', function() {
    // 导航切换
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const targetId = this.getAttribute('href').substring(1);
            showSection(targetId);
            
            // 更新导航状态
            navLinks.forEach(l => l.classList.remove('active'));
            this.classList.add('active');
        });
    });
    
    // 初始化图表
    initCharts();
    
    // 加载初始数据
    loadDashboardData();
    
    // 绑定事件
    document.getElementById('refreshKeys').addEventListener('click', loadKeysData);
    document.getElementById('keySearch').addEventListener('input', filterKeys);
    document.getElementById('refreshMissUrls').addEventListener('click', loadMissUrlsData);
    document.getElementById('missUrlSearch').addEventListener('input', filterMissUrls);
    document.getElementById('flushButton').addEventListener('click', flushCache);
    document.getElementById('flushAllButton').addEventListener('click', flushAllCache);
    document.getElementById('deleteCache').addEventListener('click', deleteCurrentCache);
    
    // 自动刷新
    setInterval(loadDashboardData, 30000); // 每30秒刷新一次仪表盘数据
});

// 显示指定部分
function showSection(sectionId) {
    currentSection = sectionId;
    
    document.querySelectorAll('.section').forEach(section => {
        section.classList.remove('active');
    });
    
    document.getElementById(sectionId).classList.add('active');
    
    // 加载对应部分的数据
    if (sectionId === 'dashboard') {
        loadDashboardData();
    } else if (sectionId === 'keys') {
        loadKeysData();
    } else if (sectionId === 'miss_urls') {
        loadMissUrlsData();
    }
}

// 初始化图表
function initCharts() {
    // 命中率图表
    const hitRatioCtx = document.getElementById('hitRatioChart').getContext('2d');
    hitRatioChart = new Chart(hitRatioCtx, {
        type: 'pie',
        data: {
            labels: ['内存缓存命中', 'Redis缓存命中', '未命中'],
            datasets: [{
                data: [0, 0, 0],
                backgroundColor: ['#4CAF50', '#2196F3', '#F44336']
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'bottom'
                }
            }
        }
    });
    
    // 内存使用图表
    const memoryUsageCtx = document.getElementById('memoryUsageChart').getContext('2d');
    memoryUsageChart = new Chart(memoryUsageCtx, {
        type: 'bar',
        data: {
            labels: ['内存缓存', 'Redis缓存'],
            datasets: [{
                label: '已用空间',
                data: [0, 0],
                backgroundColor: ['#2196F3', '#FF9800']
            }]
        },
        options: {
            responsive: true,
            scales: {
                y: {
                    beginAtZero: true,
                    title: {
                        display: true,
                        text: '内存使用 (MB)'
                    }
                }
            }
        }
    });
}

// 加载仪表盘数据
async function loadDashboardData() {
    try {
        const response = await fetch('/api/cache/stats');
        const data = await response.json();
        
        // 更新图表数据
        updateCharts(data);
        
        // 更新统计表格
        updateStatsTable(data);
        
        // 如果当前在键列表页面，也更新键列表
        if (currentSection === 'keys') {
            updateKeysTable(data.recent_keys);
        }
    } catch (error) {
        console.error('加载仪表盘数据失败:', error);
    }
}

// 更新图表
function updateCharts(data) {
    // 更新命中率图表
    hitRatioChart.data.datasets[0].data = [
        data.memory_hit_count,
        data.redis_hit_count,
        data.miss_count
    ];
    hitRatioChart.update();
    
    // 更新内存使用图表
    const memoryUsageMB = data.memory_usage / (1024 * 1024);
    const redisUsedMemoryMB = (data.redis_used_memory || 0) / (1024 * 1024);
    
    memoryUsageChart.data.datasets[0].data = [
        memoryUsageMB.toFixed(2),
        redisUsedMemoryMB.toFixed(2)
    ];
    memoryUsageChart.update();
}

// 更新统计表格
function updateStatsTable(data) {
    const totalRequests = data.memory_hit_count + data.redis_hit_count + data.miss_count;
    const hitRatio = totalRequests > 0 ? 
        ((data.memory_hit_count + data.redis_hit_count) / totalRequests * 100).toFixed(2) : 
        '0.00';
    
    const memoryUsageMB = (data.memory_usage / (1024 * 1024)).toFixed(2);
    const memoryCapacityMB = (data.memory_capacity / (1024 * 1024)).toFixed(2);
    const redisUsedMemoryMB = data.redis_used_memory ? 
        (data.redis_used_memory / (1024 * 1024)).toFixed(2) : 
        'N/A';
    
    const statsHtml = `
        <tr>
            <td>总请求数</td>
            <td>${totalRequests}</td>
        </tr>
        <tr>
            <td>内存缓存命中</td>
            <td>${data.memory_hit_count}</td>
        </tr>
        <tr>
            <td>Redis缓存命中</td>
            <td>${data.redis_hit_count}</td>
        </tr>
        <tr>
            <td>未命中</td>
            <td>${data.miss_count}</td>
        </tr>
        <tr>
            <td>命中率</td>
            <td>${hitRatio}%</td>
        </tr>
        <tr>
            <td>内存缓存使用</td>
            <td>${memoryUsageMB} MB / ${memoryCapacityMB} MB</td>
        </tr>
        <tr>
            <td>Redis内存使用</td>
            <td>${redisUsedMemoryMB} MB</td>
        </tr>
    `;
    
    document.getElementById('statsTable').innerHTML = statsHtml;
}

// 加载键列表数据
async function loadKeysData() {
    try {
        const response = await fetch('/api/cache/keys');
        const data = await response.json();
        
        updateKeysTable(data.keys);
    } catch (error) {
        console.error('加载键列表失败:', error);
    }
}

// 更新键列表表格
function updateKeysTable(keys) {
    if (!keys || keys.length === 0) {
        document.getElementById('keysTable').innerHTML = '<tr><td colspan="3">没有缓存键</td></tr>';
        return;
    }
    
    const keysHtml = keys.map(item => {
        const date = new Date(item.time * 1000);
        const formattedTime = date.toLocaleString();
        
        return `
            <tr>
                <td>${item.key}</td>
                <td>${formattedTime}</td>
                <td>
                    <button class="btn btn-sm btn-info view-cache" data-key="${item.key}">
                        <i class="bi bi-eye"></i> 查看
                    </button>
                    <button class="btn btn-sm btn-danger delete-cache" data-key="${item.key}">
                        <i class="bi bi-trash"></i> 删除
                    </button>
                </td>
            </tr>
        `;
    }).join('');
    
    document.getElementById('keysTable').innerHTML = keysHtml;
    
    // 绑定查看和删除按钮事件
    document.querySelectorAll('.view-cache').forEach(button => {
        button.addEventListener('click', function() {
            const key = this.getAttribute('data-key');
            viewCacheDetail(key);
        });
    });
    
    document.querySelectorAll('.delete-cache').forEach(button => {
        button.addEventListener('click', function() {
            const key = this.getAttribute('data-key');
            deleteCache(key);
        });
    });
}

// 过滤键列表
function filterKeys() {
    const searchTerm = document.getElementById('keySearch').value.toLowerCase();
    const rows = document.querySelectorAll('#keysTable tr');
    
    rows.forEach(row => {
        const keyCell = row.querySelector('td:first-child');
        if (!keyCell) return;
        
        const key = keyCell.textContent.toLowerCase();
        if (key.includes(searchTerm)) {
            row.style.display = '';
        } else {
            row.style.display = 'none';
        }
    });
}

// 查看缓存详情
async function viewCacheDetail(key) {
    try {
        const response = await fetch(`/api/cache/item?key=${encodeURIComponent(key)}`);
        const data = await response.json();
        
        if (response.status === 404) {
            alert('缓存键不存在');
            return;
        }
        
        // 保存当前缓存键
        currentCacheKey = key;
        
        // 格式化JSON显示
        document.getElementById('cacheMetadata').textContent = JSON.stringify(data.metadata, null, 2);
        
        // 尝试解析缓存内容为JSON
        try {
            const contentObj = JSON.parse(data.value);
            document.getElementById('cacheContent').textContent = JSON.stringify(contentObj, null, 2);
        } catch (e) {
            document.getElementById('cacheContent').textContent = data.value;
        }
        
        // 显示模态框
        const modal = new bootstrap.Modal(document.getElementById('cacheDetailModal'));
        modal.show();
    } catch (error) {
        console.error('获取缓存详情失败:', error);
        alert('获取缓存详情失败');
    }
}

// 删除缓存
async function deleteCache(key) {
    if (!confirm(`确定要删除缓存键 "${key}" 吗？`)) {
        return;
    }
    
    try {
        const response = await fetch(`/api/cache/item?key=${encodeURIComponent(key)}`, {
            method: 'DELETE'
        });
        const data = await response.json();
        
        if (data.success) {
            alert('缓存删除成功');
            loadKeysData(); // 重新加载键列表
        } else {
            alert(`删除失败: ${data.error}`);
        }
    } catch (error) {
        console.error('删除缓存失败:', error);
        alert('删除缓存失败');
    }
}

// 删除当前查看的缓存
function deleteCurrentCache() {
    if (currentCacheKey) {
        deleteCache(currentCacheKey);
        
        // 关闭模态框
        const modal = bootstrap.Modal.getInstance(document.getElementById('cacheDetailModal'));
        modal.hide();
    }
}

// 清除缓存 - 优化版本
async function flushCache() {
    const prefix = document.getElementById('prefixInput').value;
    const confirmMessage = prefix ? 
        `确定要清除所有以 "${prefix}" 开头的缓存吗？` : 
        '确定要清除所有缓存吗？';
    
    if (!confirm(confirmMessage)) {
        return;
    }
    
    // 显示加载状态
    document.getElementById('flushResult').className = 'alert alert-info';
    document.getElementById('flushResult').textContent = '正在清除缓存...';
    
    try {
        const response = await fetch('/api/cache/flush', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ prefix: prefix })
        });
        
        // 检查HTTP状态码
        if (!response.ok) {
            throw new Error(`HTTP错误: ${response.status}`);
        }
        
        const data = await response.json();
        
        if (data.success) {
            document.getElementById('flushResult').className = 'alert alert-success';
            document.getElementById('flushResult').textContent = 
                `清除成功，共清除 ${data.count} 个缓存项`;
                
            // 重新加载数据
            loadDashboardData();
            if (currentSection === 'keys') {
                loadKeysData();
            }
        } else {
            document.getElementById('flushResult').className = 'alert alert-danger';
            document.getElementById('flushResult').textContent = 
                `清除失败: ${data.error || '未知错误'}`;
            console.error('清除缓存失败:', data.error);
        }
    } catch (error) {
        console.error('清除缓存失败:', error);
        document.getElementById('flushResult').className = 'alert alert-danger';
        document.getElementById('flushResult').textContent = `清除缓存失败: ${error.message || '连接服务器失败'}`;
    }
}

// 清除所有缓存 - 优化版本
async function flushAllCache() {
    if (!confirm('确定要清除所有缓存吗？这将删除系统中的所有缓存数据！')) {
        return;
    }
    
    // 显示加载状态
    document.getElementById('flushResult').className = 'alert alert-info';
    document.getElementById('flushResult').textContent = '正在清除所有缓存...';
    
    try {
        const response = await fetch('/api/cache/flush', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ prefix: '' })
        });
        
        // 检查HTTP状态码
        if (!response.ok) {
            throw new Error(`HTTP错误: ${response.status}`);
        }
        
        const data = await response.json();
        
        if (data.success) {
            document.getElementById('flushResult').className = 'alert alert-success';
            document.getElementById('flushResult').textContent = 
                `清除成功，共清除 ${data.count} 个缓存项`;
                
            // 重新加载数据
            loadDashboardData();
            if (currentSection === 'keys') {
                loadKeysData();
            }
        } else {
            document.getElementById('flushResult').className = 'alert alert-danger';
            document.getElementById('flushResult').textContent = 
                `清除失败: ${data.error || '未知错误'}`;
            console.error('清除所有缓存失败:', data.error);
        }
    } catch (error) {
        console.error('清除所有缓存失败:', error);
        document.getElementById('flushResult').className = 'alert alert-danger';
        document.getElementById('flushResult').textContent = `清除所有缓存失败: ${error.message || '连接服务器失败'}`;
    }
}

// 加载未命中URL数据
async function loadMissUrlsData() {
    try {
        const response = await fetch('/api/cache/miss_urls');
        const data = await response.json();
        
        updateMissUrlsTable(data.urls);
    } catch (error) {
        console.error('加载未命中URL失败:', error);
    }
}

// 更新未命中URL表格
function updateMissUrlsTable(urls) {
    if (!urls || urls.length === 0) {
        document.getElementById('missUrlsTable').innerHTML = '<tr><td colspan="4">没有未命中的URL</td></tr>';
        return;
    }
    
    const urlsHtml = urls.map(item => {
        const firstDate = new Date(item.first_time * 1000);
        const lastDate = new Date(item.last_time * 1000);
        const formattedFirstTime = firstDate.toLocaleString();
        const formattedLastTime = lastDate.toLocaleString();
        
        return `
            <tr>
                <td>${item.url}</td>
                <td>${item.count}</td>
                <td>${formattedFirstTime}</td>
                <td>${formattedLastTime}</td>
            </tr>
        `;
    }).join('');
    
    document.getElementById('missUrlsTable').innerHTML = urlsHtml;
}

// 过滤未命中URL
function filterMissUrls() {
    const searchTerm = document.getElementById('missUrlSearch').value.toLowerCase();
    const rows = document.querySelectorAll('#missUrlsTable tr');
    
    rows.forEach(row => {
        const urlCell = row.querySelector('td:first-child');
        if (!urlCell) return;
        
        const url = urlCell.textContent.toLowerCase();
        if (url.includes(searchTerm)) {
            row.style.display = '';
        } else {
            row.style.display = 'none';
        }
    });
}

// 添加一个通用的带重试功能的API调用函数
async function callApiWithRetry(url, method, body, maxRetries = 2) {
    let retries = 0;
    
    while (retries <= maxRetries) {
        try {
            const response = await fetch(url, {
                method: method,
                headers: {
                    'Content-Type': 'application/json'
                },
                body: body ? JSON.stringify(body) : undefined
            });
            
            if (!response.ok) {
                throw new Error(`HTTP错误: ${response.status}`);
            }
            
            return await response.json();
        } catch (error) {
            retries++;
            console.warn(`API调用失败，尝试重试 ${retries}/${maxRetries}:`, error);
            
            if (retries > maxRetries) {
                throw error;
            }
            
            // 等待一段时间再重试
            await new Promise(resolve => setTimeout(resolve, 1000 * retries));
        }
    }
}

// 使用重试机制的清除缓存函数
async function flushCacheWithRetry() {
    const prefix = document.getElementById('prefixInput').value;
    const confirmMessage = prefix ? 
        `确定要清除所有以 "${prefix}" 开头的缓存吗？` : 
        '确定要清除所有缓存吗？';
    
    if (!confirm(confirmMessage)) {
        return;
    }
    
    document.getElementById('flushResult').className = 'alert alert-info';
    document.getElementById('flushResult').textContent = '正在清除缓存...';
    
    try {
        const data = await callApiWithRetry('/api/cache/flush', 'POST', { prefix: prefix });
        
        if (data.success) {
            document.getElementById('flushResult').className = 'alert alert-success';
            document.getElementById('flushResult').textContent = 
                `清除成功，共清除 ${data.count} 个缓存项`;
                
            // 重新加载数据
            loadDashboardData();
            if (currentSection === 'keys') {
                loadKeysData();
            }
        } else {
            document.getElementById('flushResult').className = 'alert alert-danger';
            document.getElementById('flushResult').textContent = 
                `清除失败: ${data.error || '未知错误'}`;
        }
    } catch (error) {
        console.error('清除缓存失败:', error);
        document.getElementById('flushResult').className = 'alert alert-danger';
        document.getElementById('flushResult').textContent = `清除缓存失败: ${error.message || '连接服务器失败'}`;
    }
}

// 检查Redis连接状态
async function checkRedisConnection() {
    try {
        const response = await fetch('/api/cache/status');
        if (!response.ok) {
            return false;
        }
        
        const data = await response.json();
        return data.redis_connected === true;
    } catch (error) {
        console.error('检查Redis连接失败:', error);
        return false;
    }
}

// 在页面加载时检查Redis连接
async function initializeApp() {
    // 检查Redis连接
    const redisConnected = await checkRedisConnection();
    
    if (!redisConnected) {
        // 显示Redis连接警告
        const alertDiv = document.createElement('div');
        alertDiv.className = 'alert alert-warning';
        alertDiv.textContent = 'Redis连接失败，部分功能可能无法正常工作。';
        document.querySelector('.container').prepend(alertDiv);
    }
    
    // 加载初始数据
    loadDashboardData();
    loadKeysData();
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', initializeApp);

// 设置按钮加载状态
function setButtonLoading(buttonId, isLoading) {
    const button = document.getElementById(buttonId);
    if (!button) return;
    
    if (isLoading) {
        button.disabled = true;
        button.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> 处理中...';
    } else {
        button.disabled = false;
        button.innerHTML = button.getAttribute('data-original-text') || button.innerHTML;
    }
}

// 在页面加载时保存原始按钮文本
document.addEventListener('DOMContentLoaded', function() {
    const buttons = document.querySelectorAll('button');
    buttons.forEach(button => {
        button.setAttribute('data-original-text', button.innerHTML);
    });
});

// 使用按钮状态管理的清除缓存函数
async function flushCacheWithButtonState() {
    const prefix = document.getElementById('prefixInput').value;
    const confirmMessage = prefix ? 
        `确定要清除所有以 "${prefix}" 开头的缓存吗？` : 
        '确定要清除所有缓存吗？';
    
    if (!confirm(confirmMessage)) {
        return;
    }
    
    setButtonLoading('flushButton', true);
    document.getElementById('flushResult').className = 'alert alert-info';
    document.getElementById('flushResult').textContent = '正在清除缓存...';
    
    try {
        const response = await fetch('/api/cache/flush', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ prefix: prefix })
        });
        
        const data = await response.json();
        
        if (data.success) {
            document.getElementById('flushResult').className = 'alert alert-success';
            document.getElementById('flushResult').textContent = 
                `清除成功，共清除 ${data.count} 个缓存项`;
                
            // 重新加载数据
            loadDashboardData();
            if (currentSection === 'keys') {
                loadKeysData();
            }
        } else {
            document.getElementById('flushResult').className = 'alert alert-danger';
            document.getElementById('flushResult').textContent = 
                `清除失败: ${data.error || '未知错误'}`;
        }
    } catch (error) {
        console.error('清除缓存失败:', error);
        document.getElementById('flushResult').className = 'alert alert-danger';
        document.getElementById('flushResult').textContent = `清除缓存失败: ${error.message || '连接服务器失败'}`;
    } finally {
        setButtonLoading('flushButton', false);
    }
}