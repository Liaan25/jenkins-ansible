# Ansible Проект - Безопасное Развертывание Системы Мониторинга

## Оглавление

- [Введение](#введение)
- [Требования](#требования)
- [Быстрый старт](#быстрый-старт)
- [Структура проекта](#структура-проекта)
- [Конфигурация](#конфигурация)
- [Использование](#использование)
- [Безопасность](#безопасность)
- [Troubleshooting](#troubleshooting)

## Введение

Этот Ansible проект предназначен для автоматизированного развертывания системы мониторинга (Prometheus + Grafana + NetApp Harvest) с полным соблюдением корпоративных требований безопасности.

### Ключевые особенности

✅ **Идемпотентность** - можно запускать многократно без риска  
✅ **Безопасность** - все секреты передаются через `/dev/shm`  
✅ **Модульность** - роли можно использовать независимо  
✅ **Проверки** - автоматическая верификация после развертывания  
✅ **Логирование** - полная трассировка всех действий  

## Требования

### На управляющем сервере (откуда запускается Ansible)

- Ansible >= 2.12
- Python >= 3.8
- SSH клиент
- jq (для обработки JSON)

```bash
# Установка на RHEL/CentOS
sudo yum install ansible python3 openssh-clients jq

# Проверка версии
ansible --version
```

### На целевых серверах (куда развертывается)

- RHEL/CentOS 7/8
- Python 3.x
- SSH сервер
- Пользователь `monitoring_ci` с настроенными правами sudo
- Созданные учетные записи через IDM:
  - `monitoring_svc` (СУЗ)
  - `monitoring_ci` (ТУЗ)
  - `monitoring_admin` (ПУЗ)
  - `monitoring_ro` (ReadOnly)

### Доступ к ресурсам

- Vault (SecMan) для получения секретов
- RLM для создания файловых систем
- Bitbucket/Git для клонирования репозитория
- Сеть до целевых серверов и NetApp кластеров

## Быстрый старт

### 1. Подготовка

```bash
# Клонировать репозиторий
git clone <repository_url>
cd secure_deployment/ansible

# Скопировать пример inventory
cp inventories/production inventories/my_environment

# Отредактировать inventory
vim inventories/my_environment
```

### 2. Настройка inventory

Отредактируйте `inventories/my_environment`:

```ini
[monitoring_servers]
mon-prod-01 ansible_host=10.10.10.101 netapp_api_addr=netapp-cluster-01.example.com

[monitoring_servers:vars]
ansible_user=monitoring_ci
ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### 3. Настройка переменных

Отредактируйте `group_vars/monitoring.yml`:

```yaml
# ОБЯЗАТЕЛЬНО изменить:
vault_namespace: "KPRJ_123456"  # Ваш namespace
admin_email: "admin@yourcompany.com"
netapp_api_addr: "netapp-cluster.example.com"
```

### 4. Проверка подключения

```bash
# Проверить SSH подключение
ansible -i inventories/my_environment monitoring_servers -m ping

# Проверить sudo права
ansible -i inventories/my_environment monitoring_servers -m shell -a "whoami" --become
```

### 5. Запуск развертывания

```bash
# Полное развертывание
ansible-playbook -i inventories/my_environment playbooks/deploy_monitoring.yml

# С дополнительными параметрами
ansible-playbook -i inventories/my_environment playbooks/deploy_monitoring.yml \
  --extra-vars "netapp_api_addr=netapp-cluster.example.com" \
  --extra-vars "rlm_token=YOUR_RLM_TOKEN" \
  -v
```

### 6. Проверка результата

```bash
# Проверить статус сервисов на целевом сервере
ssh monitoring_ci@10.10.10.101
sudo -u monitoring_svc systemctl --user status prometheus
sudo -u monitoring_svc systemctl --user status grafana
sudo -u monitoring_svc systemctl --user status harvest
```

## Структура проекта

```
ansible/
├── ansible.cfg                 # Основная конфигурация Ansible
├── inventories/                # Инвентори для разных окружений
│   ├── production             # Production серверы
│   ├── staging                # Staging серверы (опционально)
│   └── development            # Dev серверы (опционально)
├── group_vars/                 # Переменные для групп серверов
│   └── monitoring.yml         # Общие переменные для мониторинга
├── host_vars/                  # Переменные для конкретных хостов (опционально)
├── roles/                      # Ansible роли
│   ├── common/                # Общая роль (подготовка)
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── defaults/
│   │   ├── handlers/
│   │   └── templates/
│   ├── vault_agent/           # Роль для Vault Agent
│   ├── prometheus/            # Роль для Prometheus
│   ├── grafana/               # Роль для Grafana
│   └── harvest/               # Роль для Harvest
├── playbooks/                  # Playbooks
│   ├── deploy_monitoring.yml  # Главный playbook
│   ├── update_config.yml      # Обновление конфигураций
│   └── rollback.yml           # Откат изменений
└── README.md                   # Эта документация
```

## Конфигурация

### ansible.cfg

Основные настройки Ansible:

```ini
[defaults]
inventory = inventories/production
roles_path = roles
host_key_checking = False
retry_files_enabled = False
```

### Inventory

Определение целевых серверов:

```ini
[monitoring_servers]
server1 ansible_host=10.10.10.101
server2 ansible_host=10.10.10.102

[monitoring_servers:vars]
ansible_user=monitoring_ci
netapp_api_addr=netapp-cluster.example.com
```

### Group Variables

Общие переменные в `group_vars/monitoring.yml`:

```yaml
# Пути
monitoring_base_dir: "/opt/monitoring"

# Пользователи
monitoring_service_user: "monitoring_svc"
monitoring_ci_user: "monitoring_ci"

# Vault
vault_addr: "https://vault.sigma.sbrf.ru"
vault_namespace: "KPRJ_000000"

# Порты
prometheus_port: 9090
grafana_port: 3000
```

## Использование

### Основные команды

```bash
# Полное развертывание
ansible-playbook -i <inventory> playbooks/deploy_monitoring.yml

# Только определенные теги
ansible-playbook -i <inventory> playbooks/deploy_monitoring.yml --tags "setup,config"

# Dry-run (без изменений)
ansible-playbook -i <inventory> playbooks/deploy_monitoring.yml --check

# Показать изменения
ansible-playbook -i <inventory> playbooks/deploy_monitoring.yml --diff

# Verbose режим (отладка)
ansible-playbook -i <inventory> playbooks/deploy_monitoring.yml -vvv
```

### Теги

Доступные теги для выборочного выполнения:

| Тег | Описание |
|-----|----------|
| `setup` | Подготовка инфраструктуры |
| `vault` | Настройка Vault Agent |
| `prometheus` | Установка Prometheus |
| `grafana` | Установка Grafana |
| `harvest` | Установка Harvest |
| `config` | Обновление конфигураций |
| `service` | Управление сервисами |
| `verify` | Проверка безопасности |

Примеры:

```bash
# Только настройка Prometheus
ansible-playbook playbooks/deploy_monitoring.yml --tags "prometheus"

# Обновить только конфигурации
ansible-playbook playbooks/deploy_monitoring.yml --tags "config"

# Проверить безопасность
ansible-playbook playbooks/deploy_monitoring.yml --tags "verify"
```

### Extra Variables

Передача дополнительных параметров:

```bash
# Переопределить NetApp адрес
ansible-playbook playbooks/deploy_monitoring.yml \
  --extra-vars "netapp_api_addr=netapp-cluster.example.com"

# Передать RLM token
ansible-playbook playbooks/deploy_monitoring.yml \
  --extra-vars "rlm_token=YOUR_TOKEN"

# Несколько параметров
ansible-playbook playbooks/deploy_monitoring.yml \
  --extra-vars "netapp_api_addr=netapp.com prometheus_port=9091"

# Из файла JSON
ansible-playbook playbooks/deploy_monitoring.yml \
  --extra-vars "@vars.json"
```

## Безопасность

### 1. SSH Ключи

```bash
# Генерация SSH ключа (если нет)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/monitoring_ci_rsa

# Копирование на целевой сервер
ssh-copy-id -i ~/.ssh/monitoring_ci_rsa monitoring_ci@target-server

# Использование в Ansible
ansible_ssh_private_key_file: ~/.ssh/monitoring_ci_rsa
```

### 2. Vault Integration

Ansible автоматически получает секреты из Vault через Jenkins pipeline. В standalone режиме:

```bash
# Экспорт переменных окружения
export VAULT_ADDR="https://vault.sigma.sbrf.ru"
export VAULT_NAMESPACE="KPRJ_000000"
export VAULT_TOKEN="your-token"

# Использование в playbook
ansible-playbook playbooks/deploy_monitoring.yml \
  --extra-vars "vault_token=$VAULT_TOKEN"
```

### 3. Передача секретов

Секреты **НИКОГДА** не хранятся в inventory или group_vars. Только через:

- Jenkins pipeline (рекомендуется)
- Ansible Vault (для шифрования)
- Environment переменные
- `/dev/shm` на целевом сервере

### 4. Sudo права

Ansible использует только разрешенные sudo команды из `/etc/sudoers.d/monitoring_system`:

```bash
# Проверка sudo прав
sudo -l -U monitoring_ci

# Тестирование конкретной команды
sudo -u monitoring_svc systemctl --user status prometheus
```

### 5. Проверка безопасности

После развертывания автоматически запускается скрипт проверки:

```bash
# Автоматически (в playbook)
- name: "Проверка безопасности"
  command: bash /opt/monitoring/scripts/verify_security.sh

# Вручную на сервере
ssh monitoring_ci@target-server
sudo bash /opt/monitoring/scripts/verify_security.sh
```

## Troubleshooting

### Проблема: "Permission denied"

```bash
# Проверить SSH подключение
ssh -i ~/.ssh/id_rsa monitoring_ci@target-server

# Проверить sudo права
ssh monitoring_ci@target-server "sudo -l"

# Проверить группы пользователя
ssh monitoring_ci@target-server "groups"
```

### Проблема: "Failed to connect to the host"

```bash
# Проверить connectivity
ping target-server

# Проверить SSH порт
nc -zv target-server 22

# Проверить inventory
ansible-inventory -i inventories/production --list
```

### Проблема: "Module not found"

```bash
# Установить недостающие модули
pip3 install ansible-core
pip3 install jmespath

# Проверить версию Ansible
ansible --version

# Обновить Ansible
pip3 install --upgrade ansible
```

### Проблема: "Vault secrets not available"

```bash
# Проверить AppRole credentials на сервере
ssh monitoring_ci@target-server "ls -la /opt/vault/conf/"

# Проверить Vault Agent
ssh monitoring_ci@target-server "sudo -u monitoring_svc systemctl --user status vault-agent-monitoring"

# Проверить логи
ssh monitoring_ci@target-server "journalctl --user -u vault-agent-monitoring -f"
```

### Проблема: "Service failed to start"

```bash
# Проверить статус сервиса
ssh monitoring_ci@target-server "sudo -u monitoring_svc systemctl --user status prometheus"

# Проверить логи
ssh monitoring_ci@target-server "journalctl --user -u prometheus -n 50"

# Проверить конфигурацию
ssh monitoring_ci@target-server "promtool check config /opt/monitoring/config/prometheus.yml"
```

### Отладка Ansible

```bash
# Максимальный verbose
ansible-playbook playbooks/deploy_monitoring.yml -vvvv

# Запустить с пошаговым выполнением
ansible-playbook playbooks/deploy_monitoring.yml --step

# Начать с определенной задачи
ansible-playbook playbooks/deploy_monitoring.yml --start-at-task="Task Name"

# Ограничить выполнение одним хостом
ansible-playbook playbooks/deploy_monitoring.yml --limit mon-prod-01
```

## Дополнительные команды

### Управление сервисами

```bash
# Перезапуск всех сервисов
ansible monitoring_servers -m shell -a "sudo -u monitoring_svc systemctl --user restart prometheus grafana harvest"

# Проверка статуса
ansible monitoring_servers -m shell -a "sudo -u monitoring_svc systemctl --user status prometheus"

# Просмотр логов
ansible monitoring_servers -m shell -a "journalctl --user -u prometheus -n 20"
```

### Сбор информации

```bash
# Сбор фактов о системе
ansible monitoring_servers -m setup

# Проверка дискового пространства
ansible monitoring_servers -m shell -a "df -h /opt/monitoring"

# Проверка портов
ansible monitoring_servers -m shell -a "ss -tlnp | grep -E '9090|3000|12990'"
```

### Обновление конфигураций

```bash
# Обновить только конфигурацию Prometheus
ansible-playbook playbooks/deploy_monitoring.yml --tags "prometheus,config"

# Обновить конфигурацию без перезапуска
ansible-playbook playbooks/deploy_monitoring.yml --tags "config" --skip-tags "service"
```

## Лучшие практики

1. **Тестирование на dev/stage** перед production
2. **Использование тегов** для частичного развертывания
3. **Dry-run (`--check`)** перед реальными изменениями
4. **Версионирование** inventory и переменных в Git
5. **Регулярное обновление** Ansible и модулей
6. **Мониторинг** выполнения playbooks через Jenkins
7. **Backup** конфигураций перед изменениями
8. **Документирование** изменений в переменных

## Поддержка

Для получения помощи:

1. Проверьте раздел [Troubleshooting](#troubleshooting)
2. Проверьте логи Ansible
3. Проверьте логи сервисов на целевом сервере
4. Обратитесь к основной документации в `/docs`

## Ссылки

- [Основная документация](../docs/DEPLOYMENT_GUIDE.md)
- [Модель безопасности](../docs/SECURITY_MODEL.md)
- [Инструкция по Vault](../docs/VAULT_SECRETS_GUIDE.md)
- [Ansible Documentation](https://docs.ansible.com/)






