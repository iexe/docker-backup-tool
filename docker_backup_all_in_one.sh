#!/bin/bash
# Docker应用简化备份脚本
# 版本：3.3.0 - 修复版本，解决空包问题和代码冗余
# 2025/10/16  修复清除旧备份逻辑错误。清楚应该在脚本执行之前，但是现在是脚本执行后已经备份的内容被清除后才创建的备份压缩包文件。修复使用GeMini 2.5 pro
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 全局变量
DEFAULT_BACKUP_DIR="/opt/docker_backups"
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)
LOG_FILE=""
CONFIG_FILE="$HOME/.docker_backup_config"

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

# 加载配置
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
# Docker备份配置文件
BACKUP_DIR="$BACKUP_DIR"
EOF
    print_success "配置已保存到 $CONFIG_FILE"
}

# 配置备份目录
configure_backup_dir() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 配置备份目录"
    echo ""
    echo "当前备份目录: $BACKUP_DIR"
    echo "默认备份目录: $DEFAULT_BACKUP_DIR"
    echo ""
    echo "1) 使用默认目录 ($DEFAULT_BACKUP_DIR)"
    echo "2) 自定义备份目录"
    echo "3) 查看当前配置"
    echo "4) 返回主菜单"
    echo ""
    
    read -p "请选择 (1-4): " choice
    
    case $choice in
        1)
            BACKUP_DIR="$DEFAULT_BACKUP_DIR"
            save_config
            print_info "已设置为默认目录: $BACKUP_DIR"
            ;;
        2)
            read -p "请输入新的备份目录路径: " new_dir
            if [ -n "$new_dir" ]; then
                # 创建目录（如果不存在）
                if mkdir -p "$new_dir" 2>/dev/null; then
                    BACKUP_DIR="$new_dir"
                    save_config
                    print_success "备份目录已设置为: $BACKUP_DIR"
                else
                    print_error "无法创建目录: $new_dir"
                fi
            else
                print_warning "未输入目录路径"
            fi
            ;;
        3)
            echo ""
            print_info "当前配置："
            echo "备份目录: $BACKUP_DIR"
            echo "配置文件: $CONFIG_FILE"
            echo "目录状态: $([ -d "$BACKUP_DIR" ] && echo "存在" || echo "不存在")"
            if [ -d "$BACKUP_DIR" ]; then
                echo "目录大小: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "未知")"
                echo "备份文件数: $(find "$BACKUP_DIR" -name "docker_backup_*.tar.gz" 2>/dev/null | wc -l)"
            fi
            ;;
        4)
            return
            ;;
        *)
            print_error "请输入1-4"
            sleep 1
            configure_backup_dir
            return
            ;;
    esac
    
    echo ""
    read -p "按回车继续..." -r
    configure_backup_dir
}

# 显示标题
show_title() {
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║      Docker备份恢复系统 v3.3.0       ║${NC}"
    echo -e "${PURPLE}║           修复版本 (稳定)            ║${NC}"
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

# 执行指定模式的备份
perform_backup_mode() {
    local mode=$1
    local containers=""
    
    # 创建备份目录和日志
    mkdir -p "$BACKUP_DIR"
    LOG_FILE="$BACKUP_DIR/backup_$TIMESTAMP.log"

    # --- 修复：在备份开始前清理旧的临时文件和最终压缩包，确保全新开始 ---
    print_info "清理旧备份文件（替换模式）..."
    find "$BACKUP_DIR" -name "docker_backup_*.tar.gz" -type f -delete 2>/dev/null
    find "$BACKUP_DIR" -name "*_backup_*" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$BACKUP_DIR" -name "system_info_*.txt" -type f -delete 2>/dev/null
    find "$BACKUP_DIR" -name "restore_backup.sh" -type f -delete 2>/dev/null
    # --- 清理结束 ---

    case $mode in
        4) # 自定义选择容器
            containers=$(select_containers_interactive)
            if [ $? -ne 0 ]; then
                return 1
            fi
            ;;
        *) # 其他模式备份所有容器
            containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
            ;;
    esac
    
    if [ -z "$containers" ]; then
        print_error "没有可备份的容器"
        return 1
    fi
    
    log "开始备份，模式：$mode"
    log "备份容器：$(echo "$containers" | tr '\n' ' ')"
    
    local success=0
    
    # 备份每个容器
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            print_info "备份容器：$container"
            
            local container_backup_dir="$BACKUP_DIR/${container}_backup_$TIMESTAMP"
            mkdir -p "$container_backup_dir"
            
            case $mode in
                1) # 完整备份
                    backup_container_config "$container" "$container_backup_dir"
                    backup_container_volumes "$container" "$container_backup_dir"
                    generate_startup_script "$container" "$container_backup_dir"
                    ;;
                2) # 仅配置
                    backup_container_config "$container" "$container_backup_dir"
                    generate_startup_script "$container" "$container_backup_dir"
                    ;;
                3) # 仅数据
                    backup_container_volumes "$container" "$container_backup_dir"
                    ;;
                4) # 自定义（完整备份）
                    backup_container_config "$container" "$container_backup_dir"
                    backup_container_volumes "$container" "$container_backup_dir"
                    generate_startup_script "$container" "$container_backup_dir"
                    ;;
            esac
            
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
备份模式: $mode
成功备份: $success 个容器

