#!/bin/bash

# ==============================================================================
# Полный скрипт диагностики сервисов мониторинга
# ==============================================================================
# 
# Назначение: Диагностика проблем с запуском Prometheus, Grafana, Harvest
# Использование: ./diagnose_service_startup.sh
#
# ==============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Переменные
MONITORING_USER="CI10742292-lnx-mon_sys"
MONITORING_GROUP="CI10742292-lnx-mon_sys"
MONITORING_BASE_DIR="/opt/monitoring"
SERVICES=("prometheus" "grafana" "harvest")

# Функции
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "Команда '$1' доступна"
    else
        print_error "Команда '$1' НЕ доступна"
    fi
}

# ==============================================================================
# 1. ПРОВЕРКА СИСТЕМНЫХ ПРЕДПОСЫЛОК
# ==============================================================================

print_header "1. ПРОВЕРКА СИСТЕМНЫХ ПРЕДПОСЫЛОК"

echo "Проверка пользователя $MONITORING_USER..."
if id "$MONITORING_USER" &>/dev/null; then
    print_success "Пользователь $MONITORING_USER существует"
    echo "Информация о пользователе:"
    id "$MONITORING_USER"
else
    print_error "Пользователь $MONITORING_USER НЕ существует"
fi

echo -e "\nПроверка lingering для пользователя..."
if sudo loginctl show-user "$MONITORING_USER" | grep -q "Linger=yes"; then
    print_success "Linger включен для $MONITORING_USER"
else
    print_warning "Linger НЕ включен для $MONITORING_USER"
fi

echo -e "\nПроверка XDG_RUNTIME_DIR..."
USER_UID=$(id -u "$MONITORING_USER")
XDG_RUNTIME_DIR="/run/user/$USER_UID"
if [ -d "$XDG_RUNTIME_DIR" ]; then
    print_success "XDG_RUNTIME_DIR существует: $XDG_RUNTIME_DIR"
else
    print_error "XDG_RUNTIME_DIR НЕ существует: $XDG_RUNTIME_DIR"
fi

# ==============================================================================
# 2. ПРОВЕРКА ФАЙЛОВОЙ СИСТЕМЫ
# ==============================================================================

print_header "2. ПРОВЕРКА ФАЙЛОВОЙ СИСТЕМЫ"

echo "Проверка базовой директории..."
if [ -d "$MONITORING_BASE_DIR" ]; then
    print_success "Базовая директория существует: $MONITORING_BASE_DIR"
else
    print_error "Базовая директория НЕ существует: $MONITORING_BASE_DIR"
fi

# Проверка структуры директорий
DIRECTORIES=(
    "$MONITORING_BASE_DIR/bin"
    "$MONITORING_BASE_DIR/config"
    "$MONITORING_BASE_DIR/data"
    "$MONITORING_BASE_DIR/logs"
    "/home/$MONITORING_USER/.config/systemd/user"
)

for dir in "${DIRECTORIES[@]}"; do
    if [ -d "$dir" ]; then
        print_success "Директория существует: $dir"
        echo "  Права: $(ls -ld "$dir" | awk '{print $1, $3, $4}')"
    else
        print_error "Директория НЕ существует: $dir"
    fi
done

# ==============================================================================
# 3. ПРОВЕРКА ИСПОЛНЯЕМЫХ ФАЙЛОВ
# ==============================================================================

print_header "3. ПРОВЕРКА ИСПОЛНЯЕМЫХ ФАЙЛОВ"

BINARIES=(
    "$MONITORING_BASE_DIR/bin/grafana-server"
    "$MONITORING_BASE_DIR/bin/prometheus"
    "$MONITORING_BASE_DIR/bin/harvest"
)

for binary in "${BINARIES[@]}"; do
    echo -e "\nПроверка: $binary"
    
    if [ -f "$binary" ]; then
        print_success "Файл существует"
        
        # Проверка прав
        PERMS=$(stat -c "%A" "$binary")
        OWNER=$(stat -c "%U:%G" "$binary")
        echo "  Права: $PERMS, Владелец: $OWNER"
        
        # Проверка исполняемости
        if [ -x "$binary" ]; then
            print_success "Файл исполняемый"
        else
            print_error "Файл НЕ исполняемый"
        fi
        
        # Проверка версии (если возможно)
        if [[ "$binary" == *"grafana-server"* ]]; then
            if sudo -u "$MONITORING_USER" "$binary" --version &>/dev/null; then
                print_success "Grafana может быть запущена"
            else
                print_error "Grafana НЕ может быть запущена"
            fi
        elif [[ "$binary" == *"prometheus"* ]]; then
            if sudo -u "$MONITORING_USER" "$binary" --version &>/dev/null; then
                print_success "Prometheus может быть запущен"
            else
                print_error "Prometheus НЕ может быть запущен"
            fi
        elif [[ "$binary" == *"harvest"* ]]; then
            if sudo -u "$MONITORING_USER" "$binary" version &>/dev/null; then
                print_success "Harvest может быть запущен"
            else
                print_error "Harvest НЕ может быть запущен"
            fi
        fi
        
    else
        print_error "Файл НЕ существует"
    fi
done

# ==============================================================================
# 4. ПРОВЕРКА SYSTEMD UNITS
# ==============================================================================

print_header "4. ПРОВЕРКА SYSTEMD UNITS"

SYSTEMD_USER_DIR="/home/$MONITORING_USER/.config/systemd/user"

