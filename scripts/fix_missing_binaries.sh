#!/bin/bash

# ==============================================================================
# Единый скрипт для поиска и создания символических ссылок на бинари мониторинга
# ==============================================================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MONITORING_BIN_DIR="/opt/monitoring/bin"

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

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# ==============================================================================
# 1. ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ
# ==============================================================================

print_header "1. ПРОВЕРКА ТЕКУЩЕГО СОСТОЯНИЯ"

echo "Проверка директории $MONITORING_BIN_DIR..."
if [ -d "$MONITORING_BIN_DIR" ]; then
    print_success "Директория существует"
    echo "Содержимое:"
    ls -la "$MONITORING_BIN_DIR/" || echo "  Директория пуста"
else
    print_error "Директория НЕ существует"
fi

# ==============================================================================
# 2. ПОИСК ИСПОЛНЯЕМЫХ ФАЙЛОВ
# ==============================================================================

print_header "2. ПОИСК ИСПОЛНЯЕМЫХ ФАЙЛОВ"

# Функция поиска бинаря с известными путями
find_binary() {
    local binary_name="$1"
    local found_path=""
    
    echo -e "\n${YELLOW}Поиск $binary_name...${NC}"
    
    # Известные пути из RPM пакетов
    case "$binary_name" in
        "grafana-server")
            KNOWN_PATHS=("/usr/sbin/grafana-server" "/usr/bin/grafana-server")
            ;;
        "prometheus")
            KNOWN_PATHS=("/usr/bin/prometheus" "/usr/local/bin/prometheus")
            ;;
        "harvest")
            KNOWN_PATHS=("/opt/harvest/bin/harvest" "/usr/bin/harvest" "/usr/local/bin/harvest")
            ;;
        *)
            KNOWN_PATHS=("/usr/bin/$binary_name" "/usr/sbin/$binary_name" "/usr/local/bin/$binary_name")
            ;;
    esac
    
    for path in "${KNOWN_PATHS[@]}"; do
        if [ -f "$path" ] && [ -x "$path" ]; then
            found_path="$path"
            print_success "Найден: $found_path"
            echo "  Права: $(ls -la "$found_path" | awk '{print $1, $3, $4}')"
            break
        fi
    done
    
    if [ -z "$found_path" ]; then
        print_error "$binary_name не найден в известных путях"
        # Расширенный поиск
        found_path=$(find /usr /opt -name "$binary_name" -type f -executable 2>/dev/null | head -1)
        if [ -n "$found_path" ]; then
            print_success "Найден через расширенный поиск: $found_path"
        fi
    fi
    
    echo "$found_path"
}

# Поиск всех бинарей
GRAFANA_PATH=$(find_binary "grafana-server")
PROMETHEUS_PATH=$(find_binary "prometheus")
HARVEST_PATH=$(find_binary "harvest")

# ==============================================================================
# 3. ПРОВЕРКА УСТАНОВЛЕННЫХ ПАКЕТОВ
# ==============================================================================

print_header "3. ПРОВЕРКА УСТАНОВЛЕННЫХ ПАКЕТОВ"

echo "Проверка установленных RPM пакетов..."
INSTALLED_PACKAGES=$(rpm -qa | grep -E "(grafana|prometheus|harvest)" | sort)

if [ -n "$INSTALLED_PACKAGES" ]; then
    print_success "Найдены пакеты:"
    echo "$INSTALLED_PACKAGES"
    
    # Показать файлы из пакетов
    for pkg in $INSTALLED_PACKAGES; do
        echo -e "\nФайлы из пакета $pkg:"
        rpm -ql "$pkg" | grep -E "(bin/|sbin/)" | head -3
    done
else
    print_error "Пакеты мониторинга не найдены"
fi

# ==============================================================================
# 4. СОЗДАНИЕ СИМВОЛИЧЕСКИХ ССЫЛОК
# ==============================================================================

