# Безопасное развертывание системы мониторинга

## Описание проекта

Данный проект представляет собой безопасное решение для развертывания системы мониторинга (Prometheus + Grafana + Harvest) в корпоративной среде Enterprise со строгой ролевой моделью и соблюдением всех требований безопасности банка.

## Ключевые особенности

✅ **Соответствие корпоративным требованиям безопасности**
- Работа с непривилегированными пользователями
- Использование User Systemd Units
- Минимальный набор прав sudo
- Секреты хранятся в `/dev/shm` (tmpfs в RAM)

✅ **Разделение полномочий**
- 4 типа учетных записей (СУЗ, ПУЗ, ТУЗ, ReadOnly)
- Раздельные директории для bin, config, data, logs
- Принцип наименьших привилегий

✅ **Автоматизация**
- Jenkins Pipeline для CI/CD
- Ansible playbooks для управления конфигурацией
- Интеграция с RLM для установки ПО
- Vault Agent для управления секретами

✅ **Безопасность**
- Явные права sudo без переменных и звездочек
- Автоматическая ротация секретов
- Защита от эскалации привилегий
- Аудит всех операций

## Структура проекта

```
secure_deployment/
├── README.md                          # Этот файл
├── docs/                              # Документация
│   ├── DEPLOYMENT_GUIDE.md            # Руководство по развертыванию
│   ├── IDM_ACCOUNTS_GUIDE.md          # Создание учетных записей в IDM
│   ├── SUDOERS_GUIDE.md               # Настройка прав sudo
│   ├── SECURITY_MODEL.md              # Схема безопасности
│   ├── VAULT_SECRETS_GUIDE.md         # Работа с секретами Vault
│   └── FILESYSTEM_STRUCTURE.md        # Структура файловой системы
├── scripts/                           # Скрипты развертывания
│   ├── deploy_monitoring_secure.sh    # Главный скрипт развертывания
│   ├── setup_vault_agent.sh           # Настройка Vault Agent
│   ├── manage_secrets.sh              # Управление секретами
│   ├── cleanup_secrets.sh             # Очистка секретов
│   └── verify_security.sh             # Проверка безопасности
├── ansible/                           # Ansible проект
│   ├── ansible.cfg                    # Конфигурация Ansible
│   ├── inventories/                   # Инвентори
│   ├── playbooks/                     # Playbooks
│   ├── roles/                         # Роли
│   └── group_vars/                    # Переменные групп
├── systemd/                           # User systemd units
│   ├── prometheus.service
│   ├── grafana.service
│   ├── harvest.service
│   └── vault-agent-monitoring.service
├── config/                            # Конфигурационные файлы
│   ├── vault-agent.hcl                # Конфигурация Vault Agent
│   ├── prometheus.yml                 # Конфигурация Prometheus
│   ├── grafana.ini                    # Конфигурация Grafana
│   └── harvest.yml                    # Конфигурация Harvest
├── sudoers/                           # Файлы sudoers
│   └── monitoring_system              # Явные права sudo
└── Jenkinsfile                        # Jenkins Pipeline

```

## Быстрый старт

### Предварительные требования

1. **Учетные записи в IDM** - см. [IDM_ACCOUNTS_GUIDE.md](docs/IDM_ACCOUNTS_GUIDE.md)
2. **Файловая система через RLM** - 7GB минимум
3. **Права sudo через IDM** - см. [SUDOERS_GUIDE.md](docs/SUDOERS_GUIDE.md)
4. **Vault AppRole** - role_id и secret_id для доступа к Vault
5. **Jenkins** - настроенный с нужными credentials

### Порядок развертывания

1. **Подготовка учетных записей**
   ```bash
   # Создать УЗ в IDM согласно IDM_ACCOUNTS_GUIDE.md
   - monitoring_svc (NoLogin) - СУЗ
   - monitoring_admin - ПУЗ
   - monitoring_ci - ТУЗ
   - monitoring_ro - ReadOnly
   ```