容器列表:
$(echo "$containers" | sed 's/^/- /')
EOF
    
    # 创建恢复脚本
    create_restore_script
    
    # 创建压缩包（固定文件名，不包含时间戳）
    log "创建备份压缩包..."
    local backup_archive="$BACKUP_DIR/docker_backup_${HOSTNAME}_latest.tar.gz"
    
    cd "$BACKUP_DIR"
    # --- 修复：从此处的 tar 命令中移除 2>/dev/null，以便在打包失败时显示错误 ---
    tar -czf "$backup_archive" *_backup_$TIMESTAMP/ system_info_$TIMESTAMP.txt restore_backup.sh
    
    # 清理本次备份产生的临时文件
    log "清理本次备份的临时文件..."
    rm -rf *_backup_$TIMESTAMP/
    rm -f system_info_$TIMESTAMP.txt
    
    if [ -f "$backup_archive" ]; then
        local backup_size=$(du -h "$backup_archive" | cut -f1)
        print_success "备份完成！"
        print_info "备份文件：$backup_archive ($backup_size)"
        print_info "恢复脚本：$BACKUP_DIR/restore_backup.sh"
        echo ""
        print_info "跨服务器恢复命令："
        echo "  # 将 $backup_archive 和 restore_backup.sh 复制到目标服务器"
        echo "  ./restore_backup.sh $backup_archive"
        
        log "备份成功完成"
    else
        print_error "创建备份压缩包失败！请检查日志：$LOG_FILE"
        log "备份失败：无法创建压缩包 $backup_archive"
    fi
}

# 交互式选择容器
select_containers_interactive() {
    local all_containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    
    if [ -z "$all_containers" ]; then
        print_error "没有运行中的容器"
        return 1
    fi
    
    echo ""
    echo "可用容器："
    local i=1
    local container_array=()
    
    while IFS= read -r container; do
        echo "$i) $container"
        container_array+=("$container")
        ((i++))
    done <<< "$all_containers"
    
    echo "a) 全部容器"
    echo ""
    
    read -p "选择容器 (数字/多个用空格分隔/a=全部): " selection
    
    if [ "$selection" = "a" ]; then
        echo "$all_containers"
        return 0
    fi
    
    local selected=""
    local valid=true
    
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#container_array[@]}" ]; then
            if [ -n "$selected" ]; then
                selected="$selected\n${container_array[$((num-1))]}"
            else
                selected="${container_array[$((num-1))]}"
            fi
        else
            print_error "无效选项: $num"
            valid=false
            break
        fi
    done
    
    if [ "$valid" = true ] && [ -n "$selected" ]; then
        echo -e "$selected"
        return 0
    else
        return 1
    fi
}

