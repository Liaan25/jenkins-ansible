# Ansible Roles - Документация

## Обзор ролей

Проект использует модульную архитектуру с отдельными ролями для каждого компонента:

| Роль | Описание | Ответственность |
|------|----------|----------------|
| `common` | Общая подготовка | Создание директорий, пользователей, базовая настройка |
| `vault_agent` | Vault Agent | Управление секретами, сертификатами |
| `prometheus` | Prometheus | Сбор метрик, storage |
| `grafana` | Grafana | Визуализация, дашборды |
| `harvest` | NetApp Harvest | Сбор метрик с NetApp кластеров |

## Структура роли

Каждая роль имеет стандартную структуру:

```
role_name/
├── tasks/
│   └── main.yml          # Основные задачи
├── handlers/
│   └── main.yml          # Обработчики событий
├── templates/
│   └── *.j2              # Jinja2 шаблоны
├── files/
│   └── *                 # Статические файлы
└── defaults/
    └── main.yml          # Переменные по умолчанию (опционально)
```

## Использование ролей

### В playbook

```yaml
- name: "Установка Prometheus"
  hosts: monitoring_servers
  become: yes
  
  roles:
    - role: prometheus
      tags: [prometheus]
```

### Отдельно

```bash
ansible-playbook -i inventory playbook.yml --tags "prometheus"
```

## Детальное описание ролей

### 1. common

**Задачи**:
- Создание базовых директорий
- Проверка пользователей
- Установка зависимостей
- Настройка lingering для systemd user

**Теги**: `setup`, `check`, `directories`

**Переменные**:
- `monitoring_base_dir`
- `monitoring_service_user`
- `monitoring_ci_user`

---

### 2. vault_agent

**Задачи**:
- Создание директорий для Vault
- Копирование конфигурации Vault Agent (Jinja2)
- Установка systemd unit
- Запуск Vault Agent
- Ожидание получения секретов

**Handlers**:
- `reload systemd user` - перезагрузка systemd
- `restart vault-agent` - перезапуск Vault Agent

**Templates**:
- `vault-agent.hcl.j2` - главная конфигурация

**Теги**: `setup`, `config`, `systemd`, `service`, `wait`

**Важно**: Требует наличия `role_id.txt` и `secret_id.txt` в `/opt/vault/conf/`

---

### 3. prometheus

**Задачи**:
- Создание директорий для данных
- Копирование конфигурации (Jinja2)
- Копирование TLS конфигурации
- Установка systemd unit
- Запуск сервиса

**Handlers**:
- `reload prometheus` - graceful reload конфигурации
- `restart prometheus` - полный перезапуск

**Templates**:
- `prometheus.yml.j2` - основная конфигурация
- `web-config.yml.j2` - TLS настройки

**Теги**: `setup`, `config`, `systemd`, `service`

**Переменные**:
- `prometheus_port`
- `prometheus.scrape_interval`
- `prometheus.retention_time`

---

### 4. grafana

**Задачи**:
- Создание директорий для данных
- Создание директорий provisioning
- Копирование конфигурации (Jinja2)
- Копирование datasource provisioning
- Установка systemd unit
- Запуск сервиса

**Handlers**:
- `restart grafana` - перезапуск Grafana

**Templates**:
- `grafana.ini.j2` - главная конфигурация

**Files**:
- `provisioning/datasources/prometheus.yml` - автоматическая настройка Prometheus datasource
- `provisioning/dashboards/dashboards.yml` - конфигурация дашбордов

**Теги**: `setup`, `config`, `provisioning`, `systemd`, `service`

**Переменные**:
- `grafana_port`
- `grafana.protocol`
- `grafana.allow_embedding`

**Важно**: Admin пароль должен быть в environment `GF_SECURITY_ADMIN_PASSWORD`

---

### 5. harvest

