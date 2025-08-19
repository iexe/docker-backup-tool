#!/bin/bash

# Docker应用简化备份脚本
# 版本：3.1 - 修复版本，解决界面刷新问题

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 全局变量
BACKUP_DIR="/opt/docker_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)
LOG_FILE=""

# 打印函数
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
    echo -e "${NC}$message"
}

# 显示标题
show_title() {
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        Docker备份恢复系统 v3.1      ║${NC}"
    echo -e "${PURPLE}║           修复版本(稳定)            ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo ""
}

# 检查环境
check_environment() {
    if ! command -v docker &> /dev/null || ! docker ps &> /dev/null; then
        print_error "Docker未安装或服务未运行"
        return 1
    fi
    
    for cmd in tar gzip find date; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "缺少必要命令：$cmd"
            return 1
        fi
    done
    
    return 0
}

# 显示Docker状态
show_docker_status() {
    print_info "当前Docker环境："
    echo "  服务器：$HOSTNAME"
    echo "  Docker版本：$(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1)"
    
    local containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    if [ -n "$containers" ]; then
        echo "  运行中的容器："
        echo "$containers" | sed 's/^/    - /'
    else
        print_warning "没有运行中的容器"
    fi
    echo ""
}

# 备份容器配置
backup_container_config() {
    local container="$1"
    local backup_path="$2"
    
    log "备份容器 $container 的配置..."
    
    docker inspect "$container" > "$backup_path/container_config.json" 2>/dev/null
    docker inspect "$container" --format '{{.Config.Image}}' > "$backup_path/image_info.txt" 2>/dev/null
    docker inspect "$container" --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' > "$backup_path/env_vars.txt" 2>/dev/null
    docker inspect "$container" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} -> {{(index $conf 0).HostPort}}{{"\n"}}{{end}}{{end}}' > "$backup_path/port_mappings.txt" 2>/dev/null
    docker inspect "$container" --format '{{.HostConfig.RestartPolicy.Name}}{{if .HostConfig.RestartPolicy.MaximumRetryCount}}:{{.HostConfig.RestartPolicy.MaximumRetryCount}}{{end}}' > "$backup_path/restart_policy.txt" 2>/dev/null
    docker inspect "$container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.Type}}:{{.Mode}}{{"\n"}}{{end}}' > "$backup_path/mounts_info.txt" 2>/dev/null
}