# 创建恢复脚本
create_restore_script() {
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
cd "$RESTORE_DIR" || exit

echo "解压备份文件..."
tar -xzf "$BACKUP_FILE"

echo "恢复数据卷..."
for container_dir in *_backup_*/; do
    if [ -d "$container_dir" ]; then
        container_name=$(echo "$container_dir" | sed 's/_backup_.*\///')
        echo "处理容器: $container_name"
        
        cd "$container_dir" || continue
        
        for volume_file in volume_*.tar.gz; do
            if [ -f "$volume_file" ]; then
                volume_name=$(echo "$volume_file" | sed 's/^volume_//' | sed 's/\.tar\.gz$//')
                echo "恢复数据卷: $volume_name"
                docker volume create "$volume_name" >/dev/null 2>&1
                docker run --rm -v "$volume_name:/data" -v "$PWD:/backup" alpine:latest tar xzf "/backup/$volume_file" -C /data
            fi
        done
        
        for mount_file in mount_*.tar.gz; do
            if [ -f "$mount_file" ]; then
                # mount_name=$(echo "$mount_file" | sed 's/^mount_//' | sed 's/\.tar\.gz$//')
                # target_path="/opt/restored_data/$container_name/$mount_name"
                # echo "恢复挂载目录到: $target_path (请注意：绑定的主机目录需要手动确认路径并放置)"
                # mkdir -p "$target_path"
                # tar -xzf "$mount_file" -C "$target_path"
                echo "警告：检测到绑定挂载的备份文件 '$mount_file'。"
                echo "       为了服务器安全，脚本不会自动恢复主机路径。"
                echo "       请手动解压此文件，并将其内容放置到新容器所需的正确主机路径上。"
                echo "       恢复后的启动脚本 start_container.sh 中会指明原始的主机路径。"
            fi
        done
        
        cd ..
    fi
done

echo "数据恢复完成！"
echo "临时恢复目录: $RESTORE_DIR"
echo ""
echo "请检查以上输出，确认数据卷和绑定目录已按预期恢复。"
echo "接下来，您可以手动执行以下命令来启动容器："
echo "（请在执行前，仔细检查并编辑 start_container.sh 脚本中的主机路径 -v /host/path:/container/path）"
echo ""
for container_dir in *_backup_*/; do
    if [ -d "$container_dir" ] && [ -f "$container_dir/start_container.sh" ]; then
        container_name=$(echo "$container_dir" | sed 's/_backup_.*\///')
        echo "cd $RESTORE_DIR/$container_dir && ./start_container.sh  # 启动 $container_name"
    fi
done
RESTORE_SCRIPT
    
    chmod +x "$BACKUP_DIR/restore_backup.sh"
}

# 完整功能菜单
main_menu() {
    clear
    show_title
    show_docker_status
    
    echo "═══════════════════════════════════════"
    echo "Docker备份管理系统："
    echo "1) 🔄 执行备份"
    echo "2) 📥 恢复备份"
    echo "3) ⏰ 配置定时备份"
    echo "4) 📋 查看备份历史"
    echo "5) 📁 配置备份目录"
    echo "6) 🔧 备份模式选择"
    echo "7) ❓ 显示帮助"
    echo "8) 🚪 退出"
    echo ""
    
    read -p "请选择功能 (1-8): " choice
    
    case "$choice" in
        1)
            backup_menu
            ;;
        2)
            restore_menu
            ;;
        3)
            cron_menu
            ;;
        4)
            show_backup_history
            read -p "按回车返回主菜单..." -r
            main_menu
            ;;
        5)
            configure_backup_dir
            ;;
        6)
            mode_menu
            ;;
        7)
            show_help
            read -p "按回车返回主菜单..." -r
            main_menu
            ;;
        8)
            print_info "感谢使用Docker备份系统！"
            exit 0
            ;;
        *)
            print_error "请输入1-8"
            sleep 1
            main_menu
            ;;
    esac
}

# 备份菜单
backup_menu() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔄 备份操作"
    echo "1) 完整备份（配置+数据）"
    echo "2) 仅配置备份（快速）"
    echo "3) 仅数据备份（数据卷+挂载）"
    echo "4) 自定义选择容器（完整备份）"
    echo "5) 返回主菜单"
    echo ""
    
    read -p "请选择备份模式 (1-5): " mode
    
    case "$mode" in
        1)
            print_info "开始完整备份..."
            perform_backup_mode 1
            ;;
        2)
            print_info "开始配置备份..."
            perform_backup_mode 2
            ;;
        3)
            print_info "开始数据备份..."
            perform_backup_mode 3
            ;;
        4)
            print_info "自定义选择容器..."
            perform_backup_mode 4
            ;;
        5)
            main_menu
            return
            ;;
        *)
            print_error "请输入1-5"
            sleep 1
            backup_menu
            return
            ;;
    esac
    
    echo ""
    read -p "按回车返回主菜单..." -r
    main_menu
}

