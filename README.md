# Docker Backup & Restore Tool

🐳 一个功能完整的Docker应用备份恢复工具，支持交互式操作、多种备份模式和跨服务器部署。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Language-Shell-green.svg)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-Compatible-blue.svg)](https://www.docker.com/)
[![Linux](https://img.shields.io/badge/OS-Linux-orange.svg)](https://www.linux.org/)

## ✨ 特性

- 🎯 **单文件解决方案** - 仅需一个脚本文件，包含所有功能
- 🎨 **交互式界面** - 彩色菜单，操作简单直观
- 🔄 **多种备份模式** - 完整备份/仅配置/仅数据/自定义选择
- ⏰ **定时备份** - 支持多种时间策略配置
- 🌐 **跨服务器兼容** - 备份文件可在任何Linux系统恢复
- 🔧 **智能恢复** - 自动生成容器启动脚本
- 📦 **自动压缩** - 新备份自动替换旧备份，节省空间
- 📁 **自定义目录** - 可配置备份文件存储位置
- 🔄 **替换备份** - 新备份自动覆盖旧备份，避免冗余文件
- 📝 **详细日志** - 完整的操作记录和错误追踪

## 🚀 快速开始

### 一键远程使用


- **安装到本地（推荐） - 下载脚本到本地使用**
```bash
curl -fsSL https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/docker_backup_all_in_one.sh | bash -s -- --install
```
- **自动备份- 直接执行备份**
```bash
curl -fsSL https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/docker_backup_all_in_one.sh | bash -s -- --auto
```
- **默认模式 - 5秒倒计时后自动备份（可Ctrl+C取消）**
```bash
curl -fsSL https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/docker_backup_all_in_one.sh | bash
```

#### 💡 远程执行说明

- **推荐使用 `--auto` 参数**：直接执行备份，无延迟
- **使用 `--install` 参数**：安装到本地后可完整使用所有功能  
- **默认模式**：由于管道限制无法真正交互，会显示提示后自动备份


启动后会显示完整功能菜单：
```
Docker备份管理系统：
1) 🔄 执行备份          # 4种备份模式可选
2) 📥 恢复备份          # 智能恢复系统
3) ⏰ 配置定时备份      # 多种时间策略
4) 📋 查看备份历史      # 备份文件管理
5) 📁 配置备份目录      # 自定义备份位置
6) 🔧 备份模式选择      # 详细功能说明
7) ❓ 显示帮助          # 完整使用指南
8) 🚪 退出
```

### 自动备份模式

```bash
# 执行完整自动备份
./docker_backup_all_in_one.sh --auto

# 安装到本地系统
./docker_backup_all_in_one.sh --install

# 查看帮助信息
./docker_backup_all_in_one.sh --help
```

## 🔧 备份模式

| 模式 | 描述 | 适用场景 |
|------|------|----------|
| **完整备份** | 容器配置 + 数据卷 + 镜像信息 | 生产环境、服务器迁移 |
| **仅配置** | 容器配置 + 环境变量 | 快速配置备份 |
| **仅数据** | 数据卷 + 挂载目录 | 数据安全备份 |
| **自定义** | 手动选择容器 | 特定容器备份 |

## ⏰ 定时备份配置

支持多种定时策略：

- 每天凌晨2点
- 每周日凌晨2点
- 每月1号凌晨2点
- 自定义Cron表达式

配置后会自动添加到系统crontab中。

## 🌐 跨服务器恢复

### 步骤1：在源服务器备份

```bash
# 执行备份
./docker_backup_all_in_one.sh --auto

# 查看备份文件
ls -la /opt/docker_backups/
```

### 步骤2：传输到目标服务器

```bash
# 复制备份文件
scp /opt/docker_backups/docker_backup_*.tar.gz user@target-server:/tmp/

# 复制恢复脚本（如果需要）
scp /opt/docker_backups/restore_backup.sh user@target-server:/tmp/
```

### 步骤3：在目标服务器恢复

```bash
# 方法1：使用本工具恢复
./docker_backup_all_in_one.sh
# 选择菜单项2（恢复备份）

# 方法2：直接使用恢复脚本
./restore_backup.sh /tmp/docker_backup_*.tar.gz
```

## 📦 备份内容

每次备份包含以下内容：

### 容器配置
- 完整的容器配置（JSON格式）
- 环境变量和启动参数
- 端口映射和网络配置
- 重启策略和健康检查
- 标签和元数据

### 数据文件
- Docker数据卷（完整备份）
- 绑定挂载目录
- 配置文件和应用数据

### 自动化脚本
- 容器启动脚本（自动生成）
- 批量恢复脚本
- 系统环境信息

## 🛠️ 系统要求

### 基础要求
- **操作系统**: 任何Linux发行版
- **Docker**: 17.06 或更高版本
- **权限**: root用户或docker组成员
- **磁盘空间**: 建议至少为容器数据总大小的2倍

### 依赖命令
脚本仅依赖基础Linux命令：
- `docker` - Docker引擎
- `tar` - 压缩解压
- `gzip` - 压缩工具
- `find` - 文件查找
- `date` - 时间处理
- `crontab` - 定时任务（可选）

### 兼容性测试

✅ **已测试的系统**:
- Ubuntu 18.04/20.04/22.04
- CentOS 7/8/Stream
- Debian 9/10/11
- RHEL 7/8/9
- Alpine Linux
- 宝塔面板环境

## 🔒 安全特性

### 数据保护
- 非破坏性操作设计
- 操作前确认提示
- 完整的操作日志记录
- 支持备份文件加密（可选）

### 权限控制
```bash
# 设置备份目录权限
chmod 700 /opt/docker_backups

# 限制脚本访问权限
chmod 750 docker_backup_all_in_one.sh
```

## 📊 性能表现

### 测试环境
- **系统**: Linux 5.10.0-32-cloud-amd64
- **Docker**: v27.2.0
- **容器数量**: 3个（memos, moontv, libretv）

### 测试结果
- **备份时间**: ~47秒
- **备份大小**: 221MB（完整备份）
- **成功率**: 100%
- **恢复时间**: <2分钟

## 🐛 故障排除

### 常见问题

#### 1. 权限错误
```bash
# 添加用户到docker组
sudo usermod -aG docker $USER

# 或者使用sudo运行
sudo ./docker_backup_all_in_one.sh
```

#### 2. 磁盘空间不足
```bash
# 清理Docker缓存
docker system prune -a

# 检查磁盘使用
df -h
```

#### 3. 容器启动失败
```bash
# 检查端口占用
netstat -tlnp | grep :端口号

# 查看容器日志
docker logs 容器名

# 检查镜像是否存在
docker images
```

#### 4. 远程执行问题
```bash
# 如果 curl | bash 执行失败，可以先下载到本地
wget https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/docker_backup_all_in_one.sh
chmod +x docker_backup_all_in_one.sh
./docker_backup_all_in_one.sh

# 或者使用安装模式
curl -fsSL https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/docker_backup_all_in_one.sh | bash -s -- --install
```

#### 5. 恢复脚本问题
- 检查备份文件完整性：`tar -tzf 备份文件.tar.gz`
- 确认目标路径权限正确
- 手动调整启动脚本中的挂载路径

### 调试模式

```bash
# 启用详细输出
bash -x ./docker_backup_all_in_one.sh --auto

# 查看备份日志
tail -f /opt/docker_backups/backup_*.log
```

## 📝 更新日志

### v3.0 (当前版本)
- ✨ 全新单文件架构设计
- ✨ 交互式彩色界面
- ✨ 智能备份模式选择
- ✨ 增强的跨服务器兼容性
- ✨ 自动生成恢复脚本
- ✨ 完善的错误处理机制

## 🤝 贡献指南

我们欢迎任何形式的贡献！

### 如何贡献
1. Fork 这个项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 报告问题
如果您发现bug或有功能建议，请[创建Issue](https://github.com/moli-xia/docker-backup-tool/issues)。

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- 感谢所有Docker社区的贡献者
- 感谢使用和测试此工具的用户们

## 🆕 版本 3.2 新功能

### 📁 自定义备份目录
- **灵活配置**：用户可以自定义备份文件存储位置
- **配置持久化**：配置自动保存到 `~/.docker_backup_config`
- **自动加载**：下次使用时自动加载保存的配置
- **目录管理**：自动创建目录并验证权限

### 🔄 替换备份模式
- **新备份替换旧备份**：不再累积多个备份文件
- **固定文件名**：使用 `docker_backup_{主机名}_latest.tar.gz` 格式
- **节省空间**：避免占用过多存储空间
- **简化管理**：始终只保留一个最新的备份文件

### 🔧 配置界面
```
📁 配置备份目录
当前备份目录: /opt/docker_backups
默认备份目录: /opt/docker_backups

1) 使用默认目录 (/opt/docker_backups)
2) 自定义备份目录  
3) 查看当前配置
4) 返回主菜单
```

### 💾 配置文件格式
```bash
# Docker备份配置文件
BACKUP_DIR="/your/custom/backup/directory"
```

## 📞 支持

如果您觉得这个项目有用，请给它一个 ⭐️

### 获取帮助
- 📖 查看脚本内置帮助：`./docker_backup_all_in_one.sh --help`
- 🐛 报告问题：[GitHub Issues](https://github.com/moli-xia/docker-backup-tool/issues)
- 💬 讨论交流：[GitHub Discussions](https://github.com/moli-xia/docker-backup-tool/discussions)

---

**让Docker应用备份变得简单而可靠！** 🚀
