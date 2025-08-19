#!/bin/bash

# Docker应用一体化备份恢复脚本
# 版本：3.0 - 单文件版本
# 功能：备份、恢复、定时任务、跨服务器兼容

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BACKUP_DIR="/opt/docker_backups"
BACKUP_DIR=""
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)
LOG_FILE=""

# 显示Logo和版本信息
show_header() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║        Docker备份恢复系统 v3.0      ║${NC}"
    echo -e "${PURPLE}║           一体化单文件版本           ║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════╝${NC}"
    echo ""
}

# 打印函数
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 日志函数
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
    echo -e "${CYAN}$message${NC}"
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
    echo ""
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

# 选择备份目录
select_backup_dir() {
    echo "备份目录选择："
    echo "1) 默认目录: $DEFAULT_BACKUP_DIR"
    echo "2) 自定义目录"
    
    while true; do
        read -p "请选择 (1-2): " choice
        case $choice in
            1) BACKUP_DIR="$DEFAULT_BACKUP_DIR"; break ;;
            2) 
                read -p "请输入目录路径: " custom_dir
                if [ -n "$custom_dir" ]; then
                    BACKUP_DIR="$custom_dir"
                    break
                fi
                ;;
            *) print_error "请输入1或2" ;;
        esac
    done
    
    mkdir -p "$BACKUP_DIR"
    LOG_FILE="$BACKUP_DIR/backup_$TIMESTAMP.log"
    print_success "备份目录：$BACKUP_DIR"
}

# 选择备份模式
select_backup_mode() {
    echo ""
    echo "备份模式选择："
    echo "1) 完整备份（配置+数据卷+镜像信息）"
    echo "2) 仅配置备份（容器配置+环境变量）"
    echo "3) 仅数据备份（数据卷+挂载目录）"
    echo "4) 自定义选择容器"
    
    while true; do
        read -p "请选择模式 (1-4): " mode
        case $mode in
            1|2|3|4) return $mode ;;
            *) print_error "请输入1-4" ;;
        esac
    done
}

# 选择容器
select_containers() {
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
    
    while true; do
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
        fi
    done
}

# 备份容器配置
backup_container_config() {
    local container="$1"
    local backup_path="$2"
    
    log "备份容器 $container 的配置..."
    
    # 容器详细配置
    docker inspect "$container" > "$backup_path/container_config.json" 2>/dev/null
    
    # 镜像信息
    docker inspect "$container" --format '{{.Config.Image}}' > "$backup_path/image_info.txt" 2>/dev/null
    
    # 环境变量
    docker inspect "$container" --format '{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' > "$backup_path/env_vars.txt" 2>/dev/null
    
    # 端口映射
    docker inspect "$container" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} -> {{(index $conf 0).HostPort}}{{"\n"}}{{end}}{{end}}' > "$backup_path/port_mappings.txt" 2>/dev/null
    
    # 重启策略
    docker inspect "$container" --format '{{.HostConfig.RestartPolicy.Name}}{{if .HostConfig.RestartPolicy.MaximumRetryCount}}:{{.HostConfig.RestartPolicy.MaximumRetryCount}}{{end}}' > "$backup_path/restart_policy.txt" 2>/dev/null
    
    # 挂载信息
    docker inspect "$container" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}:{{.Type}}:{{.Mode}}{{"\n"}}{{end}}' > "$backup_path/mounts_info.txt" 2>/dev/null
}