# 恢复菜单
restore_menu() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📥 恢复备份"
    
    local backups=$(find "$BACKUP_DIR" -name "docker_backup_*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [ -z "$backups" ]; then
        print_error "没有找到备份文件"
        read -p "按回车返回主菜单..." -r
        main_menu
        return
    fi
    
    echo "可用的备份文件："
    local i=1
    local backup_array=()
    
    while IFS= read -r backup; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "$i) $(basename "$backup") ($size) - $date"
        backup_array+=("$backup")
        ((i++))
    done <<< "$backups"
    
    echo "$i) 手动输入备份文件路径"
    echo "$((i+1))) 返回主菜单"
    echo ""
    
    read -p "请选择备份文件 (1-$((i+1))): " choice
    
    local selected_backup=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt $i ]; then
        selected_backup="${backup_array[$((choice-1))]}"
    elif [ "$choice" -eq $i ]; then
        read -p "请输入备份文件完整路径: " selected_backup
    elif [ "$choice" -eq $((i+1)) ]; then
        main_menu
        return
    else
        print_error "无效选择"
        sleep 1
        restore_menu
        return
    fi
    
    if [ ! -f "$selected_backup" ]; then
        print_error "备份文件不存在：$selected_backup"
        sleep 2
        restore_menu
        return
    fi
    
    print_info "使用恢复脚本恢复备份..."
    if [ -x "$BACKUP_DIR/restore_backup.sh" ]; then
        "$BACKUP_DIR/restore_backup.sh" "$selected_backup"
    else
        print_error "恢复脚本不存在，请先创建一次备份"
    fi
    
    read -p "按回车返回主菜单..." -r
    main_menu
}

# 定时任务菜单
cron_menu() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⏰ 配置定时备份"
    echo "1) 每天凌晨2点"
    echo "2) 每周日凌晨2点"
    echo "3) 每月1号凌晨2点"
    echo "4) 自定义时间"
    echo "5) 查看当前定时任务"
    echo "6) 删除定时任务"
    echo "7) 返回主菜单"
    echo ""
    
    read -p "请选择 (1-7): " choice
    
    local cron_schedule=""
    local desc=""

    case $choice in
        1)
            cron_schedule="0 2 * * *"
            desc="每天凌晨2点"
            ;;
        2)
            cron_schedule="0 2 * * 0"
            desc="每周日凌晨2点"
            ;;
        3)
            cron_schedule="0 2 1 * *"
            desc="每月1号凌晨2点"
            ;;
        4)
            echo "Cron表达式格式: 分 时 日 月 周"
            echo "例如: 0 2 * * * (每天凌晨2点)"
            echo "      30 1 * * 1 (每周一凌晨1点30分)"
            read -p "请输入cron表达式: " cron_schedule
            desc="自定义时间"
            ;;
        5)
            echo ""
            print_info "当前定时任务："
            crontab -l 2>/dev/null | grep "docker-backup-auto" || echo "没有Docker备份相关的定时任务"
            read -p "按回车返回..." -r
            cron_menu
            return
            ;;
        6)
            crontab -l 2>/dev/null | grep -v "docker-backup-auto" | crontab -
            print_success "定时任务已删除"
            read -p "按回车返回..." -r
            cron_menu
            return
            ;;
        7)
            main_menu
            return
            ;;
        *)
            print_error "请输入1-7"
            sleep 1
            cron_menu
            return
            ;;
    esac

    if [ -z "$cron_schedule" ]; then
        cron_menu
        return
    fi
    
    # 配置定时任务
    local script_path
    script_path=$(realpath "$0")
    local cron_entry="$cron_schedule $script_path --auto #docker-backup-auto"
    
    (crontab -l 2>/dev/null | grep -v "docker-backup-auto"; echo "$cron_entry") | crontab -
    
    print_success "定时任务已配置：$desc"
    echo "当前定时任务："
    crontab -l | grep "docker-backup-auto"
    
    read -p "按回车返回主菜单..." -r
    main_menu
}

