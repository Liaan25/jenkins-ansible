# Роль: rlm_standard_setup

## Назначение

Настройка сервисов мониторинга (Prometheus, Grafana, Harvest) по стандартным путям после установки RLM пакетов. Соответствует подходу из `deploy_monitoring.sh`, но с соблюдением принципов безопасности проекта `secure_deployment`.

## Отличия от безопасного режима

| Аспект | Безопасный режим | Стандартный RLM режим |
|--------|------------------|----------------------|
| **Пользователи** | Непривилегированные УЗ (monitoring_svc) | Системные пользователи (prometheus, grafana, harvest) |
| **Пути конфигов** | `/opt/monitoring/config/` | `/etc/prometheus/`, `/etc/grafana/`, `/opt/harvest/` |
| **Пути данных** | `/opt/monitoring/data/` | `/var/lib/prometheus/`, `/var/lib/grafana/`, `/var/lib/harvest/` |
| **Systemd units** | User units в `~/.config/systemd/user/` | System units в `/etc/systemd/system/` |
| **Секреты** | `/dev/shm/monitoring_secrets/` | Системные пути сертификатов |

## Использование

### Включение в playbook

```yaml
- name: "Настройка сервисов по стандартным путям"
  hosts: all
  roles:
    - role: rlm_standard_setup
  when: use_rlm_standard_setup | default(false)
```

### Переменные

```yaml
# Параметры портов
prometheus_port: 9090
grafana_port: 3000
harvest_unix_port: 12991
harvest_netapp_port: 12990

# Параметры NetApp
netapp_poller_name: "netapp-cluster"
netapp_api_addr: "netapp-cluster.example.com"
netapp_api_user: "admin"
netapp_api_password: "password"

# Флаг режима
use_rlm_standard_setup: true
```

## Процесс выполнения

1. **Проверка RLM пакетов** - проверка установленных prometheus, grafana, harvest
2. **Остановка системных сервисов** - остановка и маскировка стандартных сервисов
3. **Настройка сертификатов** - копирование сертификатов в системные пути
4. **Конфигурация Prometheus** - настройка prometheus.yml, web-config.yml
5. **Конфигурация Grafana** - настройка grafana.ini, provisioning
6. **Конфигурация Harvest** - настройка harvest.yml, systemd сервиса
7. **Запуск сервисов** - включение и запуск системных сервисов

## Соответствие deploy_monitoring.sh

Роль реализует те же функции что и соответствующие разделы в `deploy_monitoring.sh`:

- `configure_prometheus()` → Prometheus конфигурация
- `configure_grafana_ini()` → Grafana конфигурация  
- `configure_harvest()` → Harvest конфигурация
- `configure_services()` → Запуск сервисов

## Безопасность

Несмотря на использование стандартных путей, роль соблюдает принципы безопасности:

- Правильные права доступа на файлы сертификатов
- Использование TLS/mTLS для всех соединений
- Ограничение доступа к приватным ключам (0600)
- Проверка валидности конфигурационных файлов

## Проверка

После выполнения роли можно проверить статус сервисов:

```bash
systemctl status prometheus
systemctl status grafana-server  
systemctl status harvest
```

И доступность сервисов:

```bash
curl -k https://localhost:9090/-/healthy
curl -k https://localhost:3000/api/health
```
