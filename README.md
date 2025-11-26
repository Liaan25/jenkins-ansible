# Безопасное развертывание системы мониторинга

## Обзор

Проект предоставляет два режима развертывания системы мониторинга (Prometheus + Grafana + Harvest):

### 🔧 Режим 1: Стандартная RLM установка

**Параметр:** `USE_RLM_STANDARD_SETUP = true`

Соответствует подходу из `deploy_monitoring.sh`:
- **Пользователи:** системные (prometheus, grafana, harvest)
- **Пути конфигов:** стандартные (`/etc/prometheus/`, `/etc/grafana/`, `/opt/harvest/`)
- **Пути данных:** системные (`/var/lib/prometheus/`, `/var/lib/grafana/`)
- **Systemd units:** системные сервисы
- **Секреты:** системные пути сертификатов

### 🔒 Режим 2: Безопасная установка

**Параметр:** `USE_RLM_STANDARD_SETUP = false`

Оригинальный подход secure_deployment:
- **Пользователи:** непривилегированные УЗ (monitoring_svc, monitoring_ci, etc.)
- **Пути конфигов:** прикладные (`/opt/monitoring/config/`)
- **Пути данных:** прикладные (`/opt/monitoring/data/`)
- **Systemd units:** user units в `~/.config/systemd/user/`
- **Секреты:** `/dev/shm/monitoring_secrets/`

## Использование

### Jenkins Pipeline

В Jenkins pipeline доступен параметр `USE_RLM_STANDARD_SETUP`:

```groovy
booleanParam(
    name: 'USE_RLM_STANDARD_SETUP',
    defaultValue: true,
    description: '''Использовать стандартную установку через RLM пакеты:
• true: Стандартные системные сервисы (prometheus, grafana-server, harvest)
• false: Безопасные пользовательские сервисы (изолированные пути)'''
)
```

### Ansible Playbook

В Ansible playbook используется переменная `use_rlm_standard_setup`:

```yaml
- name: "Настройка сервисов по стандартным путям"
  hosts: all
  roles:
    - role: rlm_standard_setup
  when: use_rlm_standard_setup | default(false)
```

## Проверка установки

### Стандартный RLM режим

```bash
# Проверка системных сервисов
systemctl status prometheus
systemctl status grafana-server
systemctl status harvest

# Проверка конфигурационных файлов
ls -la /etc/prometheus/
ls -la /etc/grafana/
ls -la /opt/harvest/

# Запуск скрипта проверки
sudo bash /opt/monitoring/scripts/verify_rlm_standard_setup.sh
```

### Безопасный режим

```bash
# Проверка пользовательских сервисов
sudo -u monitoring_svc -g monitoring_svc systemctl --user status prometheus
sudo -u monitoring_svc -g monitoring_svc systemctl --user status grafana
sudo -u monitoring_svc -g monitoring_svc systemctl --user status harvest

# Проверка конфигурационных файлов
ls -la /opt/monitoring/config/
ls -la /opt/monitoring/data/

# Запуск скрипта проверки безопасности
sudo bash /opt/monitoring/scripts/verify_security.sh
```

## Архитектура

### Стандартный RLM режим

```
/etc/prometheus/
├── prometheus.yml
├── web-config.yml
└── cert/
    ├── server.crt
    └── server.key

/etc/grafana/
├── grafana.ini
└── cert/
    ├── crt.crt
    └── key.key

/opt/harvest/
├── harvest.yml
└── cert/
    ├── server.crt
    └── server.key
```

### Безопасный режим

```
/opt/monitoring/
├── config/
│   ├── prometheus.yml
│   ├── web-config.yml
│   ├── grafana.ini
│   └── harvest.yml
├── data/
│   ├── prometheus/
│   ├── grafana/
│   └── harvest/
└── certs/
    ├── server_bundle.pem
    └── ca_chain.crt
```

## Безопасность

Оба режима соблюдают принципы безопасности:

- Правильные права доступа на файлы сертификатов
- Использование TLS/mTLS для всех соединений
- Ограничение доступа к приватным ключам (0600)
- Проверка валидности конфигурационных файлов
- Изоляция секретов в tmpfs (`/dev/shm/`)


