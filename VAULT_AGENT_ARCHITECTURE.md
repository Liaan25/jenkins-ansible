# Архитектура развертывания Vault Agent и Monitoring Stack

## 📋 Обзор

Система мониторинга использует **два независимых набора пользователей**:
1. **Vault Agent** — для управления сертификатами (создается через RLM)
2. **Monitoring Stack** — для работы приложений мониторинга (создается через IDM)

---

## 👥 Архитектура пользователей

### 1. Vault Agent (System Service)

| Параметр | Значение | Кто создает |
|----------|----------|-------------|
| **User** | `{{ kae_stend }}-lnx-va-start` | RLM сценарий `vault_agent_config` |
| **Group** | `{{ kae_stend }}-lnx-va-read` | RLM сценарий `vault_agent_config` |
| **Systemd** | System service (`/etc/systemd/system/`) | RLM |
| **Назначение** | Получение сертификатов из Vault SecMan | — |
| **Пример** | `CI10742292-lnx-va-start` | — |

### 2. Monitoring Stack (User Services)

| Роль | User | Group | Кто создает |
|------|------|-------|-------------|
| **СУЗ (Service)** | `{{ kae_stend }}-lnx-mon_sys` | `{{ kae_stend }}-lnx-mon_sys` | IDM (заранее) |
| **ТУЗ (CI/CD)** | `{{ kae_stend }}-lnx-mon_ci` | `{{ kae_stend }}-lnx-mon_sys` | IDM (заранее) |
| **ПУЗ (Admin)** | `{{ kae_stend }}-lnx-mon_admin` | `{{ kae_stend }}-lnx-mon_sys` | IDM (заранее) |
| **ReadOnly** | `{{ kae_stend }}-lnx-mon_ro` | `{{ kae_stend }}-lnx-mon_sys` | IDM (заранее) |

**Примеры:**
- СУЗ: `CI10742292-lnx-mon_sys`
- ТУЗ: `CI10742292-lnx-mon_ci`
- Группа: `CI10742292-lnx-mon_sys` (единая для всех)

**Systemd:**
- User services (`~/.config/systemd/user/`)
- Запускаются от `{{ kae_stend }}-lnx-mon_sys`

---

## 🔄 Последовательность развертывания

### ЭТАП 1: Подготовка окружения (Common Role)

**Что делается:**
- Проверка наличия пользователей Monitoring Stack в IDM
- Создание структуры директорий `/opt/monitoring/`
- Копирование utility скриптов
- Копирование wrapper скриптов с SHA256 защитой

**От какого пользователя:** `root` (через `become: yes`)

**Важно:**
- Пользователи Monitoring Stack (`*-lnx-mon_*`) должны быть **созданы заранее через IDM**
- Если пользователей нет → playbook упадет с ошибкой

---

### ЭТАП 1.5: Установка ПО через RLM API

**Что делается:**

#### 1.5.1. Установка Vault Agent

**RLM сценарий:** `vault_agent_config`

**Параметры:**
```yaml
params:
  v_url: "HTTPS://VAULT.SIGMA.SBRF.RU"  # Обязательно UPPERCASE!
  tenant: "{{ vault_namespace }}"
  serv_user: "{{ kae_stend }}-lnx-va-start"  # Создастся автоматически
  serv_group: "{{ kae_stend }}-lnx-va-read"  # Создастся автоматически
  read_user: "{{ kae_stend }}-lnx-va-start"
  approle: "approle/vault-agent"
  start_after_configuration: false  # Не запускать сразу
```

**Что делает RLM:**
1. Создает пользователя `{{ kae_stend }}-lnx-va-start` через IDM
2. Создает группу `{{ kae_stend }}-lnx-va-read` через IDM
3. Устанавливает Vault Agent binary
4. Создает systemd service `/etc/systemd/system/vault-agent.service`
5. Настраивает конфигурацию в `/opt/vault/conf/`

**Результат:**
- ✅ Vault Agent установлен и настроен
- ✅ Пользователи для Vault Agent созданы
- ⏸️ Service НЕ запущен (параметр `start_after_configuration: false`)

#### 1.5.2. Установка RPM пакетов

**RLM сценарий:** `LINUX_RPM_INSTALLER`

**Пакеты:**
- Prometheus → `/usr/bin/prometheus`
- Grafana → `/usr/sbin/grafana-server`
- Harvest → `/usr/bin/harvest`

**От какого пользователя:** `connection: local` (выполняется на Jenkins)

---

### ЭТАП 2: Проверка Vault Agent и получение секретов

