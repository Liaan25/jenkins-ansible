#!/bin/bash

# ==============================================================================
# Скрипт проверки логов сервисов мониторинга
# ==============================================================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MONITORING_USER="CI10742292-lnx-mon_sys"

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ==============================================================================
# 1. ПРОВЕРКА ЛОГОВ SYSTEMD
# ==============================================================================

print_header "1. ПРОВЕРКА ЛОГОВ SYSTEMD"

for service in grafana prometheus harvest; do
    echo -e "\n${YELLOW}Логи $service:${NC}"
    sudo -u "$MONITORING_USER" bash -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) journalctl --user -u $service -n 20 --no-pager"
    echo ""
done

# ==============================================================================
# 2. ПРОВЕРКА ФАЙЛОВ КОНФИГУРАЦИИ
# ==============================================================================

print_header "2. ПРОВЕРКА ФАЙЛОВ КОНФИГУРАЦИИ"

CONFIG_FILES=(
    "/opt/monitoring/config/grafana.ini"
    "/opt/monitoring/config/prometheus.yml"
    "/opt/monitoring/config/harvest.yml"
    "/opt/monitoring/config/web-config.yml"
)

for config in "${CONFIG_FILES[@]}"; do
    echo -n "$config: "
    if [ -f "$config" ]; then
        print_success "существует"
        echo "  Размер: $(stat -c %s "$config") байт"
        echo "  Права: $(ls -la "$config" | awk '{print $1, $3, $4}')"
        
        # Проверка синтаксиса для YAML файлов
        if [[ "$config" == *.yml ]] || [[ "$config" == *.yaml ]]; then
            if python3 -c "import yaml; yaml.safe_load(open('$config'))" &>/dev/null; then
                print_success "  YAML синтаксис корректен"
            else
                print_error "  Ошибка YAML синтаксиса"
            fi
        fi
    else
        print_error "НЕ существует"
    fi
done

# ==============================================================================
# 3. ПРОВЕРКА ДИРЕКТОРИЙ ДАННЫХ
# ==============================================================================

print_header "3. ПРОВЕРКА ДИРЕКТОРИЙ ДАННЫХ"

DATA_DIRS=(
    "/opt/monitoring/data/grafana"
    "/opt/monitoring/data/prometheus"
    "/opt/monitoring/logs/grafana"
    "/opt/monitoring/logs/prometheus"
    "/opt/monitoring/logs/harvest"
)

for dir in "${DATA_DIRS[@]}"; do
    echo -n "$dir: "
    if [ -d "$dir" ]; then
        print_success "существует"
        echo "  Права: $(ls -ld "$dir" | awk '{print $1, $3, $4}')"
    else
        print_error "НЕ существует"
    fi
done

# ==============================================================================
# 4. ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ==============================================================================

print_header "4. ПРОВЕРКА ЗАВИСИМОСТЕЙ"

# Проверка что бинари могут запускаться
echo "Проверка запуска бинарей..."

# Grafana
echo -n "Grafana: "
if sudo -u "$MONITORING_USER" /opt/monitoring/bin/grafana-server --version &>/dev/null; then
    print_success "запускается"
else
    print_error "не запускается"
    echo "  Попытка запуска с выводом ошибки:"
    sudo -u "$MONITORING_USER" /opt/monitoring/bin/grafana-server --version 2>&1 | head -5
fi

# Prometheus
echo -n "Prometheus: "
if sudo -u "$MONITORING_USER" /opt/monitoring/bin/prometheus --version &>/dev/null; then
    print_success "запускается"
else
    print_error "не запускается"
    echo "  Попытка запуска с выводом ошибки:"
    sudo -u "$MONITORING_USER" /opt/monitoring/bin/prometheus --version 2>&1 | head -5
fi

# Harvest
echo -n "Harvest: "
if sudo -u "$MONITORING_USER" /opt/monitoring/bin/harvest version &>/dev/null; then
    print_success "запускается"
else
    print_error "не запускается"
    echo "  Попытка запуска с выводом ошибки:"
    sudo -u "$MONITORING_USER" /opt/monitoring/bin/harvest version 2>&1 | head -5
fi

# ==============================================================================
# 5. ПРОВЕРКА СЕТЕВЫХ ПОРТОВ
# ==============================================================================

print_header "5. ПРОВЕРКА СЕТЕВЫХ ПОРТОВ"

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
# 6. РЕКОМЕНДАЦИИ
# ==============================================================================

print_header "6. РЕКОМЕНДАЦИИ"

echo "Если сервисы падают с ошибками:"
echo "1. Проверьте логи выше для конкретных ошибок"
echo "2. Убедитесь что конфигурационные файлы корректны"
echo "3. Проверьте что все зависимости установлены"
echo "4. Убедитесь что директории данных существуют и доступны"
echo ""
echo "Для детальной диагностики:"
echo "  sudo -u $MONITORING_USER journalctl --user -u <service> -f"
echo "  sudo -u $MONITORING_USER /opt/monitoring/bin/<binary> --version"