print_header "4. СОЗДАНИЕ СИМВОЛИЧЕСКИХ ССЫЛОК"

# Создать директорию если не существует
if [ ! -d "$MONITORING_BIN_DIR" ]; then
    echo -e "${YELLOW}Создание директории $MONITORING_BIN_DIR...${NC}"
    sudo mkdir -p "$MONITORING_BIN_DIR"
    sudo chown CI10742292-lnx-mon_ci:CI10742292-lnx-mon_sys "$MONITORING_BIN_DIR"
    sudo chmod 750 "$MONITORING_BIN_DIR"
    print_success "Директория создана"
fi

# Функция для создания ссылки
create_link() {
    local source="$1"
    local link_name="$2"
    
    if [ -n "$source" ] && [ -f "$source" ] && [ -x "$source" ]; then
        if [ ! -L "$MONITORING_BIN_DIR/$link_name" ]; then
            echo -e "${GREEN}Создание ссылки: $link_name → $source${NC}"
            sudo ln -sf "$source" "$MONITORING_BIN_DIR/$link_name"
            print_success "Ссылка создана"
        else
            echo -e "${YELLOW}Ссылка уже существует: $link_name${NC}"
        fi
    else
        print_error "Не могу создать ссылку для $link_name - файл не найден"
    fi
}

# Создание ссылок
create_link "$GRAFANA_PATH" "grafana-server"
create_link "$PROMETHEUS_PATH" "prometheus"
create_link "$HARVEST_PATH" "harvest"

# ==============================================================================
# 5. ПРОВЕРКА РЕЗУЛЬТАТА
# ==============================================================================

print_header "5. ПРОВЕРКА РЕЗУЛЬТАТА"

echo "Проверка созданных ссылок:"
ls -la "$MONITORING_BIN_DIR/"

echo -e "\nПроверка прав:"
for binary in grafana-server prometheus harvest; do
    if [ -L "$MONITORING_BIN_DIR/$binary" ]; then
        echo "$binary: $(ls -la "$MONITORING_BIN_DIR/$binary" | awk '{print $1, $3, $4, $9, $10, $11}')"
    else
        print_error "$binary: ссылка не создана"
    fi
done

# ==============================================================================
# 6. ТЕСТИРОВАНИЕ ЗАПУСКА
# ==============================================================================

print_header "6. ТЕСТИРОВАНИЕ ЗАПУСКА"

# Функция тестирования бинаря
test_binary() {
    local binary_name="$1"
    local binary_path="$MONITORING_BIN_DIR/$binary_name"
    
    echo -n "Тестирование $binary_name: "
    
    if [ -L "$binary_path" ] && [ -x "$binary_path" ]; then
        if sudo -u CI10742292-lnx-mon_sys "$binary_path" --version &>/dev/null || \
           sudo -u CI10742292-lnx-mon_sys "$binary_path" version &>/dev/null; then
            print_success "работает"
        else
            print_warning "запускается, но может быть ошибка версии"
        fi
    else
        print_error "недоступен"
    fi
}

test_binary "grafana-server"
test_binary "prometheus"
test_binary "harvest"

# ==============================================================================
# 7. РЕКОМЕНДАЦИИ
# ==============================================================================

print_header "7. РЕКОМЕНДАЦИИ"

echo "Если ссылки созданы успешно, попробуйте запустить сервисы:"
echo ""
echo "  sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user start grafana'"
echo "  sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user status grafana'"
echo ""

if [ -z "$GRAFANA_PATH" ] || [ -z "$PROMETHEUS_PATH" ] || [ -z "$HARVEST_PATH" ]; then
    print_warning "Некоторые бинари не найдены. Возможные решения:"
    echo "  1. Проверить установку RPM пакетов через RLM"
    echo "  2. Убедиться что пакеты установлены корректно"
    echo "  3. Проверить пути установки: rpm -ql <package> | grep bin"
fi

print_header "СКРИПТ ЗАВЕРШЕН"