**Что делается:**
1. Проверка что Vault Agent service установлен
2. Проверка статуса Vault Agent
3. Ожидание получения сертификатов от Vault
4. Проверка наличия сертификатов в `/opt/vault/certs/`

**От какого пользователя:** `root` (через `become: yes`)

**Важно:**
- Vault Agent УЖЕ установлен через RLM (ЭТАП 1.5)
- Мы НЕ создаем конфигурацию (это сделал RLM)
- Мы НЕ запускаем service (это сделал RLM)
- Мы только **проверяем** и **ожидаем** сертификаты

**Проверяемые файлы:**
- `/opt/vault/certs/server_bundle.pem`
- `/opt/vault/certs/ca_chain.crt`

---

### ЭТАП 3: Установка и настройка Prometheus

**Что делается:**
1. Копирование конфигурации `prometheus.yml`
2. Копирование TLS конфигурации `web-config.yml`
3. Копирование systemd unit в `~/.config/systemd/user/`
4. Перезагрузка systemd daemon (User mode)
5. Запуск Prometheus service

**От какого пользователя:**
- Конфигурация: `root` (владелец файлов: `{{ monitoring_ci_user }}`)
- Systemd: `{{ monitoring_service_user }}` (User Systemd)

**Systemd:**
```ini
[Unit]
Description=Prometheus Monitoring Server
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/prometheus \
  --config.file=/opt/monitoring/config/prometheus.yml \
  --storage.tsdb.path=/opt/monitoring/data/prometheus \
  --web.config.file=/opt/monitoring/config/web-config.yml
Restart=always
User={{ monitoring_service_user }}
Group={{ monitoring_group }}

[Install]
WantedBy=default.target
```

---

### ЭТАП 4: Установка и настройка Grafana

**Аналогично Prometheus:**
- User Systemd service
- Запускается от `{{ monitoring_service_user }}`
- Конфигурация в `/opt/monitoring/config/grafana.ini`

---

### ЭТАП 5: Установка и настройка Harvest

**Аналогично Prometheus и Grafana:**
- User Systemd service
- Запускается от `{{ monitoring_service_user }}`
- Конфигурация в `/opt/monitoring/config/harvest.yml`

---

## 🔐 Матрица доступа

### Файловая система

| Путь | Owner | Group | Права |
|------|-------|-------|-------|
| `/opt/monitoring/` | `root` | `{{ kae_stend }}-lnx-mon_sys` | `0755` |
| `/opt/monitoring/config/` | `{{ kae_stend }}-lnx-mon_ci` | `{{ kae_stend }}-lnx-mon_sys` | `0750` |
| `/opt/monitoring/data/` | `{{ kae_stend }}-lnx-mon_sys` | `{{ kae_stend }}-lnx-mon_sys` | `0770` |
| `/opt/monitoring/logs/` | `{{ kae_stend }}-lnx-mon_sys` | `{{ kae_stend }}-lnx-mon_sys` | `0770` |
| `/opt/vault/certs/` | `{{ kae_stend }}-lnx-va-start` | `{{ kae_stend }}-lnx-va-read` | `0750` |
| `/dev/shm/monitoring_secrets/` | `{{ kae_stend }}-lnx-mon_sys` | `{{ kae_stend }}-lnx-mon_sys` | `0700` |

### Systemd Services

| Service | Type | User | Где находится |
|---------|------|------|---------------|
| `vault-agent.service` | System | `{{ kae_stend }}-lnx-va-start` | `/etc/systemd/system/` |
| `prometheus.service` | User | `{{ kae_stend }}-lnx-mon_sys` | `~/.config/systemd/user/` |
| `grafana.service` | User | `{{ kae_stend }}-lnx-mon_sys` | `~/.config/systemd/user/` |
| `harvest.service` | User | `{{ kae_stend }}-lnx-mon_sys` | `~/.config/systemd/user/` |

---

## 📝 Переменные в Ansible

### group_vars/all.yml

```yaml
# KAE_STEND - передается из Jenkins через dynamic_inventory
kae_stend: "CI10742292"  # Пример, реальное значение из Jenkins

# Vault Agent пользователи (создаются RLM)
vault_agent_user: "{{ kae_stend }}-lnx-va-start"
vault_agent_group: "{{ kae_stend }}-lnx-va-read"

# Monitoring пользователи (создаются IDM заранее)
monitoring_service_user: "{{ user_sys }}"  # CI10742292-lnx-mon_sys
monitoring_ci_user: "{{ user_ci }}"        # CI10742292-lnx-mon_ci
monitoring_admin_user: "{{ user_admin }}"  # CI10742292-lnx-mon_admin
monitoring_ro_user: "{{ user_ro }}"        # CI10742292-lnx-mon_ro

# Единая группа для всех monitoring пользователей
monitoring_group: "{{ user_sys }}"  # CI10742292-lnx-mon_sys
```

