#!/bin/bash
################################################################################
# Скрипт-обертка для управления firewall правилами
################################################################################
#
# Назначение:
#   Безопасное управление iptables правилами для системы мониторинга
#   с валидацией всех входных параметров
#
# Использование:
#   ./manage_firewall.sh <ACTION> <SERVICE>
#
# Параметры:
#   ACTION  - Действие: add | remove | check
#   SERVICE - Сервис: prometheus | grafana | harvest_unix | harvest_netapp | harvest_range
#
# Примеры:
#   ./manage_firewall.sh add prometheus
#   ./manage_firewall.sh remove grafana
#   ./manage_firewall.sh check harvest_unix
#
################################################################################

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Функции вывода
print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ==========================================
# WHITELIST СЕРВИСОВ И ПОРТОВ
# ==========================================

# Допустимые сервисы и их порты (IMMUTABLE)
declare -A ALLOWED_SERVICES=(
    ["prometheus"]="9090"
    ["grafana"]="3000"
    ["harvest_unix"]="12990"
    ["harvest_netapp"]="13001"
    ["harvest_range"]="13000:14000"
)

# Допустимые действия
declare -A ALLOWED_ACTIONS=(
    ["add"]="1"
    ["remove"]="1"
    ["check"]="1"
)

# ==========================================
# ВАЛИДАЦИЯ ПАРАМЕТРОВ
# ==========================================

validate_action() {
    local action="$1"
    
    if [[ ! -v ALLOWED_ACTIONS["$action"] ]]; then
        print_error "Недопустимое действие: ${action}"
        echo "Допустимые действия: ${!ALLOWED_ACTIONS[*]}"
        return 1
    fi
    
    return 0
}

validate_service() {
    local service="$1"
    
    if [[ ! -v ALLOWED_SERVICES["$service"] ]]; then
        print_error "Недопустимый сервис: ${service}"
        echo "Допустимые сервисы: ${!ALLOWED_SERVICES[*]}"
        return 1
    fi
    
    return 0
}

# ==========================================
# ФУНКЦИИ УПРАВЛЕНИЯ IPTABLES
# ==========================================

check_rule() {
    local port="$1"
    
    if [[ "$port" =~ : ]]; then
        # Диапазон портов
        /usr/sbin/iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    else
        # Одиночный порт - проверяем для localhost и любого IP
        /usr/sbin/iptables -C INPUT -p tcp -s 127.0.0.1 --dport "$port" -j ACCEPT 2>/dev/null || \
        /usr/sbin/iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    fi
}

add_rule() {
    local port="$1"
    
    if check_rule "$port"; then
        print_info "Правило уже существует для порта ${port}"
        return 0
    fi
    
    if [[ "$port" =~ : ]]; then
        # Диапазон портов (для Harvest)
        /usr/sbin/iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        print_success "Добавлено правило для диапазона портов ${port}"
    else
        # Одиночный порт - разрешаем для любого IP
        /usr/sbin/iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        print_success "Добавлено правило для порта ${port}"
    fi
}

remove_rule() {
    local port="$1"
    
    if ! check_rule "$port"; then
        print_info "Правило не найдено для порта ${port}"
        return 0
    fi
    
    if [[ "$port" =~ : ]]; then
        # Диапазон портов
        /usr/sbin/iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    else
        # Одиночный порт - удаляем оба варианта (если есть)
        /usr/sbin/iptables -D INPUT -p tcp -s 127.0.0.1 --dport "$port" -j ACCEPT 2>/dev/null || true
        /usr/sbin/iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
    
    print_success "Удалено правило для порта ${port}"
}

# ==========================================
# ОСНОВНАЯ ЛОГИКА
# ==========================================

main() {
    # Проверка количества аргументов
    if [[ $# -ne 2 ]]; then
        print_error "Неверное количество аргументов"
        echo "Использование: $0 <ACTION> <SERVICE>"
        echo "  ACTION:  add | remove | check"
        echo "  SERVICE: prometheus | grafana | harvest_unix | harvest_netapp | harvest_range"
        exit 1
    fi
    
    local action="$1"
    local service="$2"
    
    print_info "Обработка запроса: действие=${action}, сервис=${service}"
    
    # Валидация входных параметров
    if ! validate_action "$action"; then
        exit 1
    fi
    
    if ! validate_service "$service"; then
        exit 1
    fi
    
    # Получение порта из whitelist
    local port="${ALLOWED_SERVICES[$service]}"
    print_info "Порт для сервиса ${service}: ${port}"
    
    # Выполнение действия
    case "$action" in
        add)
            add_rule "$port"
            ;;
        remove)
            remove_rule "$port"
            ;;
        check)
            if check_rule "$port"; then
                print_success "Правило существует для порта ${port}"
                exit 0
            else
                print_info "Правило не найдено для порта ${port}"
                exit 1
            fi
            ;;
    esac
    
    print_success "Операция ${action} для ${service} завершена"
}

# Запуск
main "$@"





