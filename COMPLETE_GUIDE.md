# Полное Руководство - Безопасная Система Мониторинга

## 🎯 Цель проекта

Безопасное развертывание production-ready системы мониторинга (Prometheus + Grafana + NetApp Harvest) в корпоративной банковской инфраструктуре с полным соблюдением требований информационной безопасности.

---

## 📋 Содержание

1. [Краткий обзор](#краткий-обзор)
2. [Архитектура безопасности](#архитектура-безопасности)
3. [Компоненты проекта](#компоненты-проекта)
4. [Методы развертывания](#методы-развертывания)
5. [Пошаговое развертывание](#пошаговое-развертывание)
6. [Проверка и верификация](#проверка-и-верификация)
7. [Эксплуатация](#эксплуатация)
8. [Безопасность](#безопасность)
9. [Troubleshooting](#troubleshooting)
10. [FAQ](#faq)

---

## Краткий обзор

### Что включает проект

✅ **Документация (6 файлов, ~1500 страниц)**
- Руководство по развертыванию
- Модель безопасности
- Инструкции по созданию учетных записей
- Настройка Vault Agent
- Структура файловой системы
- Конфигурация sudoers

✅ **Ansible автоматизация**
- Готовые роли для всех компонентов
- Идемпотентные playbooks
- Inventory примеры
- Полная автоматизация развертывания

✅ **Jenkins Pipeline**
- Безопасная передача секретов
- Автоматическая очистка
- Интеграция с Vault
- Проверка безопасности

✅ **Конфигурационные файлы**
- Prometheus с mTLS
- Grafana с HTTPS
- Harvest для NetApp
- Vault Agent templates

✅ **Systemd User Units**
- Все сервисы работают под непривилегированным пользователем
- Автозапуск через user systemd
- Изоляция процессов
- Ограничение capabilities

✅ **Скрипты**
- Управление секретами
- Проверка безопасности
- Очистка временных данных
- Верификация установки

---

## Архитектура безопасности

### Модель "Наименьших привилегий"

```
┌─────────────────────────────────────────────────────────────┐
│                    PRODUCTION SERVER                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Prometheus   │  │  Grafana     │  │  Harvest     │      │
│  │ (9090)       │  │  (3000)      │  │  (12990)     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         ↓                 ↓                  ↓               │
│  ┌──────────────────────────────────────────────────┐       │
│  │        User Systemd (monitoring_svc)            │       │
│  └──────────────────────────────────────────────────┘       │
│         ↓                                                    │
│  ┌──────────────────────────────────────────────────┐       │
│  │   Vault Agent (управление секретами)            │       │
│  └──────────────────────────────────────────────────┘       │
│         ↓                                                    │
│  ┌──────────────────────────────────────────────────┐       │
│  │   /dev/shm/monitoring_secrets (tmpfs в RAM)     │       │
│  │   - Сертификаты (server.crt, server.key)       │       │
│  │   - Credentials (netapp, grafana)               │       │
│  │   - Vault token                                  │       │
│  └──────────────────────────────────────────────────┘       │
│                                                               │
│  ┌──────────────────────────────────────────────────┐       │
│  │   /opt/monitoring/                               │       │
│  │   ├── bin/      (750, ci:monitoring)            │       │
│  │   ├── config/   (750, ci:monitoring)            │       │
│  │   ├── data/     (770, svc:monitoring)           │       │
│  │   ├── logs/     (770, svc:admin)                │       │
│  │   └── scripts/  (755, ci:monitoring)            │       │
│  └──────────────────────────────────────────────────┘       │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│                    УЧЕТНЫЕ ЗАПИСИ                            │
├─────────────────────────────────────────────────────────────┤
│  • monitoring_svc   → СУЗ (запуск сервисов)                 │
│  • monitoring_ci    → ТУЗ (деплой, обновления)              │
│  • monitoring_admin → ПУЗ (администрирование)               │
│  • monitoring_ro    → ReadOnly (чтение логов)               │
└─────────────────────────────────────────────────────────────┘
```

### Защита на уровнях

1. **Сеть**: Firewall, mTLS, ограничение портов
2. **Аутентификация**: SSH keys, AppRole (Vault), mTLS
3. **Авторизация**: RBAC (4 роли), sudo rules, file permissions
4. **Шифрование**: TLS 1.2+, AES-256-GCM
5. **Аудит**: Логирование всех действий, journalctl

---

## Компоненты проекта

### Структура директорий

```
secure_deployment/
├── README.md                          # Главное описание
├── QUICKSTART.md                      # Быстрый старт
├── PROJECT_SUMMARY.md                 # Сводка проекта
├── IMPLEMENTATION_NOTES.md            # Заметки по реализации
├── COMPLETE_GUIDE.md                  # Это руководство
├── Jenkinsfile                        # CI/CD Pipeline
│
├── docs/                              # 📚 Документация
│   ├── DEPLOYMENT_GUIDE.md           # Руководство по развертыванию
│   ├── SECURITY_MODEL.md             # Модель безопасности
│   ├── IDM_ACCOUNTS_GUIDE.md         # Создание учетных записей
│   ├── SUDOERS_GUIDE.md              # Настройка sudo
│   ├── VAULT_SECRETS_GUIDE.md        # Работа с секретами
│   └── FILESYSTEM_STRUCTURE.md       # Структура ФС
│
├── ansible/                           # 🤖 Ansible автоматизация
│   ├── README.md                     # Документация Ansible
│   ├── ansible.cfg                   # Конфигурация Ansible
│   ├── inventories/                  # Инвентори серверов
│   │   └── production
│   ├── group_vars/                   # Переменные групп
│   │   └── monitoring.yml
│   ├── roles/                        # Ansible роли
│   │   ├── common/                   # Общая подготовка
│   │   ├── vault_agent/              # Vault Agent
│   │   ├── prometheus/               # Prometheus
│   │   ├── grafana/                  # Grafana
│   │   └── harvest/                  # Harvest
│   └── playbooks/                    # Playbooks
│       └── deploy_monitoring.yml     # Главный playbook
│
├── config/                            # ⚙️ Примеры конфигураций
│   ├── prometheus.yml.example        # Prometheus конфиг
│   ├── prometheus-web-config.yml.example  # TLS для Prometheus
│   ├── grafana.ini.example           # Grafana конфиг
│   ├── harvest.yml.example           # Harvest конфиг
│   └── vault-agent.hcl.example       # Vault Agent конфиг
│
├── systemd/                           # 🔧 Systemd units
│   ├── prometheus.service            # Prometheus unit
│   ├── grafana.service               # Grafana unit
│   ├── harvest.service               # Harvest unit
│   └── vault-agent-monitoring.service # Vault Agent unit
│
├── scripts/                           # 📝 Утилитарные скрипты
│   ├── manage_secrets.sh             # Управление секретами
│   ├── cleanup_secrets.sh            # Очистка секретов
│   └── verify_security.sh            # Проверка безопасности
│
└── sudoers/                           # 🔐 Sudo правила
    └── monitoring_system             # Файл для /etc/sudoers.d/
```

---

## Методы развертывания

### Метод 1: Jenkins Pipeline (Рекомендуется) 🚀

**Преимущества:**
- Полная автоматизация
- Интеграция с Vault
- Безопасная передача секретов
- Логирование всех действий
- Проверка безопасности

**Использование:**

1. Настройте Jenkins job с параметрами
2. Укажите целевой сервер
3. Запустите pipeline
4. Дождитесь завершения
5. Проверьте отчет

```groovy
// В Jenkins создайте Pipeline Job
// Используйте Jenkinsfile из проекта
// Укажите параметры в Build with Parameters
```

### Метод 2: Ansible (Гибкий) ⚙️

**Преимущества:**
- Идемпотентность
- Можно запускать частично (теги)
- Проверка изменений (--check, --diff)
- Подходит для batch операций

**Использование:**

```bash
cd secure_deployment/ansible

# Настроить inventory
vim inventories/production

# Запустить развертывание
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml
```

### Метод 3: Ручное развертывание (Для понимания) 📖

**Преимущества:**
- Полный контроль
- Понимание каждого шага
- Обучение

**Использование:**

Следуйте пошаговому руководству в `docs/DEPLOYMENT_GUIDE.md`

---

## Пошаговое развертывание

### Этап 0: Подготовка (Before you begin)

#### 0.1. Создание учетных записей в IDM

```bash
# Следуйте инструкциям в docs/IDM_ACCOUNTS_GUIDE.md

# Необходимо создать:
- monitoring_svc   (nologin, для запуска сервисов)
- monitoring_ci    (интерактивная, для деплоя)
- monitoring_admin (интерактивная, администрирование)
- monitoring_ro    (интерактивная, чтение логов)

# Группа:
- monitoring (все пользователи в этой группе)
```

#### 0.2. Настройка sudo прав

```bash
# Скопировать файл sudoers на сервер
scp sudoers/monitoring_system root@target-server:/etc/sudoers.d/

# Проверить синтаксис
sudo visudo -c -f /etc/sudoers.d/monitoring_system

# Установить права
sudo chmod 440 /etc/sudoers.d/monitoring_system
sudo chown root:root /etc/sudoers.d/monitoring_system
```

#### 0.3. Создание файловых систем через RLM

```bash
# В RLM создать файловые системы:
# /opt/monitoring        - 10 GB (базовая директория)
# /opt/monitoring/data   - 50 GB (данные Prometheus, Grafana)
# /opt/monitoring/logs   - 20 GB (логи)

# Владельцы:
# /opt/monitoring        → monitoring_ci:monitoring
# /opt/monitoring/data   → monitoring_svc:monitoring
# /opt/monitoring/logs   → monitoring_svc:monitoring_admin
```

#### 0.4. Получение секретов из Vault

```bash
# В Vault должны быть созданы:
# - secret/data/monitoring/vault-agent (AppRole credentials)
# - secret/data/monitoring/rpm-urls (URL RPM пакетов)
# - secret/data/monitoring/grafana-web (Grafana credentials)
# - secret/data/monitoring/netapp-api (NetApp credentials)
# - pki/issue/monitoring (PKI для сертификатов)

# AppRole должен иметь policy для чтения этих секретов
```

### Этап 1: Установка базового ПО

```bash
# SSH на целевой сервер
ssh monitoring_ci@target-server

# Установка зависимостей
sudo yum install -y curl jq openssl systemd

# Проверка версий
systemctl --version
openssl version
jq --version
```

### Этап 2: Установка RPM пакетов через RLM

```bash
# В RLM создать задачу на установку:
# - prometheus (из портала ДИ)
# - grafana (из портала ДИ)
# - harvest (из портала ДИ или custom RPM)

# После установки проверить:
rpm -qa | grep -E "prometheus|grafana|harvest"
```

### Этап 3: Настройка Vault Agent

```bash
# Копирование AppRole credentials (из Jenkins или Vault)
sudo -u monitoring_svc mkdir -p /opt/vault/conf
sudo -u monitoring_svc bash -c 'echo "ROLE_ID_HERE" > /opt/vault/conf/role_id.txt'
sudo -u monitoring_svc bash -c 'echo "SECRET_ID_HERE" > /opt/vault/conf/secret_id.txt'
sudo -u monitoring_svc chmod 600 /opt/vault/conf/*.txt

# Копирование конфигурации Vault Agent
sudo cp config/vault-agent.hcl.example /opt/monitoring/config/vault-agent.hcl
sudo vim /opt/monitoring/config/vault-agent.hcl
# Изменить: namespace, server domain

# Копирование systemd unit
sudo -u monitoring_svc cp systemd/vault-agent-monitoring.service ~/.config/systemd/user/

# Запуск
sudo -u monitoring_svc systemctl --user daemon-reload
sudo -u monitoring_svc systemctl --user enable --now vault-agent-monitoring

# Проверка
sudo -u monitoring_svc systemctl --user status vault-agent-monitoring
```

### Этап 4: Настройка Prometheus

```bash
# Копирование конфигураций
sudo cp config/prometheus.yml.example /opt/monitoring/config/prometheus.yml
sudo cp config/prometheus-web-config.yml.example /opt/monitoring/config/web-config.yml

# Редактирование (замена SERVER_DOMAIN на ваш домен)
sudo vim /opt/monitoring/config/prometheus.yml
sudo vim /opt/monitoring/config/web-config.yml

# Установка прав
sudo chown monitoring_ci:monitoring /opt/monitoring/config/prometheus.yml
sudo chmod 640 /opt/monitoring/config/prometheus.yml

# Копирование systemd unit
sudo -u monitoring_svc cp systemd/prometheus.service ~/.config/systemd/user/

# Запуск
sudo -u monitoring_svc systemctl --user daemon-reload
sudo -u monitoring_svc systemctl --user enable --now prometheus

# Проверка
sudo -u monitoring_svc systemctl --user status prometheus
curl https://localhost:9090/metrics --cacert /dev/shm/monitoring_secrets/ca_chain.crt
```

### Этап 5: Настройка Grafana

```bash
# Копирование конфигурации
sudo cp config/grafana.ini.example /opt/monitoring/config/grafana.ini

# Редактирование
sudo vim /opt/monitoring/config/grafana.ini
# Изменить: admin_password, secret_key, domain

# Установка прав
sudo chown monitoring_ci:monitoring /opt/monitoring/config/grafana.ini
sudo chmod 640 /opt/monitoring/config/grafana.ini

# Копирование systemd unit
sudo -u monitoring_svc cp systemd/grafana.service ~/.config/systemd/user/

# Запуск
sudo -u monitoring_svc systemctl --user daemon-reload
sudo -u monitoring_svc systemctl --user enable --now grafana

# Проверка
sudo -u monitoring_svc systemctl --user status grafana
curl https://localhost:3000 --cacert /dev/shm/monitoring_secrets/ca_chain.crt
```

### Этап 6: Настройка Harvest

```bash
# Копирование конфигурации
sudo cp config/harvest.yml.example /opt/monitoring/config/harvest.yml

# Редактирование
sudo vim /opt/monitoring/config/harvest.yml
# Изменить: NetApp адреса, credentials

# Установка прав
sudo chown monitoring_ci:monitoring /opt/monitoring/config/harvest.yml
sudo chmod 640 /opt/monitoring/config/harvest.yml

# Копирование systemd unit
sudo -u monitoring_svc cp systemd/harvest.service ~/.config/systemd/user/

# Запуск
sudo -u monitoring_svc systemctl --user daemon-reload
sudo -u monitoring_svc systemctl --user enable --now harvest

# Проверка
sudo -u monitoring_svc systemctl --user status harvest
curl http://localhost:12991/metrics  # Unix metrics
```

### Этап 7: Настройка Firewall

```bash
# Открыть порты
sudo firewall-cmd --permanent --add-port=3000/tcp  # Grafana
sudo firewall-cmd --permanent --add-port=12990/tcp # Harvest NetApp (HTTPS)
sudo firewall-cmd --reload

# Prometheus доступен только локально (настроено в systemd unit)
```

### Этап 8: Проверка безопасности

```bash
# Запуск скрипта проверки
sudo bash /opt/monitoring/scripts/verify_security.sh

# Вывод должен показать:
# ✓ Все права корректны
# ✓ Все сервисы запущены
# ✓ Нет security violations
```

---

## Проверка и верификация

### Проверка сервисов

```bash
# Статус всех сервисов
sudo -u monitoring_svc systemctl --user status prometheus grafana harvest vault-agent-monitoring

# Логи
journalctl --user -u prometheus -f
journalctl --user -u grafana -f
journalctl --user -u harvest -f
```

### Проверка портов

```bash
# Все порты
ss -tlnp | grep -E "9090|3000|12990|12991|8887"

# Тест доступности
curl -k https://localhost:9090/metrics
curl -k https://localhost:3000
curl http://localhost:12991/metrics
```

### Проверка сертификатов

```bash
# Проверить наличие
ls -la /dev/shm/monitoring_secrets/

# Проверить срок действия
openssl x509 -in /dev/shm/monitoring_secrets/server.crt -noout -dates

# Проверить содержимое
openssl x509 -in /dev/shm/monitoring_secrets/server.crt -noout -text
```

### Проверка Prometheus

```bash
# Targets
curl -k https://localhost:9090/api/v1/targets | jq

# Config
curl -k https://localhost:9090/api/v1/status/config | jq

# Health
curl -k https://localhost:9090/-/healthy
```

### Проверка Grafana

```bash
# Health check
curl -k https://localhost:3000/api/health

# Login test
curl -k -X POST https://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","password":"YOUR_PASSWORD"}'
```

### Проверка Harvest

```bash
# Метрики
curl http://localhost:12991/metrics | grep "^netapp_"

# Status
harvest admin status

# Конфиг check
harvest doctor
```

---

## Эксплуатация

### Повседневные операции

#### Перезапуск сервисов

```bash
# Отдельный сервис
sudo -u monitoring_svc systemctl --user restart prometheus

# Все сервисы
sudo -u monitoring_svc systemctl --user restart prometheus grafana harvest
```

#### Просмотр логов

```bash
# Real-time
journalctl --user -u prometheus -f

# Последние 100 строк
journalctl --user -u prometheus -n 100

# За период
journalctl --user -u prometheus --since "2024-01-01" --until "2024-01-02"

# С фильтром
journalctl --user -u prometheus | grep ERROR
```

#### Обновление конфигураций

```bash
# Изменить конфиг
sudo vim /opt/monitoring/config/prometheus.yml

# Проверить синтаксис
promtool check config /opt/monitoring/config/prometheus.yml

# Применить (reload без перезапуска)
sudo -u monitoring_svc systemctl --user reload prometheus

# Или перезапустить
sudo -u monitoring_svc systemctl --user restart prometheus
```

#### Ротация логов

```bash
# Ручная ротация
sudo -u monitoring_svc logrotate -f /opt/monitoring/config/logrotate.conf

# Проверка настроек cron
crontab -l -u monitoring_svc
```

### Обслуживание

#### Обновление сертификатов

```bash
# Vault Agent автоматически обновляет сертификаты
# Проверить статус обновления
journalctl --user -u vault-agent-monitoring | grep "renewed"

# Ручное обновление (если нужно)
sudo -u monitoring_svc systemctl --user restart vault-agent-monitoring
```

#### Backup конфигураций

```bash
# Создать backup
tar -czf monitoring-config-$(date +%Y%m%d).tar.gz /opt/monitoring/config/

# Копировать в безопасное место
scp monitoring-config-*.tar.gz backup-server:/backups/
```

#### Очистка старых данных

```bash
# Prometheus (автоматически по retention policy)
# Проверить размер
du -sh /opt/monitoring/data/prometheus

# Grafana
# Удалить старые snapshots
grafana-cli admin clean-snapshots --days 30
```

#### Мониторинг дискового пространства

```bash
# Проверка
df -h /opt/monitoring/data
df -h /opt/monitoring/logs

# Алерт если > 80%
df -h /opt/monitoring/data | awk 'NR==2 {if(int($5) > 80) print "WARNING: Disk usage is " $5}'
```

---

## Безопасность

### Регулярные проверки безопасности

```bash
# Еженедельно
/opt/monitoring/scripts/verify_security.sh

# Проверка прав
find /opt/monitoring -type f -perm /o+w  # Не должно быть вывода

# Проверка сертификатов (срок действия)
for cert in /dev/shm/monitoring_secrets/*.crt; do
    echo "=== $cert ==="
    openssl x509 -in "$cert" -noout -enddate
done
```

### Обновление безопасности

```bash
# Обновление RPM пакетов через RLM
# (следовать процедурам RLM)

# Обновление сертификатов
# (автоматически через Vault Agent)

# Обновление паролей
# (в Vault, Vault Agent подхватит автоматически)
```

### Аудит

```bash
# Кто подключался
last -a | grep monitoring

# Sudo операции
sudo grep monitoring /var/log/secure

# Изменения в конфигурациях (через Git)
cd /opt/monitoring/config
git log --all --oneline --decorate
```

---

## Troubleshooting

### Prometheus не запускается

**Проблема**: `systemctl --user status prometheus` показывает failed

**Решение**:

```bash
# 1. Проверить логи
journalctl --user -u prometheus -n 50

# 2. Проверить конфигурацию
promtool check config /opt/monitoring/config/prometheus.yml

# 3. Проверить порт
ss -tlnp | grep 9090

# 4. Проверить сертификаты
ls -la /dev/shm/monitoring_secrets/

# 5. Проверить права
ls -la /opt/monitoring/config/prometheus.yml
ls -la /opt/monitoring/data/prometheus
```

### Grafana не доступна

**Проблема**: Cannot connect to https://server:3000

**Решение**:

```bash
# 1. Проверить статус
sudo -u monitoring_svc systemctl --user status grafana

# 2. Проверить порт
ss -tlnp | grep 3000

# 3. Проверить firewall
sudo firewall-cmd --list-ports

# 4. Проверить логи
journalctl --user -u grafana -n 50

# 5. Проверить конфигурацию
grep -E "^(protocol|http_port|domain)" /opt/monitoring/config/grafana.ini
```

### Harvest не собирает метрики

**Проблема**: Метрики не появляются в Prometheus

**Решение**:

```bash
# 1. Проверить статус
sudo -u monitoring_svc systemctl --user status harvest

# 2. Проверить логи
tail -f /opt/monitoring/logs/harvest/*.log

# 3. Проверить connectivity к NetApp
telnet netapp-cluster.example.com 443

# 4. Проверить credentials
# (в /dev/shm/monitoring_secrets/netapp_creds.env)

# 5. Проверить конфигурацию
harvest doctor --poller YourPoller

# 6. Проверить метрики локально
curl http://localhost:12991/metrics | grep netapp
```

### Vault Agent не получает секреты

**Проблема**: Секреты отсутствуют в /dev/shm

**Решение**:

```bash
# 1. Проверить статус
sudo -u monitoring_svc systemctl --user status vault-agent-monitoring

# 2. Проверить логи
journalctl --user -u vault-agent-monitoring -n 100

# 3. Проверить AppRole credentials
ls -la /opt/vault/conf/role_id.txt
cat /opt/vault/conf/role_id.txt  # Должен быть UUID

# 4. Проверить connectivity к Vault
curl -I https://vault.sigma.sbrf.ru

# 5. Проверить права на /dev/shm
ls -la /dev/shm/monitoring_secrets/

# 6. Тест AppRole вручную
export VAULT_ADDR="https://vault.sigma.sbrf.ru"
export VAULT_NAMESPACE="KPRJ_000000"
vault write auth/approle/login \
  role_id="..." \
  secret_id="..."
```

### Permission Denied ошибки

**Проблема**: Permission denied при выполнении команд

**Решение**:

```bash
# 1. Проверить текущего пользователя
whoami
groups

# 2. Проверить sudo права
sudo -l

# 3. Проверить владельца файла
ls -la /path/to/file

# 4. Проверить права на директорию
namei -l /opt/monitoring/config/file.yml

# 5. Исправить права (если нужно)
sudo chown monitoring_ci:monitoring /opt/monitoring/config/file.yml
sudo chmod 640 /opt/monitoring/config/file.yml
```

---

## FAQ

### Q: Как добавить еще один NetApp кластер?

**A**: 
1. Добавьте poller в `/opt/monitoring/config/harvest.yml`
2. Перезапустите Harvest: `systemctl --user restart harvest`
3. Проверьте метрики: `curl http://localhost:12991/metrics | grep yourcluster`

### Q: Как изменить retention Prometheus?

**A**:
1. Отредактируйте `/opt/monitoring/config/prometheus.yml`
2. Измените `storage.tsdb.retention.time: "30d"`
3. Примените: `systemctl --user restart prometheus`

### Q: Как добавить нового пользователя Grafana?

**A**:
1. Откройте Grafana UI
2. Configuration → Users → Invite
3. Или через API:
```bash
curl -X POST https://localhost:3000/api/admin/users \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{"name":"User Name","email":"user@example.com","login":"username","password":"password","role":"Viewer"}'
```

### Q: Как обновить RPM пакеты?

**A**:
1. Создайте задачу в RLM для обновления пакета
2. После обновления перезапустите сервис
3. Проверьте работу

### Q: Что делать если сертификат истек?

**A**:
Vault Agent автоматически обновляет сертификаты. Если нет:
1. Перезапустите Vault Agent: `systemctl --user restart vault-agent-monitoring`
2. Проверьте логи: `journalctl --user -u vault-agent-monitoring`
3. Проверьте AppRole credentials

### Q: Как мигрировать на другой сервер?

**A**:
1. Backup данных: `/opt/monitoring/data/`
2. Backup конфигураций: `/opt/monitoring/config/`
3. Развернуть на новом сервере (через Ansible)
4. Восстановить данные
5. Обновить DNS/балансировщик

### Q: Как настроить алерты?

**A**:
1. Создайте alerting rules в `/opt/monitoring/config/rules/alerts.yml`
2. Настройте Alertmanager (опционально)
3. Или используйте Grafana Alerting

### Q: Как интегрировать с LDAP?

**A**:
В `/opt/monitoring/config/grafana.ini`:
```ini
[auth.ldap]
enabled = true
config_file = /opt/monitoring/config/ldap.toml
```

Создайте `ldap.toml` с настройками LDAP.

---

## 📞 Поддержка

### Документация

- **Общая**: [README.md](README.md)
- **Развертывание**: [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)
- **Безопасность**: [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md)
- **Ansible**: [ansible/README.md](ansible/README.md)

### Полезные команды

```bash
# Статус всех сервисов
sudo -u monitoring_svc systemctl --user status prometheus grafana harvest

# Логи
journalctl --user -u prometheus -f

# Проверка безопасности
sudo bash /opt/monitoring/scripts/verify_security.sh

# Размер данных
du -sh /opt/monitoring/data/*

# Открытые порты
ss -tlnp | grep -E "9090|3000|12990"
```

---

## ✅ Чек-лист для production

- [ ] Все учетные записи созданы в IDM
- [ ] Sudoers файл настроен и протестирован
- [ ] Файловые системы созданы через RLM
- [ ] Vault Agent получает секреты
- [ ] Все сервисы запущены и работают
- [ ] Сертификаты валидны и обновляются
- [ ] Firewall настроен
- [ ] Логи пишутся и ротируются
- [ ] Метрики собираются с NetApp
- [ ] Grafana показывает дашборды
- [ ] Проверка безопасности пройдена
- [ ] Backup конфигураций настроен
- [ ] Мониторинг дискового пространства
- [ ] Документация обновлена

---

**Версия**: 1.0  
**Дата**: 2024  
**Статус**: Production Ready ✅