---

## 🚨 Критические моменты

### 1. Vault Agent ≠ Monitoring User

❌ **НЕ ПРАВИЛЬНО:**
```yaml
# Vault Agent запускается от monitoring_service_user
become_user: "{{ monitoring_service_user }}"
```

✅ **ПРАВИЛЬНО:**
```yaml
# Vault Agent устанавливается через RLM и запускается от vault_agent_user
# Мы только ПРОВЕРЯЕМ его статус, НЕ запускаем
- name: "Проверка Vault Agent"
  systemd:
    name: vault-agent
    state: started
  check_mode: yes
```

### 2. System vs User Systemd

| Service | Тип | Почему |
|---------|-----|--------|
| Vault Agent | System | Нужен для получения сертификатов **ДО** логина пользователя |
| Prometheus/Grafana/Harvest | User | Запускаются от непривилегированного пользователя, не требуют root |

### 3. RLM должен создать пользователей для Vault

Если пользователь `{{ kae_stend }}-lnx-va-start` не существует после RLM:
- ❌ Vault Agent не сможет запуститься
- ✅ Проверить параметры RLM API call
- ✅ Проверить что IDM одобрил создание пользователя

### 4. Monitoring пользователи должны быть созданы ЗАРАНЕЕ

Перед запуском Jenkins pipeline:
1. ✅ Создать заявку в IDM на создание пользователей:
   - `{{ kae_stend }}-lnx-mon_sys` (СУЗ)
   - `{{ kae_stend }}-lnx-mon_ci` (ТУЗ)
   - `{{ kae_stend }}-lnx-mon_admin` (ПУЗ)
   - `{{ kae_stend }}-lnx-mon_ro` (ReadOnly)
2. ✅ Дождаться одобрения и создания
3. ✅ Проверить что пользователи существуют: `getent passwd {{ kae_stend }}-lnx-mon_sys`

---

## 🔍 Диагностика

### Проверка Vault Agent

```bash
# Статус service
sudo systemctl status vault-agent

# Логи
sudo journalctl -u vault-agent -f

# Проверка пользователя
getent passwd CI10742292-lnx-va-start

# Проверка сертификатов
ls -lh /opt/vault/certs/
```

### Проверка Monitoring Services

```bash
# Переключиться на monitoring_service_user
sudo -i -u CI10742292-lnx-mon_sys

# Статус User services
systemctl --user status prometheus
systemctl --user status grafana
systemctl --user status harvest

# Логи
journalctl --user -u prometheus -f
```

---

## ✅ Соответствие CORPORATE_SECURITY_RULES.md

| Правило | Как соблюдается |
|---------|----------------|
| **Установка ПО только через ДИ/RLM** | ✅ Vault Agent и RPM пакеты устанавливаются через RLM API |
| **Пользователи создаются через IDM** | ✅ RLM сценарий создает Vault Agent users через IDM<br>✅ Monitoring users создаются вручную через IDM заранее |
| **Динамические имена пользователей** | ✅ `{{ kae_stend }}-lnx-va-start`, `{{ kae_stend }}-lnx-mon_sys` |
| **Разделение полномочий** | ✅ Vault Agent = отдельный user<br>✅ Monitoring = отдельные users (СУЗ/ТУЗ/ПУЗ/RO) |
| **Секреты в tmpfs** | ✅ `/dev/shm/monitoring_secrets/` (owner: СУЗ, mode: 0700) |
| **Wrapper скрипты с SHA256** | ✅ Все wrapper скрипты защищены SHA256 в sudoers |
| **Единая группа** | ✅ Все monitoring пользователи в группе `{{ kae_stend }}-lnx-mon_sys` |

---

## 📚 Связанные документы

- `CORPORATE_SECURITY_RULES.md` — правила корпоративной безопасности
- `DYNAMIC_GROUP_SUMMARY.md` — архитектура единой группы
- `SUDOERS_FOR_MVP_DEV.md` — sudoers правила для развертывания
- `deploy_monitoring.sh` — оригинальный скрипт (референс)
- `Jenkinsfile` — Jenkins Pipeline для развертывания
- `ansible/playbooks/deploy_monitoring.yml` — Ansible playbook

---

**Дата создания:** 2025-11-24  
**Версия:** 1.0  
**Статус:** Активный