2. **Создание файловой системы через RLM**
   ```bash
   # Через RLM создать ФС с владельцем monitoring_ci
   /opt/monitoring - 7GB
   ```

3. **Настройка прав sudo**
   ```bash
   # Запросить права через IDM согласно sudoers/monitoring_system
   ```

4. **Запуск через Jenkins**
   ```bash
   # Запустить Jenkins Pipeline с параметрами
   ```

Или **вручную через Ansible**:
   ```bash
   cd ansible
   ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml
   ```

## Документация

Полная документация находится в директории [docs/](docs/):

1. **[DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)** - Подробное руководство по развертыванию
2. **[IDM_ACCOUNTS_GUIDE.md](docs/IDM_ACCOUNTS_GUIDE.md)** - Создание и настройка УЗ в IDM
3. **[SUDOERS_GUIDE.md](docs/SUDOERS_GUIDE.md)** - Настройка прав sudo через IDM
4. **[SECURITY_MODEL.md](docs/SECURITY_MODEL.md)** - Модель безопасности и разделение полномочий
5. **[VAULT_SECRETS_GUIDE.md](docs/VAULT_SECRETS_GUIDE.md)** - Работа с секретами через Vault Agent
6. **[FILESYSTEM_STRUCTURE.md](docs/FILESYSTEM_STRUCTURE.md)** - Структура каталогов и права доступа

## Компоненты системы

### Мониторинг
- **Prometheus** - сбор и хранение метрик (порт 9090)
- **Grafana** - визуализация метрик (порт 3000)
- **Harvest** - сбор метрик с NetApp (порты 12990, 12991)

### Безопасность
- **Vault Agent** - управление секретами и сертификатами
- **mTLS** - взаимная аутентификация между компонентами
- **User Systemd** - сервисы в пространстве пользователя

### Автоматизация
- **Jenkins** - CI/CD pipeline
- **Ansible** - управление конфигурацией
- **RLM** - установка RPM пакетов

## Поддержка и обслуживание

### Мониторинг статуса
```bash
# От пользователя monitoring_admin
systemctl --user status prometheus
systemctl --user status grafana
systemctl --user status harvest
```

### Обновление конфигурации
```bash
# Через Ansible
cd ansible
ansible-playbook -i inventories/production playbooks/update_config.yml
```

### Ротация секретов
```bash
# Автоматически через Vault Agent
# Или вручную:
/opt/monitoring/scripts/rotate_secrets.sh
```

## Отличия от старого решения

| Аспект | Старое решение | Новое решение |
|--------|----------------|---------------|
| Права | Требует root/sudo для всего | Непривилегированные УЗ + минимум sudo |
| Systemd | System units в /etc | User units в ~/.config/systemd/user |
| Файлы | /etc, /var, /usr | /opt/monitoring + домашние каталоги |
| Секреты | Файлы на диске | /dev/shm (tmpfs в RAM) |
| Учетные записи | root + УЗ от пакетов | 4 УЗ с разделением полномочий |
| Права доступа | 777, chmod -R | Точные права по принципу наименьших привилегий |
| Sudoers | Широкие права с переменными | Явные команды без переменных |

## Соответствие требованиям безопасности

✅ Использование только ПО из портала ДИ  
✅ Обслуживание через RLM  
✅ Скрипты самообслуживания  
✅ Принцип наименьших полномочий  
✅ Непривилегированные пользователи  
✅ Отдельная ФС с правами прикладного пользователя  
✅ User systemd units  
✅ Безопасное хранение секретов в /dev/shm  
✅ Правильное разделение полномочий  
✅ Явные права sudo без переменных  
✅ Минимизация деструктивных команд  

## Контакты и поддержка

При возникновении вопросов обращайтесь к документации в директории `docs/`.

## Лицензия

Внутреннее использование в корпоративной среде.


