# Copilot AI Agent Instructions for docker-backup-tool

## 项目概览
- 本项目为**单文件 Shell 脚本**实现的 Docker 应用备份与恢复工具，主入口为 `docker_backup_all_in_one.sh`。
- 支持交互式菜单、自动/定时备份、跨服务器恢复、配置持久化、日志记录等。
- 所有核心逻辑均在该脚本内实现，无多文件依赖。

## 主要结构与数据流
- **备份流程**：
  1. 选择备份模式（完整/仅配置/仅数据/自定义）。
  2. 遍历目标容器，导出配置、环境变量、端口、挂载、数据卷。
  3. 生成启动脚本、系统信息、恢复脚本。
  4. 打包为 `docker_backup_{主机名}_latest.tar.gz`，仅保留最新备份。
- **恢复流程**：
  1. 解压备份包，恢复数据卷（自动）、挂载目录（需手动确认）。
  2. 提供自动生成的 `start_container.sh` 启动脚本。
- **配置持久化**：备份目录等配置写入 `~/.docker_backup_config`，每次启动自动加载。
- **日志**：每次备份生成 `backup_*.log`，便于追踪。

## 关键开发/调试命令
- 一键自动备份：`./docker_backup_all_in_one.sh --auto`
- 交互菜单：`./docker_backup_all_in_one.sh`
- 安装到本地：`./docker_backup_all_in_one.sh --install`
- 查看帮助：`./docker_backup_all_in_one.sh --help`
- 调试模式：`bash -x ./docker_backup_all_in_one.sh --auto`
- 查看日志：`tail -f /opt/docker_backups/backup_*.log`

## 项目约定与特殊模式
- **备份文件始终为单一最新包**，命名为 `docker_backup_{主机名}_latest.tar.gz`，避免空间浪费。
- **自定义备份目录**通过菜单或配置文件设置，默认 `/opt/docker_backups`。
- **恢复脚本**自动生成，位于备份目录，支持跨服务器恢复。
- **绑定挂载目录**恢复需人工确认，脚本仅提示不自动写入主机路径。
- **所有菜单/输出均为彩色，便于交互体验。**

## 重要文件/目录
- `docker_backup_all_in_one.sh`：主脚本，所有功能入口。
- `~/.docker_backup_config`：用户配置持久化。
- `/opt/docker_backups/`（或自定义目录）：备份文件、日志、恢复脚本存放地。
- `examples/`：用法示例与文档。

## 外部依赖
- 仅依赖基础 Linux 命令：`docker`、`tar`、`gzip`、`find`、`date`、`crontab`。
- 恢复/打包数据卷时临时拉取 `alpine:latest` 镜像。

## 贡献与调试建议
- 所有新功能建议以菜单项或参数形式集成，保持单文件架构。
- 变更备份/恢复流程时，务必同步更新自动生成的恢复脚本逻辑。
- 参考 `README.md` 获取最新功能说明和用户场景。

---
如需更多上下文，请优先查阅 `README.md` 与主脚本注释。