# 备份数据卷
backup_container_volumes() {
    local container="$1"
    local backup_path="$2"
    
    log "备份容器 $container 的数据..."
    
    # 获取挂载信息
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
# 容器 $container 启动脚本 - 生成于 $(date)

CONTAINER_NAME="$container"
IMAGE="$image"

echo "=== 启动容器: \$CONTAINER_NAME ==="

# 停止现有容器
docker stop "\$CONTAINER_NAME" 2>/dev/null || true
docker rm "\$CONTAINER_NAME" 2>/dev/null || true

# 拉取镜像
docker pull "\$IMAGE"

# 构建启动命令
DOCKER_CMD="docker run -d --name \$CONTAINER_NAME"

# 重启策略
if [ -n "$restart_policy" ] && [ "$restart_policy" != "no" ]; then
    DOCKER_CMD="\$DOCKER_CMD --restart=$restart_policy"
fi

# 端口映射
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

# 环境变量
if [ -f "env_vars.txt" ]; then
    while read -r env_line; do
        if [ -n "\$env_line" ] && [[ "\$env_line" != PATH=* ]]; then
            DOCKER_CMD="\$DOCKER_CMD -e '\$env_line'"
        fi
    done < "env_vars.txt"
fi

# 数据卷挂载（需要根据实际情况调整路径）
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

# 添加镜像
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

# 执行备份
perform_backup() {
    local mode=$1
    local containers=""
    
    case $mode in
        4) containers=$(select_containers) ;;
        *) containers=$(docker ps --format "{{.Names}}" 2>/dev/null) ;;
    esac
    
    if [ -z "$containers" ]; then
        print_error "没有可备份的容器"
        return 1
    fi
    
    log "开始备份，模式：$mode"
    
    local success=0
    local failed=0
    
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
                4) # 自定义（完整）
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
        
        # 恢复数据卷
        for volume_file in volume_*.tar.gz; do
            if [ -f "$volume_file" ]; then
                volume_name=$(echo "$volume_file" | sed 's/^volume_//' | sed 's/\.tar\.gz$//')
                echo "恢复数据卷: $volume_name"
                docker volume create "$volume_name" 2>/dev/null
                docker run --rm -v "$volume_name:/data" -v "$PWD:/backup" alpine:latest tar xzf "/backup/$volume_file" -C /data
            fi
        done
        
        # 恢复绑定挂载
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
    print_success "备份完成！文件：$(basename "$backup_archive") ($backup_size)"
    echo "恢复脚本：$BACKUP_DIR/restore_backup.sh"
    echo ""
    echo "跨服务器恢复命令："
    echo "$BACKUP_DIR/restore_backup.sh $backup_archive"
}

# 恢复备份
restore_backup() {
    echo ""
    echo "备份恢复功能"
    echo "1) 恢复本机备份"
    echo "2) 恢复外部备份文件"
    echo "3) 返回主菜单"
    
    while true; do
        read -p "请选择 (1-3): " choice
        case $choice in
            1)
                if [ ! -d "$DEFAULT_BACKUP_DIR" ]; then
                    print_error "备份目录不存在：$DEFAULT_BACKUP_DIR"
                    break
                fi
                
                local backups=$(find "$DEFAULT_BACKUP_DIR" -name "docker_backup_*.tar.gz" -type f 2>/dev/null | sort -r)
                if [ -z "$backups" ]; then
                    print_error "没有找到备份文件"
                    break
                fi
                
                echo ""
                echo "可用备份："
                local i=1
                while IFS= read -r backup; do
                    local size=$(du -h "$backup" | cut -f1)
                    local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
                    echo "$i) $(basename "$backup") ($size) - $date"
                    ((i++))
                done <<< "$backups"
                
                read -p "选择备份编号: " backup_num
                local selected_backup=$(echo "$backups" | sed -n "${backup_num}p")
                
                if [ -f "$selected_backup" ]; then
                    "$DEFAULT_BACKUP_DIR/restore_backup.sh" "$selected_backup"
                else
                    print_error "无效选择"
                fi
                break
                ;;
            2)
                read -p "请输入备份文件路径: " backup_file
                if [ -f "$backup_file" ]; then
                    if [ -x "$DEFAULT_BACKUP_DIR/restore_backup.sh" ]; then
                        "$DEFAULT_BACKUP_DIR/restore_backup.sh" "$backup_file"
                    else
                        print_error "恢复脚本不存在，请先创建备份"
                    fi
                else
                    print_error "备份文件不存在"
                fi
                break
                ;;
            3)
                break
                ;;
            *)
                print_error "请输入1-3"
                ;;
        esac
    done
}

# 配置定时任务
setup_cron() {
    echo ""
    echo "定时备份配置"
    echo "1) 每天凌晨2点"
    echo "2) 每周日凌晨2点"
    echo "3) 每月1号凌晨2点"
    echo "4) 自定义时间"
    echo "5) 删除定时任务"
    echo "6) 返回主菜单"
    
    while true; do
        read -p "请选择 (1-6): " choice
        case $choice in
            1) local cron_schedule="0 2 * * *"; local desc="每天凌晨2点"; break ;;
            2) local cron_schedule="0 2 * * 0"; local desc="每周日凌晨2点"; break ;;
            3) local cron_schedule="0 2 1 * *"; local desc="每月1号凌晨2点"; break ;;
            4) 
                read -p "输入cron表达式 (分 时 日 月 周): " cron_schedule
                local desc="自定义时间"
                break
                ;;
            5)
                crontab -l 2>/dev/null | grep -v "docker_backup_all_in_one.sh" | crontab -
                print_success "定时任务已删除"
                return
                ;;
            6) return ;;
            *) print_error "请输入1-6" ;;
        esac
    done
    
    # 添加定时任务
    local cron_entry="$cron_schedule cd $SCRIPT_DIR && ./$(basename "$0") --auto >/dev/null 2>&1"
    
    crontab -l 2>/dev/null | grep -v "docker_backup_all_in_one.sh" > /tmp/crontab_new
    echo "$cron_entry" >> /tmp/crontab_new
    crontab /tmp/crontab_new
    rm -f /tmp/crontab_new
    
    print_success "定时任务已配置：$desc"
    echo "当前定时任务："
    crontab -l | grep "docker_backup_all_in_one.sh"
}

