# Руководство по развертыванию системы мониторинга

## Оглавление

1. [Введение](#введение)
2. [Архитектура решения](#архитектура-решения)
3. [Предварительные требования](#предварительные-требования)
4. [Подготовка инфраструктуры](#подготовка-инфраструктуры)
5. [Создание учетных записей](#создание-учетных-записей)
6. [Настройка файловой системы](#настройка-файловой-системы)
7. [Настройка прав sudo](#настройка-прав-sudo)
8. [Установка через Jenkins](#установка-через-jenkins)
9. [Установка через Ansible](#установка-через-ansible)
10. [Ручная установка](#ручная-установка)
11. [Проверка установки](#проверка-установки)
12. [Обслуживание](#обслуживание)
13. [Устранение неполадок](#устранение-неполадок)

---

## Введение

Данное руководство описывает процесс безопасного развертывания системы мониторинга в корпоративной среде Enterprise с соблюдением всех требований безопасности банка.

### Компоненты системы

- **Prometheus** - система мониторинга и базы данных временных рядов
- **Grafana** - платформа визуализации и аналитики
- **Harvest** - коллектор метрик для NetApp
- **Vault Agent** - управление секретами и сертификатами

### Ключевые принципы

- Минимальные привилегии для всех компонентов
- Разделение полномочий между типами УЗ
- Секреты только в tmpfs (/dev/shm)
- User systemd units вместо system units
- Автоматизация через Ansible
- Непривилегированные файловые системы

---

## Архитектура решения

### Схема компонентов

```
┌─────────────────────────────────────────────────────────────┐
│                     Jenkins (CI/CD)                         │
│  - Получение секретов из Vault                              │
│  - Запуск Ansible playbooks                                 │
│  - Мониторинг развертывания                                 │
└────────────────────────┬────────────────────────────────────┘
                         │ SSH
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Целевой сервер (Production)                     │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │  Учетные записи (IDM)                        │           │
│  │  - monitoring_svc (NoLogin) - запуск сервисов│           │
│  │  - monitoring_ci - деплой через Jenkins/Ansible          │
│  │  - monitoring_admin - управление              │           │
│  │  - monitoring_ro - чтение логов               │           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │  Vault Agent (systemd user service)          │           │
│  │  - AppRole аутентификация                    │           │
│  │  - Получение сертификатов                    │           │
│  │  - Размещение секретов в /dev/shm            │           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │  /opt/monitoring/  (ФС через RLM)            │           │
│  │  ├── bin/     (бинарники)                    │           │
│  │  ├── config/  (конфигурация)                 │           │
│  │  ├── data/    (данные Prometheus)            │           │
│  │  └── logs/    (логи приложений)              │           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │  /dev/shm/monitoring_secrets/  (tmpfs)       │           │
│  │  - Сертификаты (server.crt, server.key)     │           │
│  │  - Пароли API                                 │           │
│  │  - Токены доступа                             │           │
│  │  Права: 700, владелец: monitoring_svc        │           │
│  └──────────────────────────────────────────────┘           │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │  User Systemd Services (~/.config/systemd/user/)         │
│  │  - prometheus.service                         │           │
│  │  - grafana.service                            │           │
│  │  - harvest.service                            │           │
│  │  - vault-agent-monitoring.service            │           │
│  └──────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

### Потоки данных

1. **Jenkins → Vault** - получение секретов через AppRole
2. **Jenkins → Target Server** - передача секретов через SSH в /dev/shm
3. **Vault Agent → Vault** - получение сертификатов и секретов
4. **Vault Agent → /dev/shm** - размещение секретов в tmpfs
5. **Services → /dev/shm** - чтение секретов из tmpfs
6. **Prometheus → Harvest** - сбор метрик по mTLS
7. **Grafana → Prometheus** - запросы данных по mTLS

---

## Предварительные требования

### Доступы и учетные данные

- [ ] Доступ к порталу ДИ (Data Infrastructure)
- [ ] Доступ к IDM для создания учетных записей
- [ ] Доступ к RLM (Resource Lifecycle Management)
- [ ] Доступ к Vault (SecMan)
- [ ] Доступ к Jenkins
- [ ] SSH-ключ для доступа к целевому серверу

### Необходимые параметры

#### Vault (SecMan)
- `SEC_MAN_ADDR` - адрес Vault сервера (например, `vault.sigma.sbrf.ru`)
- `NAMESPACE_CI` - namespace в Vault (например, `KPRJ_000000`)
- `VAULT_AGENT_KV` - путь к KV с role_id/secret_id (например, `secret/data/monitoring/vault-agent`)

#### RLM
- `RLM_API_URL` - URL RLM API (например, `https://rlm.sigma.sbrf.ru`)
- `RLM_TOKEN` - токен доступа к RLM API

#### Целевой сервер
- `SERVER_ADDRESS` - IP или FQDN сервера
- `SSH_CREDENTIALS_ID` - ID SSH credentials в Jenkins

#### Сеть и сервисы
- `PROMETHEUS_PORT` - порт Prometheus (по умолчанию 9090)
- `GRAFANA_PORT` - порт Grafana (по умолчанию 3000)
- `NETAPP_API_ADDR` - FQDN/IP NetApp кластера

#### RPM пакеты (через ДИ)
- URL для RPM Prometheus
- URL для RPM Grafana
- URL для RPM Harvest

### Системные требования

#### Целевой сервер
- ОС: Fedora/RHEL 7+
- RAM: минимум 8GB
- Диск: минимум 7GB для `/opt/monitoring`
- CPU: минимум 2 cores

#### Сетевые порты
Открытые порты на целевом сервере:
- `9090` - Prometheus (HTTPS, ограничен localhost + IP сервера)
- `3000` - Grafana (HTTPS, публичный)
- `12990` - Harvest NetApp (HTTPS, публичный)
- `12991` - Harvest Unix (HTTP, localhost only)

---

## Подготовка инфраструктуры

### Шаг 1: Получение сервера через ДИ

1. Зайти на портал ДИ: https://di.sigma.sbrf.ru
2. Заказать виртуальную машину:
   - ОС: Fedora/RHEL
   - RAM: 8GB+
   - CPU: 2+ cores
   - Диск: системный (по умолчанию)

3. **ВАЖНО**: На этапе заказа НЕ заказывать дополнительные диски с точками монтирования
   - Мы получим пустой диск через ДИ
   - Точки монтирования создадим через RLM с нужными правами

### Шаг 2: Заказ дополнительного диска

1. В ДИ найти созданный сервер
2. Добавить новый диск:
   - Размер: **7GB** (минимум)
   - **Точку монтирования НЕ указывать** (оставить пустым)
   - Это позволит нам настроить права через RLM

### Шаг 3: Проверка доступа к серверу

```bash
# Проверка SSH доступа
ssh <ваш_пользователь>@<SERVER_ADDRESS>

# Проверка passwordless sudo (NOPASSWD)
sudo -n true

# Если команда выше не работает, необходимо запросить NOPASSWD через IDM
```

---

## Создание учетных записей

Подробная инструкция: [IDM_ACCOUNTS_GUIDE.md](IDM_ACCOUNTS_GUIDE.md)

### Необходимые УЗ

Создать 4 учетные записи через АС СУУПТ (IDM):

#### 1. СУЗ (Сервисная учетная запись)
```
Имя: monitoring_svc
Тип: NoLogin (без интерактивного входа)
Назначение: Запуск сервисов (Prometheus, Grafana, Harvest)
Группа: monitoring
```

#### 2. ПУЗ (Привилегированная учетная запись)
```
Имя: monitoring_admin
Тип: Интерактивная
Назначение: Администрирование, просмотр логов, управление сервисами
Группа: monitoring
Дополнительные группы: monitoring_svc
```

#### 3. ТУЗ (Техническая учетная запись)
```
Имя: monitoring_ci
Тип: Интерактивная
Назначение: Деплой через Jenkins/Ansible, обновление бинарников
Группа: monitoring
Дополнительные группы: monitoring_svc
```

#### 4. ReadOnly УЗ
```
Имя: monitoring_ro
Тип: Интерактивная
Назначение: Только чтение конфигов и логов
Группа: monitoring_ro
```

### Настройка прав между УЗ

После создания УЗ необходимо запросить в IDM права:

#### Для monitoring_admin
```
monitoring_admin ALL=(monitoring_svc) NOPASSWD: ALL
```
Позволяет запускать команды от имени monitoring_svc

#### Для monitoring_ci
```
monitoring_ci ALL=(monitoring_svc) NOPASSWD: ALL
```
Позволяет управлять файлами и сервисами

---

## Настройка файловой системы

### Создание ФС через RLM

1. **Зайти в RLM**: https://rlm.sigma.sbrf.ru/dashboard/directions/RLM_UVS

2. **Найти сервер** по IP или имени

3. **Запустить сценарий**: "Добавление/расширение файловых систем"

4. **Создать файловые системы**:

```
Точка монтирования: /opt/monitoring
Размер: 1GB
Владелец: monitoring_ci
Группа: monitoring
Права: 755

Точка монтирования: /opt/monitoring/data
Размер: 4GB
Владелец: monitoring_svc
Группа: monitoring
Права: 770

Точка монтирования: /opt/monitoring/logs
Размер: 2GB
Владелец: monitoring_svc
Группа: monitoring_admin
Права: 770
```

**Итого: 7GB**

### Создание структуры каталогов

После создания ФС через RLM, от пользователя `monitoring_ci`:

```bash
# Войти под monitoring_ci
sudo -u monitoring_ci -i

# Создать структуру
mkdir -p /opt/monitoring/bin
mkdir -p /opt/monitoring/config
mkdir -p /opt/monitoring/scripts

# Установить права
chmod 750 /opt/monitoring/bin
chmod 750 /opt/monitoring/config
chmod 755 /opt/monitoring/scripts

# data/ и logs/ уже созданы через RLM с нужными правами
```

### Проверка ФС

```bash
# От любого пользователя
df -h | grep monitoring

# Должно показать:
# /dev/mapper/... 1.0G ... /opt/monitoring
# /dev/mapper/... 4.0G ... /opt/monitoring/data
# /dev/mapper/... 2.0G ... /opt/monitoring/logs

# Проверка прав
ls -la /opt/monitoring

# Должно показать:
# drwxr-xr-x monitoring_ci monitoring bin/
# drwxr-xr-x monitoring_ci monitoring config/
# drwxrwx--- monitoring_svc monitoring data/
# drwxrwx--- monitoring_svc monitoring_admin logs/
```

---

## Настройка прав sudo

Подробная инструкция: [SUDOERS_GUIDE.md](SUDOERS_GUIDE.md)

### Запрос прав через IDM

1. Зайти в IDM: https://idm.sigma.sbrf.ru
2. Перейти в раздел "Права на серверах Linux"
3. Создать заявку на предоставление прав sudo
4. Приложить файл `sudoers/monitoring_system` (из этого проекта)
5. Указать целевой сервер и пользователей

### Минимальный набор прав

Для работы системы необходимы следующие sudo права:

```bash
# Для monitoring_ci (деплой)
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user daemon-reload
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable prometheus
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable grafana
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable harvest
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start prometheus
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start grafana
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start harvest
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user stop prometheus
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user stop grafana
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user stop harvest
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user restart prometheus
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user restart grafana
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user restart harvest

# Для monitoring_admin (управление)
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status prometheus
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status grafana
ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status harvest
```

**ВАЖНО**: Полный файл sudoers с экранированием находится в `sudoers/monitoring_system`

---

## Установка через Jenkins

### Предварительная настройка Jenkins

1. **Создать credentials**:
   - SSH key для доступа к серверу (`SSH_CREDENTIALS_ID`)
   - RLM token (`rlm-token`)
   - Vault credentials для доступа к SecMan (`vault-agent-dev`)

2. **Создать Jenkins Pipeline**:
   - New Item → Pipeline
   - Указать репозиторий с `Jenkinsfile`
   - Настроить параметры (см. ниже)

### Параметры Jenkins Pipeline

```groovy
SERVER_ADDRESS        # IP/FQDN целевого сервера
SSH_CREDENTIALS_ID    # ID SSH credentials
SEC_MAN_ADDR          # Адрес Vault
NAMESPACE_CI          # Namespace в Vault
NETAPP_API_ADDR       # FQDN NetApp кластера
HARVEST_RPM_URL       # URL RPM Harvest
PROMETHEUS_RPM_URL    # URL RPM Prometheus
GRAFANA_RPM_URL       # URL RPM Grafana
VAULT_AGENT_KV        # Путь к AppRole в Vault
RPM_URL_KV            # Путь к URL RPM в Vault
TUZ_KV                # Путь к ТУЗ credentials
NETAPP_SSH_KV         # Путь к NetApp SSH
MON_SSH_KV            # Путь к Mon SSH
NETAPP_API_KV         # Путь к NetApp API
GRAFANA_WEB_KV        # Путь к Grafana Web
SBERCA_CERT_KV        # Путь к сертификатам
ADMIN_EMAIL           # Email администратора
GRAFANA_PORT          # Порт Grafana (3000)
PROMETHEUS_PORT       # Порт Prometheus (9090)
RLM_API_URL           # URL RLM API
```

### Запуск развертывания

1. Открыть Jenkins job
2. Нажать "Build with Parameters"
3. Заполнить все параметры
4. Нажать "Build"

### Мониторинг процесса

Jenkins Pipeline состоит из следующих стадий:

1. **Проверка параметров** - валидация входных данных
2. **Получение данных из Vault** - извлечение секретов
3. **Копирование скрипта на сервер** - передача файлов
4. **Выполнение развертывания** - запуск основного скрипта
5. **Проверка результатов** - верификация установки
6. **Очистка** - удаление временных файлов
7. **Получение сведений** - информация о доступе

### Ожидаемый результат

После успешного выполнения:

```
✅ Pipeline успешно завершен!
================================================
Доступ к сервисам:
 • Prometheus: https://<SERVER_IP>:9090
 • Prometheus: https://<DOMAIN>:9090
 • Grafana: https://<SERVER_IP>:3000
 • Grafana: https://<DOMAIN>:3000
================================================
```

---

## Установка через Ansible

### Предварительная настройка Ansible

1. **Установить Ansible** (на машине управления):
```bash
pip install ansible
```

2. **Настроить inventory**:
```bash
cd ansible/inventories
cp production.example production
# Отредактировать production - указать IP/FQDN серверов
```

3. **Настроить переменные**:
```bash
cd ansible/group_vars
cp monitoring.yml.example monitoring.yml
# Отредактировать monitoring.yml - указать параметры
```

### Структура Ansible проекта

```
ansible/
├── ansible.cfg              # Конфигурация Ansible
├── inventories/
│   └── production           # Инвентори продакшена
├── group_vars/
│   └── monitoring.yml       # Переменные для группы
├── playbooks/
│   ├── deploy_monitoring.yml      # Полное развертывание
│   ├── setup_filesystem.yml       # Настройка ФС
│   ├── setup_vault_agent.yml      # Настройка Vault Agent
│   ├── install_packages.yml       # Установка RPM
│   └── configure_services.yml     # Настройка сервисов
└── roles/
    ├── common/              # Общие задачи
    ├── vault_agent/         # Роль Vault Agent
    ├── prometheus/          # Роль Prometheus
    ├── grafana/             # Роль Grafana
    └── harvest/             # Роль Harvest
```

### Запуск развертывания

#### Полное развертывание
```bash
cd ansible
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml
```

#### Поэтапное развертывание

1. **Настройка файловой системы**:
```bash
ansible-playbook -i inventories/production playbooks/setup_filesystem.yml
```

2. **Настройка Vault Agent**:
```bash
ansible-playbook -i inventories/production playbooks/setup_vault_agent.yml
```

3. **Установка пакетов**:
```bash
ansible-playbook -i inventories/production playbooks/install_packages.yml
```

4. **Настройка сервисов**:
```bash
ansible-playbook -i inventories/production playbooks/configure_services.yml
```

### Проверка синтаксиса

```bash
# Проверка синтаксиса playbook
ansible-playbook --syntax-check playbooks/deploy_monitoring.yml

# Dry-run (без изменений)
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml --check

# Просмотр задач
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml --list-tasks
```

---

## Ручная установка

Если Jenkins и Ansible недоступны, можно выполнить установку вручную.

### Шаг 1: Подготовка

```bash
# Войти на сервер под пользователем monitoring_ci
ssh monitoring_ci@<SERVER_ADDRESS>

# Создать рабочую директорию
mkdir -p ~/deployment
cd ~/deployment

# Скопировать скрипты из репозитория
# (предполагается, что репозиторий уже склонирован)
```

### Шаг 2: Настройка переменных окружения

```bash
# Создать файл с переменными
cat > deployment.env << 'EOF'
export SEC_MAN_ADDR="vault.sigma.sbrf.ru"
export NAMESPACE_CI="KPRJ_000000"
export RLM_API_URL="https://rlm.sigma.sbrf.ru"
export RLM_TOKEN="<ВАШ_ТОКЕН>"
export NETAPP_API_ADDR="cl01-mgmt.example.org"
export GRAFANA_PORT="3000"
export PROMETHEUS_PORT="9090"
export VAULT_AGENT_KV="secret/data/monitoring/vault-agent"
export RPM_URL_KV="secret/data/monitoring/rpm-urls"
export TUZ_KV="secret/data/monitoring/tuz"
export NETAPP_SSH_KV="secret/data/monitoring/netapp-ssh"
export MON_SSH_KV="secret/data/monitoring/mon-ssh"
export NETAPP_API_KV="secret/data/monitoring/netapp-api"
export GRAFANA_WEB_KV="secret/data/monitoring/grafana-web"
export SBERCA_CERT_KV="secret/data/monitoring/sberca-cert"
export ADMIN_EMAIL="admin@example.org"
EOF

# Загрузить переменные
source deployment.env
```

### Шаг 3: Установка Vault Agent

```bash
# Запустить скрипт установки Vault Agent
sudo bash scripts/setup_vault_agent.sh
```

### Шаг 4: Получение секретов из Vault

```bash
# Создать директорию для секретов в tmpfs
sudo -u monitoring_svc mkdir -p /dev/shm/monitoring_secrets
sudo -u monitoring_svc chmod 700 /dev/shm/monitoring_secrets

# Запустить Vault Agent для получения секретов
sudo -u monitoring_svc systemctl --user start vault-agent-monitoring

# Проверить, что секреты получены
sudo -u monitoring_svc ls -la /dev/shm/monitoring_secrets/
```

### Шаг 5: Установка RPM пакетов через RLM

```bash
# Запустить скрипт установки пакетов
sudo bash scripts/install_packages_via_rlm.sh
```

### Шаг 6: Настройка конфигураций

```bash
# Скопировать конфигурационные файлы
sudo -u monitoring_ci cp config/prometheus.yml /opt/monitoring/config/
sudo -u monitoring_ci cp config/grafana.ini /opt/monitoring/config/
sudo -u monitoring_ci cp config/harvest.yml /opt/monitoring/config/

# Обновить пути к секретам в конфигах
sudo -u monitoring_ci bash scripts/update_configs.sh
```

### Шаг 7: Создание systemd units

```bash
# Создать директорию для user units
mkdir -p ~/.config/systemd/user/

# Скопировать unit файлы
cp systemd/prometheus.service ~/.config/systemd/user/
cp systemd/grafana.service ~/.config/systemd/user/
cp systemd/harvest.service ~/.config/systemd/user/

# Перезагрузить systemd
systemctl --user daemon-reload
```

### Шаг 8: Запуск сервисов

```bash
# Включить автозапуск
systemctl --user enable prometheus
systemctl --user enable grafana
systemctl --user enable harvest

# Запустить сервисы
systemctl --user start prometheus
systemctl --user start grafana
systemctl --user start harvest

# Проверить статус
systemctl --user status prometheus
systemctl --user status grafana
systemctl --user status harvest
```

### Шаг 9: Настройка iptables

```bash
# Открыть необходимые порты
sudo bash scripts/configure_firewall.sh
```

### Шаг 10: Импорт дашбордов Grafana

```bash
# Дождаться запуска Grafana (30 сек)
sleep 30

# Импортировать дашборды
bash scripts/import_grafana_dashboards.sh
```

---

## Проверка установки

### Проверка сервисов

```bash
# От пользователя monitoring_admin
systemctl --user status prometheus
systemctl --user status grafana
systemctl --user status harvest

# Должны быть: active (running)
```

### Проверка портов

```bash
# Проверка открытых портов
ss -tlnp | grep -E ":(9090|3000|12990|12991)"

# Должны быть открыты:
# :9090  - Prometheus
# :3000  - Grafana
# :12990 - Harvest NetApp
# :12991 - Harvest Unix
```

### Проверка доступности веб-интерфейсов

```bash
# Prometheus
curl -k https://localhost:9090/-/healthy
# Ожидается: Prometheus is Healthy.

# Grafana
curl -k https://localhost:3000/api/health
# Ожидается: {"database":"ok",...}

# Harvest
curl http://localhost:12991/metrics | head
# Ожидается: метрики в формате Prometheus
```

### Проверка секретов

```bash
# От пользователя monitoring_svc
sudo -u monitoring_svc ls -la /dev/shm/monitoring_secrets/

# Должны присутствовать:
# server.crt
# server.key
# ca_chain.crt
# (и другие секреты)

# Права: 600 или 640
# Владелец: monitoring_svc
```

### Проверка логов

```bash
# Логи Prometheus
tail -f /opt/monitoring/logs/prometheus/prometheus.log

# Логи Grafana
tail -f /opt/monitoring/logs/grafana/grafana.log

# Логи Harvest
tail -f /opt/monitoring/logs/harvest/harvest.log

# Не должно быть ошибок подключения или аутентификации
```

### Проверка mTLS

```bash
# Проверка что Prometheus требует client cert
curl -k https://localhost:9090/metrics
# Ожидается ошибка: certificate required

# Проверка с client cert
curl -k --cert /dev/shm/monitoring_secrets/client.crt \
     --key /dev/shm/monitoring_secrets/client.key \
     https://localhost:9090/metrics
# Ожидается: метрики Prometheus
```

### Скрипт автоматической проверки

```bash
# Запустить скрипт проверки
bash scripts/verify_security.sh

# Скрипт проверит:
# - Права на файлы и директории
# - Статус сервисов
# - Доступность портов
# - Наличие секретов в /dev/shm
# - Корректность конфигураций
# - Соответствие требованиям безопасности
```

---

## Обслуживание

### Просмотр логов

```bash
# От пользователя monitoring_admin или monitoring_ro

# Все логи
tail -f /opt/monitoring/logs/*/*.log

# Только Prometheus
journalctl --user -u prometheus -f

# Только Grafana
journalctl --user -u grafana -f

# Только Harvest
journalctl --user -u harvest -f
```

### Перезапуск сервисов

```bash
# От пользователя monitoring_admin

# Перезапуск Prometheus
systemctl --user restart prometheus

# Перезапуск Grafana
systemctl --user restart grafana

# Перезапуск Harvest
systemctl --user restart harvest

# Перезапуск всех
systemctl --user restart prometheus grafana harvest
```

### Обновление конфигурации

```bash
# От пользователя monitoring_ci

# 1. Обновить конфигурационные файлы
vim /opt/monitoring/config/prometheus.yml

# 2. Проверить синтаксис (если есть инструмент)
promtool check config /opt/monitoring/config/prometheus.yml

# 3. Перезапустить сервис
systemctl --user restart prometheus
```

### Ротация секретов

```bash
# Автоматическая ротация через Vault Agent
# Vault Agent автоматически обновляет секреты при их изменении в Vault

# Ручная ротация (если нужно)
sudo -u monitoring_svc systemctl --user restart vault-agent-monitoring

# Проверить обновление секретов
sudo -u monitoring_svc ls -lt /dev/shm/monitoring_secrets/
```

### Обновление RPM пакетов

```bash
# Через Jenkins Pipeline с новыми URL RPM

# Или через Ansible
cd ansible
ansible-playbook -i inventories/production playbooks/update_packages.yml \
  -e "prometheus_rpm_url=<NEW_URL>" \
  -e "grafana_rpm_url=<NEW_URL>" \
  -e "harvest_rpm_url=<NEW_URL>"
```

### Backup конфигураций

```bash
# От пользователя monitoring_admin

# Создать backup
tar -czf /opt/monitoring/backups/config_$(date +%Y%m%d_%H%M%S).tar.gz \
  /opt/monitoring/config/

# Автоматический backup через cron (от monitoring_admin)
crontab -e

# Добавить:
0 2 * * * tar -czf /opt/monitoring/backups/config_$(date +\%Y\%m\%d).tar.gz /opt/monitoring/config/
```

---

## Устранение неполадок

### Сервис не запускается

**Проблема**: `systemctl --user status <service>` показывает failed

**Решение**:
```bash
# 1. Проверить логи
journalctl --user -u <service> -n 50

# 2. Проверить наличие секретов
sudo -u monitoring_svc ls -la /dev/shm/monitoring_secrets/

# 3. Проверить права на файлы
ls -la /opt/monitoring/bin/<service>

# 4. Проверить конфигурацию
<service> --help # для просмотра опций проверки конфига

# 5. Запустить вручную для диагностики
sudo -u monitoring_svc /opt/monitoring/bin/<service> --config.file=/opt/monitoring/config/<service>.yml
```

### Ошибка доступа к Vault

**Проблема**: Vault Agent не может получить секреты

**Решение**:
```bash
# 1. Проверить статус Vault Agent
systemctl --user status vault-agent-monitoring

# 2. Проверить логи
journalctl --user -u vault-agent-monitoring -n 100

# 3. Проверить доступность Vault
curl -k https://<SEC_MAN_ADDR>/v1/sys/health

# 4. Проверить AppRole credentials
# (они должны быть в /opt/vault/conf/role_id.txt и secret_id.txt)

# 5. Перезапустить Vault Agent
systemctl --user restart vault-agent-monitoring
```

### Prometheus не может подключиться к Harvest

**Проблема**: Метрики Harvest не появляются в Prometheus

**Решение**:
```bash
# 1. Проверить доступность Harvest
curl -k https://localhost:12990/metrics

# 2. Проверить сертификаты mTLS
openssl s_client -connect localhost:12990 \
  -cert /dev/shm/monitoring_secrets/client.crt \
  -key /dev/shm/monitoring_secrets/client.key

# 3. Проверить конфигурацию Prometheus
grep -A 10 "harvest" /opt/monitoring/config/prometheus.yml

# 4. Проверить логи Prometheus
journalctl --user -u prometheus | grep -i harvest

# 5. Проверить firewall
sudo iptables -L -n | grep 12990
```

### Grafana не может подключиться к Prometheus

**Проблема**: Datasource в Grafana показывает ошибку

**Решение**:
```bash
# 1. Проверить доступность Prometheus из Grafana
curl -k --cert /dev/shm/monitoring_secrets/grafana-client.crt \
     --key /dev/shm/monitoring_secrets/grafana-client.key \
     https://localhost:9090/api/v1/query?query=up

# 2. Проверить настройки datasource в Grafana UI
# Settings → Data Sources → Prometheus

# 3. Проверить что клиентский сертификат загружен
# В datasource должны быть заполнены:
# - TLS Client Auth
# - TLS Client Cert
# - TLS Client Key

# 4. Пересоздать datasource через API
bash scripts/recreate_grafana_datasource.sh
```

### Порт уже занят

**Проблема**: `Address already in use`

**Решение**:
```bash
# 1. Найти процесс, использующий порт
sudo ss -tlnp | grep :<PORT>

# 2. Определить PID
sudo lsof -i :<PORT>

# 3. Остановить процесс
sudo kill <PID>

# Или использовать скрипт из проекта
bash scripts/free_port.sh <PORT>
```

### Секреты не найдены в /dev/shm

**Проблема**: Сервисы не могут найти сертификаты

**Решение**:
```bash
# 1. Проверить что /dev/shm смонтирован
mount | grep shm

# 2. Проверить размер /dev/shm
df -h /dev/shm

# 3. Создать директорию (если отсутствует)
sudo -u monitoring_svc mkdir -p /dev/shm/monitoring_secrets
sudo -u monitoring_svc chmod 700 /dev/shm/monitoring_secrets

# 4. Перезапустить Vault Agent
systemctl --user restart vault-agent-monitoring

# 5. Проверить появление файлов
watch -n 1 "sudo -u monitoring_svc ls -la /dev/shm/monitoring_secrets/"
```

### Недостаточно прав

**Проблема**: Permission denied при выполнении операций

**Решение**:
```bash
# 1. Проверить текущего пользователя
whoami
id

# 2. Проверить права на файл/директорию
ls -la <path>

# 3. Выполнить операцию от нужного пользователя
sudo -u <correct_user> <command>

# 4. Проверить sudoers права
sudo -l

# 5. Если прав нет - запросить через IDM
# См. SUDOERS_GUIDE.md
```

---

## Дополнительная информация

### Полезные команды

```bash
# Просмотр всех user services
systemctl --user list-units

# Просмотр использования ресурсов
systemctl --user status

# Просмотр логов за период
journalctl --user --since "1 hour ago"

# Просмотр только ошибок
journalctl --user -p err

# Экспорт метрик для анализа
curl -k https://localhost:9090/api/v1/query?query=up > /tmp/metrics.json
```

### Мониторинг производительности

```bash
# CPU и память сервисов
systemctl --user status prometheus grafana harvest | grep -E "(Memory|CPU)"

# Размер данных Prometheus
du -sh /opt/monitoring/data/prometheus/

# Размер логов
du -sh /opt/monitoring/logs/

# Количество активных метрик
curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data.numSeries'
```

### Контакты поддержки

- **Документация**: `/opt/monitoring/docs/`
- **Логи**: `/opt/monitoring/logs/`
- **Конфигурация**: `/opt/monitoring/config/`

---

**Конец руководства**