for service in "${SERVICES[@]}"; do
    UNIT_FILE="$SYSTEMD_USER_DIR/$service.service"
    
    echo -e "\nПроверка: $service.service"
    
    if [ -f "$UNIT_FILE" ]; then
        print_success "Unit файл существует"
        echo "  Права: $(ls -l "$UNIT_FILE" | awk '{print $1, $3, $4}')"
        
        # Проверка содержимого
        echo "  Содержимое [Service] секции:"
        sudo cat "$UNIT_FILE" | grep -A10 "\[Service\]" | head -15
        
        # Проверка статуса сервиса
        echo -e "\n  Статус сервиса:"
        if sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) systemctl --user is-active $service" &>/dev/null; then
            print_success "Сервис активен"
        else
            STATUS=$(sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) systemctl --user show -p ActiveState,SubState,Result $service")
            print_warning "Сервис не активен"
            echo "  $STATUS"
        fi
        
    else
        print_error "Unit файл НЕ существует: $UNIT_FILE"
    fi
done

# ==============================================================================
# 5. ПРОВЕРКА ЛОГОВ
# ==============================================================================

print_header "5. ПРОВЕРКА ЛОГОВ"

for service in "${SERVICES[@]}"; do
    echo -e "\nЛоги сервиса: $service"
    
    # Проверка journald логов
    LOG_OUTPUT=$(sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) journalctl --user -u $service -n 10 --no-pager 2>/dev/null" || echo "Логи недоступны")
    
    if [[ "$LOG_OUTPUT" != "Логи недоступны" ]] && [ -n "$LOG_OUTPUT" ]; then
        echo "$LOG_OUTPUT"
    else
        print_warning "Логи недоступны или пустые"
    fi
done

# ==============================================================================
# 6. ПРОВЕРКА СЕТЕВЫХ ПОРТОВ
# ==============================================================================

print_header "6. ПРОВЕРКА СЕТЕВЫХ ПОРТОВ"

PORTS=("9090" "3000" "12990" "12991")

for port in "${PORTS[@]}"; do
    echo -n "Порт $port: "
    if ss -tln | grep ":$port " &>/dev/null; then
        print_success "открыт"
    else
        print_warning "закрыт"
    fi
done

# ==============================================================================
# 7. ПРОВЕРКА СЕКРЕТОВ И КОНФИГУРАЦИИ
# ==============================================================================

print_header "7. ПРОВЕРКА СЕКРЕТОВ И КОНФИГУРАЦИИ"

# Проверка директории секретов
SECRETS_DIR="/dev/shm/monitoring_secrets"
if [ -d "$SECRETS_DIR" ]; then
    print_success "Директория секретов существует: $SECRETS_DIR"
    echo "  Содержимое:"
    sudo ls -la "$SECRETS_DIR" 2>/dev/null || echo "  Доступ запрещен"
else
    print_warning "Директория секретов НЕ существует: $SECRETS_DIR"
fi

# Проверка конфигурационных файлов
CONFIG_FILES=(
    "$MONITORING_BASE_DIR/config/grafana.ini"
    "$MONITORING_BASE_DIR/config/prometheus.yml"
    "$MONITORING_BASE_DIR/config/harvest.yml"
)

for config in "${CONFIG_FILES[@]}"; do
    if [ -f "$config" ]; then
        print_success "Конфиг существует: $(basename "$config")"
    else
        print_warning "Конфиг НЕ существует: $(basename "$config")"
    fi
done

# ==============================================================================
# 8. ПРОВЕРКА VAULT AGENT
# ==============================================================================

print_header "8. ПРОВЕРКА VAULT AGENT"

# Проверка статуса Vault Agent
if sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) systemctl --user is-active vault-agent-monitoring" &>/dev/null; then
    print_success "Vault Agent активен"
else
    print_warning "Vault Agent не активен"
fi

# Проверка файлов Vault Agent
VAULT_FILES=(
    "/opt/vault/conf/role_id.txt"
    "/opt/vault/conf/secret_id.txt"
    "/opt/vault/conf/agent.hcl"
)

for vault_file in "${VAULT_FILES[@]}"; do
    if [ -f "$vault_file" ]; then
        print_success "Vault файл существует: $(basename "$vault_file")"
    else
        print_warning "Vault файл НЕ существует: $(basename "$vault_file")"
    fi
done

# ==============================================================================
# 9. ИТОГОВАЯ ДИАГНОСТИКА
# ==============================================================================

print_header "9. ИТОГОВАЯ ДИАГНОСТИКА"

echo "Проверка возможности запуска сервисов..."

for service in "${SERVICES[@]}"; do
    echo -n "$service: "
    
    # Попытка запуска сервиса
    if sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) systemctl --user start $service" &>/dev/null; then
        sleep 2
        
        if sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) systemctl --user is-active $service" &>/dev/null; then
            print_success "запущен успешно"
        else
            print_error "не удалось запустить"
            # Получить подробную информацию об ошибке
            ERROR_INFO=$(sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/$(id -u $MONITORING_USER) systemctl --user status $service")
            echo "  Ошибка: $ERROR_INFO"
        fi
    else
        print_error "не удалось инициировать запуск"
    fi
done

# ==============================================================================
# 10. РЕКОМЕНДАЦИИ
# ==============================================================================

print_header "10. РЕКОМЕНДАЦИИ"

echo "Если сервисы не запускаются, проверьте:"
echo "1. Права на исполняемые файлы в /opt/monitoring/bin/"
echo "2. Наличие всех зависимостей для бинарей"
echo "3. Корректность конфигурационных файлов"
echo "4. Работу Vault Agent для получения секретов"
echo "5. Логи через: sudo -u $MONITORING_USER journalctl --user -u <service> -f"

print_header "ДИАГНОСТИКА ЗАВЕРШЕНА"

