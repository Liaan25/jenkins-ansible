#!/bin/bash
# Скрипт проверки соответствия требованиям безопасности
#
# Использование:
#   ./verify_security.sh [USER_SYS] [USER_ADMIN] [USER_CI] [USER_RO]
#
# Пример (статические имена):
#   ./verify_security.sh
#
# Пример (динамические имена):
#   ./verify_security.sh CI10742292-lnx-mon_sys CI10742292-lnx-mon_admin CI10742292-lnx-mon_ci CI10742292-lnx-mon_ro

set -euo pipefail

# Имена пользователей (можно переопределить параметрами)
USER_SYS="${1:-monitoring_svc}"
USER_ADMIN="${2:-monitoring_admin}"
USER_CI="${3:-monitoring_ci}"
USER_RO="${4:-monitoring_ro}"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_COUNT++))
}

echo "=================================================="
echo "ПРОВЕРКА БЕЗОПАСНОСТИ СИСТЕМЫ МОНИТОРИНГА"
echo "=================================================="
echo -e "${BLUE}Используемые пользователи:${NC}"
echo "  Сервисная (СУЗ): $USER_SYS"
echo "  Администратор (ПУЗ): $USER_ADMIN"
echo "  CI/CD (ТУЗ): $USER_CI"
echo "  ReadOnly: $USER_RO"
echo ""

# 1. Проверка учетных записей
echo "[1] Проверка учетных записей..."
if id "$USER_SYS" &>/dev/null; then
    check_pass "УЗ $USER_SYS существует"
    
    # Проверка NoLogin
    shell=$(getent passwd "$USER_SYS" | cut -d: -f7)
    if [[ "$shell" == "/sbin/nologin" ]] || [[ "$shell" == "/bin/false" ]]; then
        check_pass "$USER_SYS имеет NoLogin shell: $shell"
    else
        check_fail "$USER_SYS НЕ имеет NoLogin shell: $shell"
    fi
else
    check_fail "УЗ $USER_SYS НЕ существует"
fi

if id "$USER_ADMIN" &>/dev/null; then
    check_pass "УЗ $USER_ADMIN существует"
else
    check_warn "УЗ $USER_ADMIN не существует"
fi

if id "$USER_CI" &>/dev/null; then
    check_pass "УЗ $USER_CI существует"
else
    check_warn "УЗ $USER_CI не существует"
fi

if id "$USER_RO" &>/dev/null; then
    check_pass "УЗ $USER_RO существует"
else
    check_warn "УЗ $USER_RO не существует"
fi

echo ""

# 2. Проверка структуры директорий
echo "[2] Проверка структуры файловой системы..."

if [[ -d "/opt/monitoring" ]]; then
    check_pass "Директория /opt/monitoring существует"
    
    for dir in bin config data logs; do
        if [[ -d "/opt/monitoring/$dir" ]]; then
            check_pass "Директория /opt/monitoring/$dir существует"
        else
            check_fail "Директория /opt/monitoring/$dir НЕ существует"
        fi
    done
else
    check_fail "Директория /opt/monitoring НЕ существует"
fi

echo ""

# 3. Проверка прав на файлы
echo "[3] Проверка прав доступа..."

if [[ -d "/opt/monitoring/bin" ]]; then
    perms=$(stat -c '%a' "/opt/monitoring/bin" 2>/dev/null || echo "000")
    if [[ "$perms" == "750" ]]; then
        check_pass "/opt/monitoring/bin имеет права 750"
    else
        check_warn "/opt/monitoring/bin имеет права $perms (ожидается 750)"
    fi
fi

if [[ -d "/opt/monitoring/data" ]]; then
    perms=$(stat -c '%a' "/opt/monitoring/data" 2>/dev/null || echo "000")
    if [[ "$perms" == "770" ]]; then
        check_pass "/opt/monitoring/data имеет права 770"
    else
        check_warn "/opt/monitoring/data имеет права $perms (ожидается 770)"
    fi
fi

if [[ -d "/dev/shm/monitoring_secrets" ]]; then
    perms=$(stat -c '%a' "/dev/shm/monitoring_secrets" 2>/dev/null || echo "000")
    owner=$(stat -c '%U' "/dev/shm/monitoring_secrets" 2>/dev/null || echo "unknown")
    
    if [[ "$perms" == "700" ]]; then
        check_pass "/dev/shm/monitoring_secrets имеет права 700"
    else
        check_fail "/dev/shm/monitoring_secrets имеет неправильные права: $perms (должно быть 700)"
    fi
    
    if [[ "$owner" == "$USER_SYS" ]]; then
        check_pass "/dev/shm/monitoring_secrets принадлежит $USER_SYS"
    else
        check_fail "/dev/shm/monitoring_secrets принадлежит $owner (должно быть $USER_SYS)"
    fi
