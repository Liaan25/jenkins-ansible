#!/bin/bash
# Скрипт проверки работы стандартной RLM установки
# Проверяет настройки сервисов по стандартным путям

set -euo pipefail

# Цвета
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

echo "=================================================="
echo "ПРОВЕРКА СТАНДАРТНОЙ RLM УСТАНОВКИ"
echo "=================================================="
echo

# 1. Проверка системных пользователей
echo "[1] Проверка системных пользователей..."
for user in prometheus grafana harvest; do
    if id "$user" &>/dev/null; then
        print_success "Пользователь $user существует"
    else
        print_error "Пользователь $user НЕ существует"
    fi
done
echo

# 2. Проверка конфигурационных файлов
echo "[2] Проверка конфигурационных файлов..."
for config in \
    "/etc/prometheus/prometheus.yml" \
    "/etc/prometheus/web-config.yml" \
    "/etc/grafana/grafana.ini" \
    "/opt/harvest/harvest.yml"; do
    if [[ -f "$config" ]]; then
        print_success "Конфиг $config существует"
    else
        print_error "Конфиг $config НЕ существует"
    fi
done
echo

# 3. Проверка сертификатов
echo "[3] Проверка сертификатов..."
for cert in \
    "/etc/prometheus/cert/server.crt" \
    "/etc/prometheus/cert/server.key" \
    "/etc/grafana/cert/crt.crt" \
    "/etc/grafana/cert/key.key" \
    "/opt/harvest/cert/server.crt" \
    "/opt/harvest/cert/server.key"; do
    if [[ -f "$cert" ]]; then
        print_success "Сертификат $cert существует"
        # Проверка прав
        perms=$(stat -c '%a' "$cert" 2>/dev/null || echo "000")
        if [[ "$cert" =~ \.key$ ]] && [[ "$perms" == "600" ]]; then
            print_success "  Права корректны: $perms"
        elif [[ "$cert" =~ \.crt$ ]] && [[ "$perms" =~ ^[46][46]0$ ]]; then
            print_success "  Права корректны: $perms"
        else
            print_error "  Неправильные права: $perms"
        fi
    else
        print_error "Сертификат $cert НЕ существует"
    fi
done
echo

# 4. Проверка systemd сервисов
echo "[4] Проверка systemd сервисов..."
for service in prometheus grafana-server harvest; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_success "Сервис $service активен"
    else
        print_error "Сервис $service НЕ активен"
    fi
    
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        print_success "Сервис $service включен в автозапуск"
    else
        print_error "Сервис $service НЕ включен в автозапуск"
    fi
done
echo

# 5. Проверка портов
echo "[5] Проверка открытых портов..."
for port in 9090 3000 12990 12991; do
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        print_success "Порт $port открыт"
    else
        print_error "Порт $port НЕ открыт"
    fi
done
echo

# 6. Проверка доступности сервисов
echo "[6] Проверка доступности сервисов..."

# Prometheus
if curl -k -s https://localhost:9090/-/healthy | grep -q "Prometheus is Healthy"; then
    print_success "Prometheus доступен и здоров"
else
    print_error "Prometheus НЕ доступен"
fi

# Grafana
if curl -k -s https://localhost:3000/api/health | grep -q '"database":"ok"'; then
    print_success "Grafana доступен и здоров"
else
    print_error "Grafana НЕ доступен"
fi

echo
echo "=================================================="
echo "ПРОВЕРКА ЗАВЕРШЕНА"
echo "=================================================="
echo

print_info "Для дополнительной проверки можно выполнить:"
echo "  journalctl -u prometheus -n 20"
echo "  journalctl -u grafana-server -n 20"  
echo "  journalctl -u harvest -n 20"
echo "  harvest status --config /opt/harvest/harvest.yml"
