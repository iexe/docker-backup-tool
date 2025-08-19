#!/bin/bash

# Docker备份工具一键安装脚本
# 用于从GitHub远程安装

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 配置变量
GITHUB_REPO="YOUR_USERNAME/docker-backup-tool"
SCRIPT_NAME="docker_backup_all_in_one.sh"
INSTALL_DIR="/opt/docker-backup"
SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/${SCRIPT_NAME}"

print_info "Docker备份工具一键安装"
echo ""

# 检查系统环境
print_info "检查系统环境..."

# 检查是否为Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_error "仅支持Linux系统"
    exit 1
fi

# 检查必要命令
for cmd in curl wget docker tar; do
    if ! command -v "$cmd" &> /dev/null; then
        print_error "缺少必要命令：$cmd"
        exit 1
    fi
done

# 检查Docker
if ! docker ps &> /dev/null; then
    print_error "Docker服务未运行或权限不足"
    exit 1
fi

print_success "系统环境检查通过"

# 选择安装方式
echo ""
echo "安装方式："
echo "1) 安装到 /opt/docker-backup （推荐）"
echo "2) 安装到当前目录"
echo "3) 仅下载，不安装"

while true; do
    read -p "请选择 (1-3): " choice
    case $choice in
        1)
            INSTALL_DIR="/opt/docker-backup"
            break
            ;;
        2)
            INSTALL_DIR="$(pwd)"
            break
            ;;
        3)
            INSTALL_DIR="$(pwd)"
            ONLY_DOWNLOAD=true
            break
            ;;
        *)
            print_error "请输入1-3"
            ;;
    esac
done

# 创建安装目录
if [ "$INSTALL_DIR" != "$(pwd)" ]; then
    print_info "创建安装目录：$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
fi

# 下载脚本
print_info "从GitHub下载脚本..."
TEMP_FILE="/tmp/$SCRIPT_NAME"

if command -v curl &> /dev/null; then
    curl -fsSL "$SCRIPT_URL" -o "$TEMP_FILE"
elif command -v wget &> /dev/null; then
    wget -q "$SCRIPT_URL" -O "$TEMP_FILE"
else
    print_error "需要curl或wget命令"
    exit 1
fi

if [ ! -f "$TEMP_FILE" ]; then
    print_error "下载失败"
    exit 1
fi

print_success "脚本下载完成"

# 安装脚本
TARGET_FILE="$INSTALL_DIR/$SCRIPT_NAME"

if [ "$INSTALL_DIR" != "$(pwd)" ]; then
    sudo cp "$TEMP_FILE" "$TARGET_FILE"
    sudo chmod +x "$TARGET_FILE"
else
    cp "$TEMP_FILE" "$TARGET_FILE"
    chmod +x "$TARGET_FILE"
fi

rm -f "$TEMP_FILE"

if [ "${ONLY_DOWNLOAD:-false}" = "true" ]; then
    print_success "脚本已下载到：$TARGET_FILE"
    exit 0
fi

print_success "脚本已安装到：$TARGET_FILE"

# 创建符号链接
if [ "$INSTALL_DIR" != "$(pwd)" ] && [ -w "/usr/local/bin" ]; then
    read -p "是否创建全局命令 'docker-backup'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo ln -sf "$TARGET_FILE" "/usr/local/bin/docker-backup"
        print_success "全局命令已创建：docker-backup"
    fi
fi

# 创建备份目录
sudo mkdir -p /opt/docker_backups
print_success "备份目录已创建：/opt/docker_backups"

# 显示完成信息
echo ""
print_success "🎉 安装完成！"
echo ""
echo "使用方法："
if command -v docker-backup &>/dev/null; then
    echo "  docker-backup                    # 启动交互式界面"
    echo "  docker-backup --auto             # 执行自动备份"
    echo "  docker-backup --help             # 查看帮助"
else
    echo "  cd $INSTALL_DIR"
    echo "  ./$SCRIPT_NAME                   # 启动交互式界面"
    echo "  ./$SCRIPT_NAME --auto            # 执行自动备份"
    echo "  ./$SCRIPT_NAME --help            # 查看帮助"
fi
echo ""

# 询问是否立即运行
read -p "是否现在启动备份工具? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v docker-backup &>/dev/null; then
        docker-backup
    else
        cd "$INSTALL_DIR" && "./$SCRIPT_NAME"
    fi
fi