**Задачи**:
- Создание директорий для данных
- Копирование конфигурации (Jinja2)
- Установка systemd unit
- Запуск сервиса

**Handlers**:
- `restart harvest` - перезапуск Harvest

**Templates**:
- `harvest.yml.j2` - конфигурация с pollers

**Теги**: `setup`, `config`, `systemd`, `service`

**Переменные**:
- `netapp_api_addr`
- `harvest_netapp_port`
- `harvest_unix_port`

**Важно**: NetApp credentials должны быть в environment или `/dev/shm`

---

## Handlers

Все роли используют handlers для graceful перезагрузки сервисов.

### Когда вызываются handlers

Handlers вызываются автоматически при изменении конфигурационных файлов:

```yaml
- name: "Копирование конфигурации"
  template:
    src: config.j2
    dest: /path/to/config
  notify: restart service  # Handler будет вызван в конце play
```

### Типы handlers

1. **reload systemd user** - перезагрузка systemd daemon (для новых unit файлов)
2. **reload prometheus** - перезагрузка конфигурации без перезапуска
3. **restart <service>** - полный перезапуск сервиса

## Переменные

Все переменные определены в `group_vars/monitoring.yml`.

### Обязательные для изменения

- `vault_namespace` - ваш Vault namespace
- `netapp_api_addr` - адрес NetApp кластера
- `admin_email` - email администратора

### Опциональные

- Порты сервисов
- Интервалы scraping
- Retention policies
- TLS настройки

## Теги

Используйте теги для выборочного выполнения:

```bash
# Только установка
ansible-playbook playbook.yml --tags "setup"

# Только конфигурация
ansible-playbook playbook.yml --tags "config"

# Только Prometheus
ansible-playbook playbook.yml --tags "prometheus"

# Несколько тегов
ansible-playbook playbook.yml --tags "config,service"
```

## Примеры использования

### Полное развертывание

```bash
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml
```

### Обновление только конфигураций

```bash
ansible-playbook -i inventories/production playbooks/update_config.yml
```

### Проверка здоровья

```bash
ansible-playbook -i inventories/production playbooks/health_check.yml
```

### Откат изменений

```bash
ansible-playbook -i inventories/production playbooks/rollback.yml
```

## Безопасность

### Секреты

Все секреты передаются через:
1. Vault Agent (автоматически)
2. Environment переменные
3. `/dev/shm` (tmpfs в RAM)

**Никогда не храните секреты в:**
- Inventory файлах
- Group vars
- Host vars
- Templates (используйте переменные)

### Права доступа

Роли соблюдают принцип наименьших привилегий:
- Сервисы запускаются от `monitoring_svc`
- Конфигурации принадлежат `monitoring_ci`
- Логи доступны `monitoring_admin`

### User Systemd

Все сервисы работают через user systemd units:
- Без root прав
- Изоляция процессов
- Ограничение capabilities
- Security hardening

## Troubleshooting

### Роль не применяется

```bash
# Проверить синтаксис
ansible-playbook playbook.yml --syntax-check

# Dry-run
ansible-playbook playbook.yml --check

# Verbose
ansible-playbook playbook.yml -vvv
```

### Handler не срабатывает

Handlers вызываются только если task изменил состояние (`changed: true`).

Проверьте:
- Файл действительно изменился?
- Handler правильно указан в `notify:`?
- Play завершился успешно?

### Сервис не запускается

```bash
# На целевом сервере
sudo -u monitoring_svc systemctl --user status prometheus
journalctl --user -u prometheus -n 50
```

## Лучшие практики

1. **Идемпотентность** - роли можно запускать многократно
2. **Модульность** - каждая роль независима
3. **Теги** - для гибкого управления
4. **Handlers** - для graceful перезагрузок
5. **Проверки** - validate в templates где возможно
6. **Безопасность** - никаких секретов в коде

---

**Версия**: 1.0  
**Дата**: 2025  
**Статус**: Production Ready ✅




