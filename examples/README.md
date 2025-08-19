# 使用示例

本目录包含Docker备份工具的各种使用示例。

## 📋 示例列表

### 1. 基础使用示例

```bash
# 启动交互式界面
./docker_backup_all_in_one.sh

# 自动完整备份
./docker_backup_all_in_one.sh --auto

# 查看帮助信息
./docker_backup_all_in_one.sh --help
```

### 2. 定时备份示例

```bash
# 配置每日备份
./docker_backup_all_in_one.sh
# 选择菜单项3（定时备份）
# 选择选项1（每天凌晨2点）

# 手动添加cron任务
echo "0 2 * * * /opt/docker-backup/docker_backup_all_in_one.sh --auto" | crontab -
```

### 3. 跨服务器备份恢复示例

#### 服务器A（源服务器）
```bash
# 执行备份
./docker_backup_all_in_one.sh --auto

# 查看备份文件
ls -la /opt/docker_backups/

# 复制到服务器B
scp /opt/docker_backups/docker_backup_*.tar.gz user@server-b:/tmp/
scp /opt/docker_backups/restore_backup.sh user@server-b:/tmp/
```

#### 服务器B（目标服务器）
```bash
# 下载备份工具
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-backup-tool/main/install.sh | bash

# 恢复备份
./restore_backup.sh /tmp/docker_backup_*.tar.gz

# 或使用工具恢复
./docker_backup_all_in_one.sh
# 选择菜单项2（恢复备份）
```

### 4. Docker Compose环境示例

```bash
# 停止compose服务
docker-compose down

# 执行备份
./docker_backup_all_in_one.sh --auto

# 在新服务器恢复后
# 1. 恢复数据
./restore_backup.sh backup_file.tar.gz

# 2. 恢复compose配置（需要手动复制docker-compose.yml）
# 3. 启动服务
docker-compose up -d
```

### 5. 批量部署示例

```bash
#!/bin/bash
# 批量部署脚本

SERVERS=("server1.com" "server2.com" "server3.com")

for server in "${SERVERS[@]}"; do
    echo "部署到 $server..."
    
    # 安装工具
    ssh root@$server "curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-backup-tool/main/install.sh | bash -s -- 1"
    
    # 配置定时备份
    ssh root@$server "echo '0 2 * * * /opt/docker-backup/docker_backup_all_in_one.sh --auto' | crontab -"
    
    echo "$server 部署完成"
done
```

### 6. 灾难恢复示例

```bash
# 场景：服务器故障，需要在新服务器恢复服务

# 1. 在新服务器安装Docker
curl -fsSL https://get.docker.com | sh
systemctl start docker
systemctl enable docker

# 2. 安装备份工具
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-backup-tool/main/install.sh | bash

# 3. 从备份存储获取备份文件（示例使用rsync）
rsync -avz backup-server:/backups/docker_backup_*.tar.gz /tmp/

# 4. 恢复数据和容器
./docker_backup_all_in_one.sh
# 选择恢复备份，指定备份文件

# 5. 验证服务正常运行
docker ps
curl http://localhost:port  # 测试应用
```

### 7. 自动化备份脚本示例

```bash
#!/bin/bash
# advanced_backup.sh - 高级备份脚本示例

# 配置
BACKUP_TOOL="/opt/docker-backup/docker_backup_all_in_one.sh"
REMOTE_SERVER="backup-server.com"
REMOTE_PATH="/backups/docker/"
NOTIFICATION_EMAIL="admin@example.com"

# 执行备份
echo "开始备份..."
if $BACKUP_TOOL --auto; then
    echo "备份成功"
    
    # 同步到远程服务器
    rsync -avz /opt/docker_backups/ $REMOTE_SERVER:$REMOTE_PATH
    
    # 发送成功通知
    echo "Docker备份成功完成" | mail -s "备份成功 - $(date)" $NOTIFICATION_EMAIL
else
    echo "备份失败"
    
    # 发送失败通知
    echo "Docker备份失败，请检查系统" | mail -s "备份失败 - $(date)" $NOTIFICATION_EMAIL
    exit 1
fi
```

### 8. 监控和告警示例

```bash
#!/bin/bash
# backup_monitor.sh - 备份监控脚本

BACKUP_DIR="/opt/docker_backups"
MAX_AGE_HOURS=25  # 超过25小时认为备份过期

# 检查最新备份
LATEST_BACKUP=$(find $BACKUP_DIR -name "docker_backup_*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -z "$LATEST_BACKUP" ]; then
    echo "警告：没有找到备份文件"
    exit 1
fi

# 检查备份时间
BACKUP_TIME=$(stat -c %Y "$LATEST_BACKUP")
CURRENT_TIME=$(date +%s)
AGE_HOURS=$(( (CURRENT_TIME - BACKUP_TIME) / 3600 ))

if [ $AGE_HOURS -gt $MAX_AGE_HOURS ]; then
    echo "警告：备份文件过期，最后备份时间：$AGE_HOURS 小时前"
    exit 1
else
    echo "正常：最新备份时间：$AGE_HOURS 小时前"
fi

# 检查备份文件完整性
if tar -tzf "$LATEST_BACKUP" >/dev/null 2>&1; then
    echo "正常：备份文件完整性检查通过"
else
    echo "错误：备份文件损坏"
    exit 1
fi
```

## 📝 注意事项

1. **权限要求**：确保运行用户有Docker权限
2. **存储空间**：备份前检查磁盘空间
3. **网络连接**：跨服务器传输需要网络连接
4. **测试恢复**：定期测试备份恢复流程
5. **监控告警**：建议配置备份监控和告警

## 🔗 相关资源

- [主项目README](../README.md)
- [更新日志](../CHANGELOG.md)
- [问题报告](https://github.com/YOUR_USERNAME/docker-backup-tool/issues)
