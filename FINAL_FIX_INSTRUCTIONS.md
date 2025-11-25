# 🚀 ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ ВСЕХ ПРОБЛЕМ

## Обнаруженные проблемы

### 1. Grafana
- **Проблема**: `/usr/share/grafana/bin/grafana not installed or not executable`
- **Причина**: Неправильный `--homepath` в аргументах
- **Исправление**: Используем `--homepath=/usr/share/grafana`

### 2. Harvest  
- **Проблема**: Ошибка YAML на строке 60 `cannot unmarshal !!seq into string`
- **Причина**: Неправильный формат labels в конфигурации
- **Исправление**: Исправлен синтаксис labels

### 3. Prometheus
- **Проблема**: Ошибка YAML на строках 99-100 `field path/retention not found`
- **Причина**: Неправильный синтаксис retention для версии 2.55.1
- **Исправление**: Использован правильный синтаксис `retention_time` и `retention_size`

## СРОЧНОЕ ИСПРАВЛЕНИЕ

### Вариант 1: Перезапуск пайплайна Jenkins
```bash
# Запустите пайплайн Jenkins с обновленными templates
# Убедитесь что все флаги SKIP сняты
```

### Вариант 2: Ручное исправление на сервере

#### 1. Исправить конфигурацию Harvest
```bash
sudo -u CI10742292-lnx-mon_sys bash -c 'cat > /opt/monitoring/config/harvest.yml << "EOF"
# Вставьте содержимое исправленного harvest.yml здесь
EOF'
```

#### 2. Исправить Grafana service
```bash
sudo -u CI10742292-lnx-mon_sys bash -c 'cat > /home/CI10742292-lnx-mon_sys/.config/systemd/user/grafana.service << "EOF"
[Unit]
Description=Grafana Visualization Platform (User Service)
Documentation=https://grafana.com/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/monitoring
ExecStart=/usr/sbin/grafana-server \
  --config=/opt/monitoring/config/grafana.ini \
  --homepath=/usr/share/grafana \
  cfg:default.paths.logs=/opt/monitoring/logs/grafana \
  cfg:default.paths.data=/opt/monitoring/data/grafana
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=30s
Restart=on-failure
RestartSec=10s
Environment="PATH=/opt/monitoring/bin:/usr/local/bin:/usr/bin:/bin"
Environment="GF_PATHS_CONFIG=/opt/monitoring/config/grafana.ini"
Environment="GF_PATHS_DATA=/opt/monitoring/data/grafana"
Environment="GF_PATHS_LOGS=/opt/monitoring/logs/grafana"
LimitNOFILE=10000
LimitNPROC=512
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/opt/monitoring/data/grafana
ReadWritePaths=/opt/monitoring/logs/grafana
ReadOnlyPaths=/opt/monitoring/bin
ReadOnlyPaths=/opt/monitoring/config
ReadOnlyPaths=/dev/shm/monitoring_secrets
StandardOutput=journal
StandardError=journal
SyslogIdentifier=grafana

[Install]
WantedBy=default.target
EOF'
```

#### 3. Перезапустить сервисы
```bash
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user daemon-reload'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user restart grafana prometheus harvest'

# Проверить статус
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status grafana'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status prometheus'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status harvest'
```

## Проверка исправления

После исправлений выполните:

```bash
# Проверить запуск вручную
sudo -u CI10742292-lnx-mon_sys /usr/sbin/grafana-server --config=/opt/monitoring/config/grafana.ini --homepath=/usr/share/grafana cfg:default.paths.logs=/opt/monitoring/logs/grafana cfg:default.paths.data=/opt/monitoring/data/grafana

sudo -u CI10742292-lnx-mon_sys /opt/harvest/bin/harvest start --config /opt/monitoring/config/harvest.yml --promPort 12990

sudo -u CI10742292-lnx-mon_sys /usr/bin/prometheus --config.file=/opt/monitoring/config/prometheus.yml --web.config.file=/opt/monitoring/config/web-config.yml --storage.tsdb.path=/opt/monitoring/data/prometheus --storage.tsdb.retention.time=15d --storage.tsdb.retention.size=3GB --web.listen-address=:9090
```

## Ожидаемый результат

Все три сервиса должны запускаться без ошибок и иметь статус `active (running)`.