# 备份数据卷
backup_container_volumes() {
    local container="$1"
    local backup_path="$2"
    
    log "备份容器 $container 的数据..."
    
    local mounts=$(docker inspect "$container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.Type}}{{"\n"}}{{end}}' 2>/dev/null)
    
    while IFS= read -r mount_line; do
        if [ -n "$mount_line" ]; then
            local source=$(echo "$mount_line" | cut -d':' -f1)
            local dest=$(echo "$mount_line" | cut -d':' -f2)
            local type=$(echo "$mount_line" | cut -d':' -f3)
            
            if [ "$type" = "bind" ] && [ -d "$source" ]; then
                log "备份绑定目录：$source"
                local dest_name=$(echo "$dest" | sed 's/\//_/g' | sed 's/^_//')
                tar -czf "$backup_path/mount_${dest_name}.tar.gz" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null
            elif [ "$type" = "volume" ]; then
                log "备份数据卷：$source"
                local volume_name=$(basename "$source")
                docker run --rm -v "$volume_name:/data" -v "$backup_path:/backup" alpine:latest tar czf "/backup/volume_${volume_name}.tar.gz" -C /data . 2>/dev/null
            fi
        fi
    done <<< "$mounts"
}

# 生成启动脚本
generate_startup_script() {
    local container="$1"
    local backup_path="$2"
    
    local image=$(cat "$backup_path/image_info.txt" 2>/dev/null)
    local restart_policy=$(cat "$backup_path/restart_policy.txt" 2>/dev/null)
    
    cat > "$backup_path/start_container.sh" << EOF
#!/bin/bash
# 容器 $container 启动脚本

CONTAINER_NAME="$container"
IMAGE="$image"

echo "=== 启动容器: \$CONTAINER_NAME ==="

docker stop "\$CONTAINER_NAME" 2>/dev/null || true
docker rm "\$CONTAINER_NAME" 2>/dev/null || true
docker pull "\$IMAGE"

DOCKER_CMD="docker run -d --name \$CONTAINER_NAME"

if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
    DOCKER_CMD="\$DOCKER_CMD --restart=$restart_policy"
fi

if [ -f "port_mappings.txt" ]; then
    while read -r port_line; do
        if [ -n "\$port_line" ]; then
            container_port=\$(echo "\$port_line" | cut -d' ' -f1)
            host_port=\$(echo "\$port_line" | cut -d' ' -f3)
            if [ -n "\$host_port" ] && [ "\$host_port" != "<nil>" ]; then
                DOCKER_CMD="\$DOCKER_CMD -p \$host_port:\$container_port"
            fi
        fi
    done < "port_mappings.txt"
fi

if [ -f "env_vars.txt" ]; then
    while read -r env_line; do
        if [ -n "\$env_line" ] && [[ "\$env_line" != PATH=* ]]; then
            DOCKER_CMD="\$DOCKER_CMD -e '\$env_line'"
        fi
    done < "env_vars.txt"
fi

if [ -f "mounts_info.txt" ]; then
    while read -r mount_line; do
        if [ -n "\$mount_line" ]; then
            source_path=\$(echo "\$mount_line" | cut -d':' -f1)
            dest_path=\$(echo "\$mount_line" | cut -d':' -f2)
            mount_type=\$(echo "\$mount_line" | cut -d':' -f3)
            
            if [ "\$mount_type" = "volume" ]; then
                volume_name=\$(basename "\$source_path")
                DOCKER_CMD="\$DOCKER_CMD -v \$volume_name:\$dest_path"
            elif [ "\$mount_type" = "bind" ] && [ -d "\$source_path" ]; then
                DOCKER_CMD="\$DOCKER_CMD -v \$source_path:\$dest_path"
            fi
        fi
    done < "mounts_info.txt"
fi

DOCKER_CMD="\$DOCKER_CMD \$IMAGE"

echo "执行命令: \$DOCKER_CMD"
eval "\$DOCKER_CMD"

if [ \$? -eq 0 ]; then
    echo "✅ 容器启动成功"
    docker ps --filter "name=\$CONTAINER_NAME"
else
    echo "❌ 容器启动失败"
fi
EOF
    
    chmod +x "$backup_path/start_container.sh"
}

# 执行完整备份
perform_backup() {
    local containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    
    if [ -z "$containers" ]; then
        print_error "没有运行中的容器"
        return 1
    fi
    
    # 创建备份目录和日志
    mkdir -p "$BACKUP_DIR"
    LOG_FILE="$BACKUP_DIR/backup_$TIMESTAMP.log"
    
    log "开始完整备份"
    log "备份容器：$(echo "$containers" | tr '\n' ' ')"
    
    local success=0
    
    # 备份每个容器
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            print_info "备份容器：$container"
            
            local container_backup_dir="$BACKUP_DIR/${container}_backup_$TIMESTAMP"
            mkdir -p "$container_backup_dir"
            
            backup_container_config "$container" "$container_backup_dir"
            backup_container_volumes "$container" "$container_backup_dir"
            generate_startup_script "$container" "$container_backup_dir"
            
            ((success++))
            print_success "容器 $container 备份完成"
        fi
    done <<< "$containers"
    
    # 创建系统信息
    cat > "$BACKUP_DIR/system_info_$TIMESTAMP.txt" << EOF
备份系统信息
=============
备份时间: $(date)
源服务器: $HOSTNAME
Docker版本: $(docker --version 2>/dev/null)
成功备份: $success 个容器

容器列表:
$(echo "$containers" | sed 's/^/- /')
EOF
    
    # 创建恢复脚本
    cat > "$BACKUP_DIR/restore_backup.sh" << 'RESTORE_SCRIPT'
#!/bin/bash
# Docker备份恢复脚本

RESTORE_DIR="/tmp/docker_restore_$(date +%s)"
BACKUP_FILE="$1"

if [ $# -eq 0 ]; then
    echo "使用方法: $0 <备份文件路径>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "备份文件不存在: $BACKUP_FILE"
    exit 1
fi

echo "开始恢复..."
mkdir -p "$RESTORE_DIR"
cd "$RESTORE_DIR"

echo "解压备份文件..."
tar -xzf "$BACKUP_FILE"

echo "恢复数据卷..."
for container_dir in *_backup_*/; do
    if [ -d "$container_dir" ]; then
        container_name=$(echo "$container_dir" | sed 's/_backup_.*\///')
        echo "处理容器: $container_name"
        
        cd "$container_dir"
        
        for volume_file in volume_*.tar.gz; do
            if [ -f "$volume_file" ]; then
                volume_name=$(echo "$volume_file" | sed 's/^volume_//' | sed 's/\.tar\.gz$//')
                echo "恢复数据卷: $volume_name"
                docker volume create "$volume_name" 2>/dev/null
                docker run --rm -v "$volume_name:/data" -v "$PWD:/backup" alpine:latest tar xzf "/backup/$volume_file" -C /data
            fi
        done
        
        for mount_file in mount_*.tar.gz; do
            if [ -f "$mount_file" ]; then
                mount_name=$(echo "$mount_file" | sed 's/^mount_//' | sed 's/\.tar\.gz$//')
                target_path="/opt/restored_data/$container_name/$mount_name"
                echo "恢复挂载目录到: $target_path"
                mkdir -p "$target_path"
                tar -xzf "$mount_file" -C "$target_path"
            fi
        done
        
        cd ..
    fi
done

echo "数据恢复完成！"
echo "恢复目录: $RESTORE_DIR"
echo ""
echo "启动容器："
for container_dir in *_backup_*/; do
    if [ -d "$container_dir" ] && [ -f "$container_dir/start_container.sh" ]; then
        container_name=$(echo "$container_dir" | sed 's/_backup_.*\///')
        echo "cd $RESTORE_DIR/$container_dir && ./start_container.sh  # 启动 $container_name"
    fi
done
RESTORE_SCRIPT
    
    chmod +x "$BACKUP_DIR/restore_backup.sh"
    
    # 创建压缩包
    log "创建备份压缩包..."
    local backup_archive="$BACKUP_DIR/docker_backup_${HOSTNAME}_$TIMESTAMP.tar.gz"
    
    # 删除旧备份
    find "$BACKUP_DIR" -name "docker_backup_*.tar.gz" -type f -delete 2>/dev/null
    
    cd "$BACKUP_DIR"
    tar -czf "docker_backup_${HOSTNAME}_$TIMESTAMP.tar.gz" *_backup_$TIMESTAMP/ system_info_$TIMESTAMP.txt restore_backup.sh 2>/dev/null
    
    # 清理临时文件
    rm -rf *_backup_$TIMESTAMP/ system_info_$TIMESTAMP.txt
    
    local backup_size=$(du -h "$backup_archive" | cut -f1)
    print_success "备份完成！"
    print_info "备份文件：$backup_archive ($backup_size)"
    print_info "恢复脚本：$BACKUP_DIR/restore_backup.sh"
    echo ""
    print_info "跨服务器恢复命令："
    echo "$BACKUP_DIR/restore_backup.sh $backup_archive"
    
    log "备份成功完成"
}

# 简单菜单（无循环）
simple_menu() {
    clear
    show_title
    show_docker_status
    
    echo "═══════════════════════════════════════"
    echo "Docker备份选项："
    echo "1) 执行完整备份"
    echo "2) 查看备份历史"
    echo "3) 显示帮助"
    echo ""
    
    read -p "请选择操作 (1-3，或按回车默认执行备份): " choice
    
    case "${choice:-1}" in
        1)
            print_info "开始执行完整备份..."
            perform_backup
            ;;
        2)
            show_backup_history
            ;;
        3)
            show_help
            ;;
        *)
            print_warning "无效选择，执行默认备份"
            perform_backup
            ;;
    esac
}