# 查看备份历史
show_backup_history() {
    echo ""
    print_info "备份历史"
    
    if [ ! -d "$DEFAULT_BACKUP_DIR" ]; then
        print_warning "备份目录不存在"
        return
    fi
    
    local backups=$(find "$DEFAULT_BACKUP_DIR" -name "docker_backup_*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [ -z "$backups" ]; then
        print_warning "没有找到备份文件"
        return
    fi
    
    echo "备份文件列表："
    while IFS= read -r backup; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  📦 $(basename "$backup") ($size) - $date"
    done <<< "$backups"
    
    echo ""
    local logs=$(find "$DEFAULT_BACKUP_DIR" -name "backup_*.log" -type f 2>/dev/null | sort -r | head -3)
    if [ -n "$logs" ]; then
        echo "最近的备份日志："
        while IFS= read -r log; do
            echo "  📄 $(basename "$log")"
        done <<< "$logs"
    fi
}

# 自动备份模式
auto_backup() {
    print_info "自动备份模式"
    
    if ! check_environment; then
        exit 1
    fi
    
    BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    LOG_FILE="$BACKUP_DIR/backup_$TIMESTAMP.log"
    
    log "自动备份开始"
    
    if perform_backup 1; then
        log "自动备份成功完成"
    else
        log "自动备份失败"
        exit 1
    fi
}

# 显示帮助
show_help() {
    echo ""
    echo "Docker备份恢复系统 v3.0 - 使用说明"
    echo ""
    echo "功能："
    echo "  🔄 多模式备份（完整/配置/数据/自定义）"
    echo "  📅 定时备份配置"
    echo "  🔄 智能恢复功能"
    echo "  🌐 跨服务器兼容"
    echo ""
    echo "使用方法："
    echo "  $(basename "$0")                    # 交互式界面"
    echo "  $(basename "$0") --auto             # 自动备份"
    echo "  $(basename "$0") --help             # 显示帮助"
    echo ""
    echo "备份内容："
    echo "  • 容器配置和环境变量"
    echo "  • Docker数据卷"
    echo "  • 绑定挂载目录"
    echo "  • 自动生成的恢复脚本"
    echo ""
    echo "恢复方法："
    echo "  1. 复制备份文件到目标服务器"
    echo "  2. 运行: ./restore_backup.sh 备份文件.tar.gz"
    echo "  3. 按提示启动容器"
    echo ""
}

# 主菜单
main_menu() {
    while true; do
        show_header
        show_docker_status
        
        echo "主菜单："
        echo "1) 🔄 执行备份"
        echo "2) 📥 恢复备份"
        echo "3) ⏰ 定时备份"
        echo "4) 📋 备份历史"
        echo "5) ❓ 帮助信息"
        echo "6) 🚪 退出"
        echo ""
        
        read -p "请选择功能 (1-6): " choice
        
        case $choice in
            1)
                if ! check_environment; then
                    read -p "按回车继续..." -r
                    continue
                fi
                
                select_backup_dir
                local mode=$(select_backup_mode)
                echo ""
                perform_backup $mode
                read -p "按回车继续..." -r
                ;;
            2)
                restore_backup
                read -p "按回车继续..." -r
                ;;
            3)
                setup_cron
                read -p "按回车继续..." -r
                ;;
            4)
                show_backup_history
                read -p "按回车继续..." -r
                ;;
            5)
                show_help
                read -p "按回车继续..." -r
                ;;
            6)
                print_info "感谢使用Docker备份系统！"
                exit 0
                ;;
            *)
                print_error "请输入1-6"
                sleep 1
                ;;
        esac
    done
}

# 主程序入口
main() {
    # 处理命令行参数
    case "${1:-}" in
        --auto)
            auto_backup
            ;;
        --help)
            show_help
            ;;
        *)
            # 检查基础环境
            if ! check_environment; then
                print_error "环境检查失败，请确保Docker正常运行"
                exit 1
            fi
            
            # 启动交互式菜单
            main_menu
            ;;
    esac
}

# 运行主程序
main "$@"
