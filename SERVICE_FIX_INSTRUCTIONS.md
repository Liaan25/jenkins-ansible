# 🚀 Инструкция по тестированию исправлений сервисов

## Исправленные проблемы

### 1. Grafana
- **Проблема**: Не мог найти `/usr/share/grafana/bin/grafana`
- **Исправление**: Используем `/usr/sbin/grafana-server` напрямую

### 2. Prometheus  
- **Проблема**: Ошибка YAML в конфигурации (`field path not found`)
- **Исправление**: Обновлен синтаксис retention для версии 2.55.1

### 3. Harvest
- **Проблема**: Неправильные аргументы командной строки
- **Исправление**: Убраны неподдерживаемые флаги `--loglevel` и `--restPort`

## Тестирование исправлений

### 1. Перезапуск пайплайна Jenkins
```bash
# Запустите пайплайн Jenkins с обновленными templates
# Убедитесь что флаги SKIP_RLM_VAULT_AGENT и SKIP_TO_VERIFICATION сняты
```

### 2. Ручное тестирование (если нужно быстро проверить)

#### Grafana
```bash
sudo -u CI10742292-lnx-mon_sys /usr/sbin/grafana-server --config=/opt/monitoring/config/grafana.ini --homepath=/opt/monitoring cfg:default.paths.logs=/opt/monitoring/logs/grafana cfg:default.paths.data=/opt/monitoring/data/grafana cfg:default.paths.plugins=/opt/monitoring/data/grafana/plugins cfg:default.paths.provisioning=/opt/monitoring/config/provisioning
```

#### Prometheus
```bash
sudo -u CI10742292-lnx-mon_sys /usr/bin/prometheus --config.file=/opt/monitoring/config/prometheus.yml --web.config.file=/opt/monitoring/config/web-config.yml --storage.tsdb.path=/opt/monitoring/data/prometheus --web.console.templates=/opt/monitoring/consoles --web.console.libraries=/opt/monitoring/console_libraries --storage.tsdb.retention.time=15d --storage.tsdb.retention.size=3GB --web.listen-address=:9090
```

#### Harvest
```bash
sudo -u CI10742292-lnx-mon_sys /opt/harvest/bin/harvest start --config /opt/monitoring/config/harvest.yml --promPort 12990
```

### 3. Проверка сервисов после развертывания

```bash
# Проверить статус сервисов
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status grafana'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status prometheus'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status harvest'

# Проверить доступность портов
sudo netstat -tlnp | grep -E "(9090|3000|12990)"

# Проверить логи
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u grafana -f'
```

## Ожидаемый результат

После исправлений все три сервиса должны:
- ✅ Запускаться без ошибок
- ✅ Иметь статус `active (running)`
- ✅ Слушать на соответствующих портах
- ✅ Писать логи в journald

## Примечания

- **Grafana**: Теперь использует правильный бинарный файл `/usr/sbin/grafana-server`
- **Prometheus**: Конфигурация совместима с версией 2.55.1
- **Harvest**: Использует только поддерживаемые аргументы командной строки
- **Символические ссылки**: Остаются в `/opt/monitoring/bin/` для единообразия