# 显示备份历史
show_backup_history() {
    echo ""
    print_info "备份历史记录"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_warning "备份目录不存在：$BACKUP_DIR"
        return
    fi
    
    local backups=$(find "$BACKUP_DIR" -name "docker_backup_*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [ -z "$backups" ]; then
        print_warning "没有找到备份文件"
        return
    fi
    
    echo "发现以下备份文件："
    while IFS= read -r backup; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  📦 $(basename "$backup") ($size) - $date"
    done <<< "$backups"
}

# 显示帮助
show_help() {
    echo ""
    echo "Docker备份恢复系统 v3.1 - 使用说明"
    echo ""
    echo "功能："
    echo "  🔄 完整备份（配置+数据卷+镜像信息）"
    echo "  🌐 跨服务器兼容"
    echo "  📦 自动压缩打包"
    echo "  🔧 自动生成恢复脚本"
    echo ""
    echo "使用方法："
    echo "  $(basename "$0")                    # 简单菜单"
    echo "  $(basename "$0") --auto             # 自动备份"
    echo "  $(basename "$0") --help             # 显示帮助"
    echo ""
    echo "远程使用："
    echo "  # 交互式远程执行（有10秒选择时间）"
    echo "  curl -fsSL URL/$(basename "$0") | bash"
    echo ""
    echo "  # 直接自动备份（无交互）"
    echo "  curl -fsSL URL/$(basename "$0") | bash -s -- --auto"
    echo ""
    echo "备份内容："
    echo "  • 容器配置和环境变量"
    echo "  • Docker数据卷"
    echo "  • 绑定挂载目录"
    echo "  • 自动生成的启动脚本"
    echo ""
    echo "恢复方法："
    echo "  1. 复制备份文件到目标服务器"
    echo "  2. 运行: ./restore_backup.sh 备份文件.tar.gz"
    echo "  3. 按提示启动容器"
    echo ""
}

# 检测管道执行
is_piped() {
    [ ! -t 0 ]
}

# 远程交互菜单（适用于管道执行）
remote_menu() {
    show_title
    show_docker_status
    
    echo "═══════════════════════════════════════"
    echo "远程Docker备份选项："
    echo "1) 🔄 立即执行完整备份（推荐）"
    echo "2) 📋 仅查看当前容器状态"
    echo "3) 📦 安装脚本到本地"
    echo "4) ❓ 显示帮助信息"
    echo ""
    
    # 给用户时间看清选项
    echo "请在10秒内选择操作（默认执行备份）："
    echo "输入数字1-4，或等待自动执行..."
    echo ""
    
    # 使用timeout读取用户输入
    local choice=""
    if command -v timeout >/dev/null 2>&1; then
        choice=$(timeout 10 bash -c 'read -p "您的选择: " choice; echo $choice' 2>/dev/null || echo "1")
    else
        # 如果没有timeout命令，直接执行备份
        choice="1"
        echo "自动选择：执行备份"
    fi
    
    case "${choice:-1}" in
        1)
            print_info "开始执行完整备份..."
            perform_backup
            ;;
        2)
            print_info "当前Docker容器状态："
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || print_error "无法获取容器信息"
            echo ""
            docker volume ls 2>/dev/null && echo "" || true
            print_info "如需备份，请重新运行脚本选择选项1"
            ;;
        3)
            install_to_local_simple
            ;;
        4)
            show_help
            ;;
        *)
            print_warning "无效选择或超时，执行默认备份"
            perform_backup
            ;;
    esac
}

