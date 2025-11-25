# Структура файловой системы

## Общая схема

```
/opt/monitoring/                          # Основная директория (владелец: monitoring_ci)
├── bin/                                  # Бинарные файлы (750, monitoring_ci:monitoring)
│   ├── prometheus                        # Бинарник Prometheus
│   ├── grafana-server                    # Бинарник Grafana
│   └── harvest                           # Бинарник Harvest
│
├── config/                               # Конфигурационные файлы (750, monitoring_ci:monitoring)
│   ├── prometheus.yml                    # Конфигурация Prometheus
│   ├── web-config.yml                    # TLS конфигурация Prometheus
│   ├── grafana.ini                       # Конфигурация Grafana
│   └── harvest.yml                       # Конфигурация Harvest
│
├── data/                                 # Данные приложений (770, monitoring_svc:monitoring)
│   └── prometheus/                       # TSDB Prometheus
│       └── wal/                          # Write-Ahead Log
│
├── logs/                                 # Логи приложений (770, monitoring_svc:monitoring_admin)
│   ├── prometheus/
│   │   └── prometheus.log
│   ├── grafana/
│   │   └── grafana.log
│   └── harvest/
│       └── harvest.log
│
└── scripts/                              # Утилитарные скрипты (755, monitoring_ci:monitoring)
    ├── verify_security.sh                # Проверка безопасности
    ├── rotate_secrets.sh                 # Ротация секретов
    └── cleanup_secrets.sh                # Очистка секретов

/dev/shm/monitoring_secrets/              # Секреты в RAM (700, monitoring_svc:monitoring)
├── server.crt                            # Серверный сертификат (640)
├── server.key                            # Серверный ключ (600)
├── client.crt                            # Клиентский сертификат (640)
├── client.key                            # Клиентский ключ (600)
├── grafana-client.crt                    # Сертификат Grafana (640)
├── grafana-client.key                    # Ключ Grafana (600)
└── ca_chain.crt                          # CA цепочка (644)

$HOME/.config/systemd/user/               # User systemd units (monitoring_svc)
├── prometheus.service                    # Systemd unit для Prometheus
├── grafana.service                       # Systemd unit для Grafana
├── harvest.service                       # Systemd unit для Harvest
└── vault-agent-monitoring.service        # Systemd unit для Vault Agent
```

## Детальное описание

### /opt/monitoring/bin/

Исполняемые файлы приложений.

**Владелец**: monitoring_ci  
**Группа**: monitoring  
**Права**: 750 (rwxr-x---)

**Кто может**:
- Писать: monitoring_ci (обновление при деплое)
- Читать/Выполнять: monitoring_ci, monitoring_svc, monitoring_admin

### /opt/monitoring/config/

Конфигурационные файлы.

**Владелец**: monitoring_ci  
**Группа**: monitoring  
**Права**: 750 (rwxr-x---)

**Отдельные файлы**:
- `prometheus.yml` - scrape configs, правила
- `web-config.yml` - TLS настройки
- `grafana.ini` - настройки Grafana
- `harvest.yml` - pollers для NetApp

### /opt/monitoring/data/

Хранение данных приложений (TSDB для Prometheus).

**Владелец**: monitoring_svc  
**Группа**: monitoring  
**Права**: 770 (rwxrwx---)

**Размер**: 4GB (через RLM)

**Кто может**:
- Писать: monitoring_svc (только сервис может писать данные)
- Читать: monitoring_svc, члены группы monitoring

### /opt/monitoring/logs/

Логи всех приложений.

**Владелец**: monitoring_svc  
**Группа**: monitoring_admin  
**Права**: 770 (rwxrwx---)

**Размер**: 2GB (через RLM)

**Ротация**: через logrotate или systemd

**Кто может**:
- Писать: monitoring_svc
- Читать: monitoring_svc, monitoring_admin, monitoring_ro

### /dev/shm/monitoring_secrets/

Секреты в tmpfs (в оперативной памяти).

**Владелец**: monitoring_svc  
**Группа**: monitoring  
**Права**: 700 (rwx------)

**Особенности**:
- Находится в RAM (не на диске)
- Автоматически очищается при перезагрузке
- Доступ ТОЛЬКО у monitoring_svc

### ~/.config/systemd/user/

User systemd units для сервисов.

**Расположение**: `/home/monitoring_svc/.config/systemd/user/`

**Управление**: через `systemctl --user`

**Автозапуск**: `loginctl enable-linger monitoring_svc`

## Команды создания структуры

```bash
# От пользователя monitoring_ci

# 1. Создать основную структуру (если через RLM не создана)
sudo mkdir -p /opt/monitoring/{bin,config,scripts}

# 2. Установить права
sudo chmod 750 /opt/monitoring/bin
sudo chmod 750 /opt/monitoring/config
sudo chmod 755 /opt/monitoring/scripts

# 3. Установить владельцев
sudo chown -R monitoring_ci:monitoring /opt/monitoring/bin
sudo chown -R monitoring_ci:monitoring /opt/monitoring/config
sudo chown -R monitoring_ci:monitoring /opt/monitoring/scripts

# 4. Создать директории для data и logs (через RLM уже созданы с нужными владельцами)
sudo chown -R monitoring_svc:monitoring /opt/monitoring/data
sudo chown -R monitoring_svc:monitoring_admin /opt/monitoring/logs

# 5. Создать директорию для секретов в tmpfs
sudo -u monitoring_svc mkdir -p /dev/shm/monitoring_secrets
sudo -u monitoring_svc chmod 700 /dev/shm/monitoring_secrets

# 6. Создать директорию для user systemd units
sudo -u monitoring_svc mkdir -p ~/.config/systemd/user
```

## Проверка структуры

```bash
# Проверка дерева директорий
tree -L 2 /opt/monitoring

# Проверка прав
ls -la /opt/monitoring/

# Проверка владельцев
ls -lR /opt/monitoring/ | grep ^d

# Проверка /dev/shm
ls -la /dev/shm/ | grep monitoring
```

## Матрица доступа

| Путь | monitoring_svc | monitoring_admin | monitoring_ci | monitoring_ro |
|------|----------------|------------------|---------------|---------------|
| /opt/monitoring/ | r-x | r-x | rwx | r-x |
| /opt/monitoring/bin/ | r-x | r-x | rwx | r-x |
| /opt/monitoring/config/ | r-x | r-x | rwx | r-x |
| /opt/monitoring/data/ | rwx | r-x (через группу) | --- | --- |
| /opt/monitoring/logs/ | rwx | r-x | --- | r-x |
| /dev/shm/monitoring_secrets/ | rwx | --- | --- | --- |

**Легенда**: r=read, w=write, x=execute, -=нет доступа