else
    check_warn "/dev/shm/monitoring_secrets не существует"
fi

echo ""

# 4. Проверка systemd units
echo "[4] Проверка systemd units..."

USER_HOME=$(getent passwd "$USER_SYS" 2>/dev/null | cut -d: -f6)
if [[ -n "$USER_HOME" ]] && [[ -d "$USER_HOME/.config/systemd/user" ]]; then
    check_pass "Директория user systemd units существует ($USER_HOME/.config/systemd/user)"
    
    for service in prometheus grafana harvest vault-agent-monitoring; do
        if [[ -f "$USER_HOME/.config/systemd/user/${service}.service" ]]; then
            check_pass "Unit файл ${service}.service существует"
        else
            check_warn "Unit файл ${service}.service не найден"
        fi
    done
else
    check_warn "Директория user systemd units не существует"
fi

echo ""

# 5. Проверка Vault Agent
echo "[5] Проверка Vault Agent..."

if [[ -f "/opt/vault/conf/role_id.txt" ]]; then
    check_pass "role_id.txt существует"
    perms=$(stat -c '%a' "/opt/vault/conf/role_id.txt")
    if [[ "$perms" == "640" ]] || [[ "$perms" == "600" ]]; then
        check_pass "role_id.txt имеет безопасные права: $perms"
    else
        check_fail "role_id.txt имеет небезопасные права: $perms"
    fi
else
    check_warn "role_id.txt не найден"
fi

if [[ -f "/opt/vault/conf/secret_id.txt" ]]; then
    check_pass "secret_id.txt существует"
    perms=$(stat -c '%a' "/opt/vault/conf/secret_id.txt")
    if [[ "$perms" == "640" ]] || [[ "$perms" == "600" ]]; then
        check_pass "secret_id.txt имеет безопасные права: $perms"
    else
        check_fail "secret_id.txt имеет небезопасные права: $perms"
    fi
else
    check_warn "secret_id.txt не найден"
fi

echo ""

# 6. Проверка сертификатов
echo "[6] Проверка сертификатов..."

if [[ -d "/dev/shm/monitoring_secrets" ]]; then
    for cert in server.crt client.crt grafana-client.crt; do
        if [[ -f "/dev/shm/monitoring_secrets/$cert" ]]; then
            check_pass "$cert существует"
            
            # Проверка срока действия
            expiry=$(openssl x509 -in "/dev/shm/monitoring_secrets/$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [[ -n "$expiry" ]]; then
                expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
                current_epoch=$(date +%s)
                days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
                
                if [[ $days_left -lt 0 ]]; then
                    check_fail "$cert ИСТЕК!"
                elif [[ $days_left -lt 7 ]]; then
                    check_warn "$cert истекает через $days_left дней"
                else
                    check_pass "$cert действителен еще $days_left дней"
                fi
            fi
        else
            check_warn "$cert не найден"
        fi
    done
    
    for key in server.key client.key grafana-client.key; do
        if [[ -f "/dev/shm/monitoring_secrets/$key" ]]; then
            perms=$(stat -c '%a' "/dev/shm/monitoring_secrets/$key")
            if [[ "$perms" == "600" ]]; then
                check_pass "$key имеет безопасные права (600)"
            else
                check_fail "$key имеет небезопасные права: $perms (должно быть 600)"
            fi
        else
            check_warn "$key не найден"
        fi
    done
fi

echo ""

# 7. Проверка портов
echo "[7] Проверка открытых портов..."

for port in 9090 3000 12990 12991; do
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        check_pass "Порт $port открыт"
    else
        check_warn "Порт $port не открыт"
    fi
done

echo ""

# 8. Проверка firewall
echo "[8] Проверка firewall правил..."

if command -v iptables &>/dev/null; then
    if sudo iptables -L INPUT -n 2>/dev/null | grep -q "9090"; then
        check_pass "Правила iptables для Prometheus настроены"
    else
        check_warn "Правила iptables для Prometheus не найдены"
    fi
else
    check_warn "iptables не доступен для проверки"
fi

echo ""

# Итоги
echo "=================================================="
echo "РЕЗУЛЬТАТЫ ПРОВЕРКИ:"
echo "=================================================="
echo -e "${GREEN}Пройдено:${NC} $PASS_COUNT"
echo -e "${YELLOW}Предупреждений:${NC} $WARN_COUNT"
echo -e "${RED}Ошибок:${NC} $FAIL_COUNT"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ Система соответствует требованиям безопасности${NC}"
    exit 0
else
    echo -e "${RED}✗ Обнаружены проблемы безопасности. Требуется исправление.${NC}"
    exit 1
fi


