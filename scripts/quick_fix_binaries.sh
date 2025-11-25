#!/bin/bash

# ==============================================================================
# Быстрый скрипт создания символических ссылок на бинари
# ==============================================================================

set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

MONITORING_BIN_DIR="/opt/monitoring/bin"

echo -e "${GREEN}Создание символических ссылок на бинари...${NC}"

# Создать директорию если не существует
if [ ! -d "$MONITORING_BIN_DIR" ]; then
    echo "Создание директории $MONITORING_BIN_DIR..."
    sudo mkdir -p "$MONITORING_BIN_DIR"
    sudo chown CI10742292-lnx-mon_ci:CI10742292-lnx-mon_sys "$MONITORING_BIN_DIR"
    sudo chmod 750 "$MONITORING_BIN_DIR"
fi

# Создание ссылок
echo ""

# Grafana
if [ -f "/usr/sbin/grafana-server" ] && [ -x "/usr/sbin/grafana-server" ]; then
    echo "Создание ссылки: grafana-server → /usr/sbin/grafana-server"
    sudo ln -sf "/usr/sbin/grafana-server" "$MONITORING_BIN_DIR/grafana-server"
    echo -e "${GREEN}✅ Grafana ссылка создана${NC}"
else
    echo -e "${RED}❌ Grafana-server не найден в /usr/sbin/${NC}"
fi

# Prometheus
if [ -f "/usr/bin/prometheus" ] && [ -x "/usr/bin/prometheus" ]; then
    echo "Создание ссылки: prometheus → /usr/bin/prometheus"
    sudo ln -sf "/usr/bin/prometheus" "$MONITORING_BIN_DIR/prometheus"
    echo -e "${GREEN}✅ Prometheus ссылка создана${NC}"
else
    echo -e "${RED}❌ Prometheus не найден в /usr/bin/${NC}"
fi

# Harvest
if [ -f "/opt/harvest/bin/harvest" ] && [ -x "/opt/harvest/bin/harvest" ]; then
    echo "Создание ссылки: harvest → /opt/harvest/bin/harvest"
    sudo ln -sf "/opt/harvest/bin/harvest" "$MONITORING_BIN_DIR/harvest"
    echo -e "${GREEN}✅ Harvest ссылка создана${NC}"
else
    echo -e "${RED}❌ Harvest не найден в /opt/harvest/bin/${NC}"
fi

# Проверка результата
echo ""
echo "Проверка созданных ссылок:"
ls -la "$MONITORING_BIN_DIR/"

echo ""
echo -e "${GREEN}Тестирование запуска сервисов...${NC}"
echo ""

# Тестирование запуска сервисов
for service in grafana prometheus harvest; do
    echo -n "Запуск $service: "
    if sudo -u CI10742292-lnx-mon_sys bash -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user start $service" &>/dev/null; then
        sleep 2
        if sudo -u CI10742292-lnx-mon_sys bash -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user is-active $service" &>/dev/null; then
            echo -e "${GREEN}✅ успешно${NC}"
        else
            echo -e "${RED}❌ ошибка${NC}"
        fi
    else
        echo -e "${RED}❌ не удалось запустить${NC}"
    fi
done

echo ""
echo -e "${GREEN}Проверка статуса сервисов:${NC}"
for service in grafana prometheus harvest; do
    echo ""
    echo "$service:"
    sudo -u CI10742292-lnx-mon_sys bash -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user status $service" | grep -E "(Active|Main PID|status)" | head -3
done