# 备份模式菜单
mode_menu() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 备份模式说明"
    echo ""
    echo "1) 完整备份："
    echo "     • 容器配置 + 环境变量"
    echo "     • 数据卷 + 绑定挂载"
    echo "     • 镜像信息 + 启动脚本"
    echo "     适用：生产环境、服务器迁移"
    echo ""
    echo "2) 仅配置备份："
    echo "     • 容器配置 + 环境变量"
    echo "     • 端口映射 + 网络配置"
    echo "     • 启动脚本（无数据）"
    echo "     适用：快速配置备份"
    echo ""
    echo "3) 仅数据备份："
    echo "     • 数据卷完整备份"
    echo "     • 绑定挂载目录"
    echo "     适用：数据安全备份"
    echo ""
    echo "4) 自定义选择："
    echo "     • 手动选择要备份的容器"
    echo "     • 完整备份选中容器"
    echo "     适用：特定容器备份"
    echo ""
    
    read -p "按回车返回主菜单..." -r
    main_menu
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
    local script_name
    script_name=$(basename "$0")
    echo ""
    echo "Docker备份恢复系统 v3.3.0 - 使用说明"
    echo ""
    echo "功能："
    echo "  🔄 完整备份（配置+数据卷+镜像信息）"
    echo "  🌐 跨服务器兼容"
    echo "  📦 自动压缩打包"
    echo "  🔧 自动生成恢复脚本"
    echo ""
    echo "使用方法："
    echo "  $script_name            # 完整功能菜单"
    echo "  $script_name --auto     # 自动执行一次完整备份（用于定时任务）"
    echo "  $script_name --install  # 安装到本地/opt/docker-backup目录"
    echo "  $script_name --help     # 显示此帮助"
    echo ""
    echo "完整功能包括："
    echo "  • 🔄 执行备份 - 4种备份模式可选"
    echo "  • 📥 恢复备份 - 智能恢复系统"
    echo "  • ⏰ 配置定时备份 - 多种时间策略"
    echo "  • 📋 查看备份历史 - 备份文件管理"
    echo "  • 🔧 备份模式选择 - 详细说明"
    echo ""
    echo "恢复方法："
    echo "  1. 将备份文件(tar.gz)和 restore_backup.sh 复制到目标服务器"
    echo "  2. 给予执行权限: chmod +x restore_backup.sh"
    echo "  3. 运行: ./restore_backup.sh docker_backup_..._latest.tar.gz"
    echo "  4. 按提示检查并手动执行启动容器的命令"
    echo ""
}

# 检测管道执行
is_piped() {
    # 如果标准输入、输出、错误都不是终端，则判断为远程管道执行
    if [ ! -t 0 ] && [ ! -t 1 ] && [ ! -t 2 ]; then
        return 0
    fi
    return 1
}

# 简化的本地安装
install_to_local_simple() {
    local install_dir="/opt/docker-backup"
    local script_name="docker-backup.sh"
    # 注意：这里假设脚本源在GitHub上，请根据实际情况修改
    local script_url="https://raw.githubusercontent.com/moli-xia/docker-backup-tool/main/docker_backup_all_in_one.sh"
    
    print_info "安装Docker备份工具到本地..."
    
    if ! mkdir -p "$install_dir"; then
        print_error "无法创建安装目录 $install_dir。请检查权限。"
        return 1
    fi
    
    local script_path="$install_dir/$script_name"
    
    print_info "正在从URL下载脚本..."
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$script_url" -o "$script_path"; then
            print_error "使用curl下载失败。请检查网络或URL: $script_url"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q "$script_url" -O "$script_path"; then
            print_error "使用wget下载失败。请检查网络或URL: $script_url"
            return 1
        fi
    else
        print_error "需要curl或wget命令来下载脚本"
        return 1
    fi
    
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        print_success "脚本已安装到：$script_path"
        
        # 尝试创建默认备份目录
        mkdir -p "$DEFAULT_BACKUP_DIR" 2>/dev/null || true
        
        echo ""
        print_info "使用方法："
        echo "  $script_path          # 启动交互界面"
        echo "  $script_path --auto   # 执行一次自动备份"
        echo "  $script_path --help   # 查看帮助"
        echo ""
        print_info "建议将 $install_dir 添加到您的PATH，或创建一个软链接："
        echo "  ln -s $script_path /usr/local/bin/docker-backup"
    else
        print_error "脚本下载后未找到，安装失败"
        return 1
    fi
}

# 主函数
main() {
    # 加载用户配置
    load_config
    
    case "${1:-}" in
        --auto)
            if ! check_environment; then
                exit 1
            fi
            print_info "自动备份模式（完整备份）"
            perform_backup_mode 1
            ;;
        --install)
            install_to_local_simple
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
                print_info "检测到远程管道执行..."
                echo ""
                echo "🔽 推荐用法："
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "1️⃣  自动备份：curl ... | bash -s -- --auto"
                echo "2️⃣  安装到本地：curl ... | bash -s -- --install"
                echo ""
                print_warning "当前模式将自动执行完整备份，如不需要请按Ctrl+C"
                
                for i in 5 4 3 2 1; do
                    echo -ne "⏱️  自动备份倒计时: $i 秒 (按 Ctrl+C 取消)\r"
                    sleep 1
                done
                echo -e "\n"
                perform_backup_mode 1
            else
                # 显示完整交互菜单
                main_menu
            fi
            ;;
    esac
}

# 运行主程序
main "$@"