# 简化的本地安装
install_to_local_simple() {
    local install_dir="/opt/docker-backup"
    local script_name="docker_backup_all_in_one.sh"
    local script_url="https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/$script_name"
    
    print_info "安装Docker备份工具到本地..."
    
    # 创建安装目录
    if ! mkdir -p "$install_dir" 2>/dev/null; then
        print_warning "无法创建 $install_dir，使用当前目录"
        install_dir="."
    fi
    
    local script_path="$install_dir/$script_name"
    
    # 下载脚本
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$script_url" -o "$script_path"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$script_url" -O "$script_path"
    else
        print_error "需要curl或wget命令来下载脚本"
        return 1
    fi
    
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        print_success "脚本已安装到：$script_path"
        
        mkdir -p /opt/docker_backups 2>/dev/null || true
        
        echo ""
        print_info "使用方法："
        echo "  $script_path                    # 本地交互界面"
        echo "  $script_path --auto             # 自动备份"
        echo "  $script_path --help             # 查看帮助"
        echo ""
        print_info "脚本已安装完成！可以在任何时候运行进行备份。"
    else
        print_error "下载失败"
        return 1
    fi
}

# 主函数
main() {
    case "${1:-}" in
        --auto)
            if ! check_environment; then
                exit 1
            fi
            print_info "自动备份模式"
            perform_backup
            ;;
        --help)
            show_help
            ;;
        *)
            if ! check_environment; then
                print_error "环境检查失败，请确保Docker正常运行"
                exit 1
            fi
            
            if is_piped; then
                print_info "检测到远程执行，启动交互模式"
                remote_menu
            else
                simple_menu
            fi
            ;;
    esac
}

# 运行主程序
main "$@"
