# Руководство по настройке прав sudo через IDM

## Оглавление

1. [Введение](#введение)
2. [Общие принципы](#общие-принципы)
3. [Структура файла sudoers](#структура-файла-sudoers)
4. [Запрос прав через IDM](#запрос-прав-через-idm)
5. [Установка файла sudoers](#установка-файла-sudoers)
6. [Проверка прав sudo](#проверка-прав-sudo)
7. [Описание предоставленных прав](#описание-предоставленных-прав)
8. [Безопасность и аудит](#безопасность-и-аудит)
9. [Устранение неполадок](#устранение-неполадок)

---

## Введение

Данное руководство описывает процесс запроса и настройки прав sudo для системы мониторинга в соответствии с корпоративными требованиями безопасности.

### Ключевые требования

✅ **Явное указание команд** - без переменных и звездочек  
✅ **Полные пути** - все команды с абсолютными путями  
✅ **Экранирование** - специальные символы экранированы (например: `root\:grafana`)  
✅ **NOPASSWD** - команды выполняются без запроса пароля  
✅ **Минимальный набор** - только необходимые команды  

---

## Общие принципы

### Принцип наименьших привилегий

Каждой учетной записи предоставляются только те права, которые необходимы для выполнения её функций:

- **monitoring_ci** - права для деплоя и управления сервисами
- **monitoring_admin** - права для администрирования и диагностики
- **monitoring_ro** - только просмотр статуса и логов

### Требования к файлу sudoers

Согласно корпоративным требованиям:

1. **Без переменных окружения**
   ```bash
   # ПЛОХО:
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart $SERVICE
   
   # ХОРОШО:
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart prometheus
   ```

2. **Без звездочек (wildcards)**
   ```bash
   # ПЛОХО:
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart *
   
   # ХОРОШО:
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart prometheus
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart grafana
   ```

3. **Полные пути команд**
   ```bash
   # ПЛОХО:
   ALL=(ALL:ALL) NOPASSWD: systemctl restart prometheus
   
   # ХОРОШО:
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl restart prometheus
   ```

4. **Экранирование специальных символов**
   ```bash
   # Двоеточие в группах:
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/chown root\:grafana /path/to/file
   
   # Скобки и другие символы также экранируются при необходимости
   ```

5. **Явные аргументы**
   ```bash
   # ПЛОХО (общая команда):
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod
   
   # ХОРОШО (конкретные аргументы):
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 700 /dev/shm/monitoring_secrets
   ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 600 /dev/shm/monitoring_secrets/server.key
   ```

6. **Флаг NOEXEC для команд просмотра**
   ```bash
   # Для команд, которые могут запускать пейджер (less, more):
   ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus
   ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/journalctl --user -u prometheus
   
   # NOEXEC предотвращает выполнение команд через пейджер (например, !sh в less)
   # Это критично для безопасности при использовании команд просмотра статуса
   ```

### Логика без учета логина

Согласно требованиям, права вводятся без учета конкретного логина:

```bash
# Формат:
ALL=(ALL:ALL) NOPASSWD: /usr/bin/<команда> <аргументы>

# Где:
# ALL - применяется для всех хостов
# (ALL:ALL) - запуск от любого пользователя:группы
# NOPASSWD - без запроса пароля
```

---

## Структура файлов sudoers

### Расположение файлов

Для системы мониторинга созданы **отдельные файлы sudoers для каждого пользователя**:

```
sudoers/
├── monitoring_ci       # ТУЗ - Техническая УЗ для CI/CD деплоя
├── monitoring_admin    # ПУЗ - Привилегированная УЗ для администрирования
├── monitoring_ro       # ReadOnly - УЗ только для чтения
├── monitoring_svc      # СУЗ - Сервисная УЗ (НЕ имеет sudo прав!)
└── monitoring_system   # Устаревший единый файл (для обратной совместимости)
```

После запроса через IDM они будут размещены в:
```
/etc/sudoers.d/monitoring_ci
/etc/sudoers.d/monitoring_admin
/etc/sudoers.d/monitoring_ro
```

**ВАЖНО**: Файл `monitoring_svc` **НЕ нужно** размещать в `/etc/sudoers.d/`, так как сервисная УЗ не имеет и не требует sudo прав!

### Преимущества раздельных файлов

✅ **Гранулярность**: Каждый пользователь имеет свой собственный файл  
✅ **Безопасность**: Легче контролировать и аудитировать права  
✅ **Сортировка**: Все команды отсортированы по алфавиту  
✅ **Управление**: Проще добавлять/удалять права конкретному пользователю  
✅ **IDM**: Отдельные заявки на каждого пользователя  

### Сравнение файлов по правам

| Файл | Пользователь | Количество команд | Назначение |
|------|-------------|-------------------|------------|
| `monitoring_ci` | ТУЗ | ~90 команд | Деплой, управление сервисами, создание структуры |
| `monitoring_admin` | ПУЗ | ~35 команд | Администрирование, диагностика, просмотр логов |
| `monitoring_ro` | ReadOnly | ~15 команд | Только просмотр статуса и логов |
| `monitoring_svc` | СУЗ | **0 команд** | **НЕ имеет sudo прав** (NoLogin пользователь) |

### Пример структуры файла (monitoring_ci)

```bash
# ==============================================================================
# ПЕРЕКЛЮЧЕНИЕ НА ДРУГОГО ПОЛЬЗОВАТЕЛЯ
# ==============================================================================

monitoring_ci ALL=(monitoring_svc) NOPASSWD: ALL

# ==============================================================================
# УПРАВЛЕНИЕ ПРАВАМИ НА ДИРЕКТОРИИ (отсортировано по алфавиту)
# ==============================================================================

monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 640 /dev/shm/monitoring_secrets/ca_chain.crt
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 640 /dev/shm/monitoring_secrets/client.crt
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 640 /dev/shm/monitoring_secrets/grafana-client.crt
...

# ==============================================================================
# УПРАВЛЕНИЕ ВЛАДЕЛЬЦАМИ ФАЙЛОВ И ДИРЕКТОРИЙ (отсортировано по алфавиту)
# ==============================================================================

monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chown -R monitoring_ci:monitoring /opt/monitoring/bin
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chown -R monitoring_ci:monitoring /opt/monitoring/config
...

# ==============================================================================
# УПРАВЛЕНИЕ USER SYSTEMD UNITS (отсортировано по алфавиту)
# ==============================================================================

monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user daemon-reload
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable grafana
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable harvest
monitoring_ci ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status grafana
...
```

---

## Запрос прав через IDM

### Шаг 1: Подготовка файлов sudoers

**Новый подход (рекомендуется)**: Использовать отдельные файлы для каждого пользователя

1. Взять соответствующие файлы из проекта:
   - `sudoers/monitoring_ci` - для ТУЗ (CI/CD)
   - `sudoers/monitoring_admin` - для ПУЗ (администратор)
   - `sudoers/monitoring_ro` - для ReadOnly
   
2. Проверить актуальность всех команд и путей
3. Убедиться что все специальные символы экранированы

**Старый подход (для обратной совместимости)**: Использовать единый файл `sudoers/monitoring_system`

### Шаг 2: Создание заявок в IDM

**ВАРИАНТ A: Отдельные заявки для каждого пользователя (рекомендуется)**

Создать **3 отдельные заявки** в IDM:

#### Заявка 1: monitoring_ci

1. **Зайти в IDM**: https://idm.sigma.sbrf.ru
2. **Перейти в раздел**: "Права на серверах Linux" / "Linux Server Rights"
3. **Создать новую заявку**: "Запросить права sudo"
4. **Заполнить основную информацию**:
   ```
   Тип заявки:       Предоставление прав sudo
   Целевой сервер:   <IP или FQDN вашего сервера>
   Проект/ФП:        <ваш проект>
   ```
5. **Приложить файл**: `sudoers/monitoring_ci`
6. **Указать пользователя**: `monitoring_ci`
7. **Обоснование**:
   ```
   Требуется для автоматизированного развертывания системы мониторинга 
   через Jenkins/Ansible. Права включают управление user systemd units, 
   создание структуры каталогов, управление секретами в /dev/shm.
   Соответствует принципу наименьших привилегий.
   ```

#### Заявка 2: monitoring_admin

1. **Создать новую заявку** (аналогично заявке 1)
2. **Приложить файл**: `sudoers/monitoring_admin`
3. **Указать пользователя**: `monitoring_admin`
4. **Обоснование**:
   ```
   Требуется для администрирования системы мониторинга: управление 
   сервисами, диагностика, просмотр логов, создание бэкапов.
   Соответствует принципу наименьших привилегий.
   ```

#### Заявка 3: monitoring_ro

1. **Создать новую заявку** (аналогично заявке 1)
2. **Приложить файл**: `sudoers/monitoring_ro`
3. **Указать пользователя**: `monitoring_ro`
4. **Обоснование**:
   ```
   Требуется для аудита и мониторинга: только просмотр статуса сервисов 
   и логов без возможности изменения. Минимальный набор прав.
   ```

**ВАЖНО**: Для `monitoring_svc` заявку **НЕ создавать** - сервисная УЗ не имеет и не требует sudo прав!

---

**ВАРИАНТ B: Единая заявка для всех пользователей (legacy)**

1. **Зайти в IDM**: https://idm.sigma.sbrf.ru
2. **Перейти в раздел**: "Права на серверах Linux" / "Linux Server Rights"
3. **Создать новую заявку**: "Запросить права sudo"
4. **Заполнить основную информацию**:
   ```
   Тип заявки:       Предоставление прав sudo
   Целевой сервер:   <IP или FQDN вашего сервера>
   Проект/ФП:        <ваш проект>
   ```
5. **Приложить файл**: `sudoers/monitoring_system`
6. **Указать пользователей**:
   ```
   - monitoring_ci
   - monitoring_admin
   - monitoring_ro
   ```
7. **Обоснование**:
   ```
   Требуется для безопасного развертывания и обслуживания системы 
   мониторинга (Prometheus + Grafana + Harvest) в соответствии с 
   принципом наименьших привилегий и корпоративными требованиями 
   безопасности.
   
   Все команды указаны явно без переменных и звездочек, используются 
   только абсолютные пути, применен принцип минимальных необходимых 
   прав для каждой УЗ.
   
   Файл sudoers проверен на синтаксис и соответствие требованиям 
   службы безопасности.
   ```

8. **Детализация по типам УЗ**:
   
   **monitoring_ci (ТУЗ)**:
   ```
   Требуются права для:
   - Автоматизированного деплоя через Jenkins/Ansible
   - Управления user systemd units
   - Создания структуры каталогов
   - Размещения секретов в /dev/shm
   - Управления правами на файлы конфигураций
   ```
   
   **monitoring_admin (ПУЗ)**:
   ```
   Требуются права для:
   - Администрирования сервисов (start, stop, restart)
   - Просмотра статуса и логов
   - Диагностики проблем
   - Создания резервных копий конфигураций
   ```
   
   **monitoring_ro (ReadOnly)**:
   ```
   Требуются права для:
   - Просмотра статуса сервисов (без управления)
   - Чтения логов
   - Диагностики (без изменений)
   ```

### Шаг 3: Согласование заявки

1. **Отправить на согласование**: Нажать "Отправить"

2. **Ожидание согласования**:
   - Заявка пройдет несколько этапов согласования
   - Служба безопасности проверит соответствие требованиям
   - Обычное время: 3-5 рабочих дней

3. **Возможные запросы**:
   - Могут запросить дополнительное обоснование
   - Могут попросить уточнить некоторые команды
   - Могут предложить альтернативные подходы

4. **Внесение изменений** (если требуется):
   - Внести правки в файл sudoers
   - Обновить приложенный файл в заявке
   - Добавить комментарии по изменениям

### Шаг 4: Автоматическое применение

После согласования:
- Файл sudoers автоматически размещается на целевом сервере
- Путь: `/etc/sudoers.d/monitoring_system`
- Права применяются немедленно
- Уведомление приходит на email

---

## Установка файла sudoers

### Автоматическая установка (через IDM)

После согласования заявки в IDM файл устанавливается автоматически:

```bash
# Файл будет размещен по пути:
/etc/sudoers.d/monitoring_system

# С правами:
-r--r----- root root monitoring_system

# И автоматически подключен к основному /etc/sudoers
```

### Ручная установка (для тестирования)

**ВНИМАНИЕ**: Только для тестовых/dev серверов!

```bash
# 1. Скопировать файл на сервер
scp sudoers/monitoring_system <user>@<server>:/tmp/

# 2. Проверить синтаксис
sudo visudo -c -f /tmp/monitoring_system

# Должно показать: /tmp/monitoring_system: parsed OK

# 3. Установить файл
sudo cp /tmp/monitoring_system /etc/sudoers.d/monitoring_system
sudo chmod 440 /etc/sudoers.d/monitoring_system
sudo chown root:root /etc/sudoers.d/monitoring_system

# 4. Проверить что файл подключен
sudo visudo -c

# Должно показать: /etc/sudoers: parsed OK

# 5. Удалить временный файл
rm /tmp/monitoring_system
```

### Проверка синтаксиса перед установкой

```bash
# Всегда проверяйте синтаксис перед установкой!
sudo visudo -c -f /path/to/monitoring_system

# Возможные ошибки:
# - "syntax error" - ошибка в синтаксисе
# - "parse error" - неправильный формат
# - "unknown user" - пользователь не существует

# Пример вывода при успехе:
# /path/to/monitoring_system: parsed OK
```

---

## Проверка прав sudo

### Проверка для monitoring_ci

```bash
# Войти под monitoring_ci
ssh monitoring_ci@<server>

# Посмотреть все доступные права
sudo -l

# Должно показать список всех команд из файла sudoers

# Проверить конкретные права:

# 1. Переключение на monitoring_svc
sudo -u monitoring_svc id
# Ожидается: uid=<UID>(monitoring_svc) gid=<GID>(monitoring) ...

# 2. Управление systemd units
sudo systemctl --user daemon-reload
sudo systemctl --user status prometheus
# Не должно быть ошибок

# 3. Создание директории в /dev/shm
sudo mkdir -p /dev/shm/test_monitoring
sudo chmod 700 /dev/shm/test_monitoring
sudo rmdir /dev/shm/test_monitoring
# Должно выполниться без ошибок

# 4. Управление правами
sudo chmod 600 /tmp/test_file 2>/dev/null || echo "OK (файл не существует)"
```

### Проверка для monitoring_admin

```bash
# Войти под monitoring_admin
ssh monitoring_admin@<server>

# Посмотреть доступные права
sudo -l

# Проверить управление сервисами:
sudo systemctl --user status prometheus
sudo systemctl --user restart prometheus
# Не должно быть ошибок Permission denied

# Проверить просмотр логов:
sudo journalctl --user -u prometheus -n 10
# Должны показаться логи

# Проверить переключение на monitoring_svc
sudo -u monitoring_svc id
# Должно работать
```

### Проверка для monitoring_ro

```bash
# Войти под monitoring_ro
ssh monitoring_ro@<server>

# Посмотреть доступные права
sudo -l

# Проверить просмотр статуса (должно работать):
sudo systemctl --user status prometheus
sudo journalctl --user -u prometheus -n 10

# Попытаться перезапустить (НЕ должно работать):
sudo systemctl --user restart prometheus
# Ожидается: Sorry, user monitoring_ro is not allowed to execute ...
```

### Автоматический скрипт проверки

```bash
#!/bin/bash
# Скрипт проверки прав sudo

echo "=== Проверка прав sudo для системы мониторинга ==="
echo

CURRENT_USER=$(whoami)
echo "Текущий пользователь: $CURRENT_USER"
echo

echo "Доступные права sudo:"
sudo -l
echo

# Проверка переключения на monitoring_svc
echo "Проверка переключения на monitoring_svc:"
if sudo -u monitoring_svc id 2>/dev/null; then
    echo "✓ Переключение работает"
else
    echo "✗ Ошибка переключения"
fi
echo

# Проверка systemctl
echo "Проверка systemctl commands:"
if sudo systemctl --user daemon-reload 2>/dev/null; then
    echo "✓ daemon-reload работает"
else
    echo "✗ daemon-reload не работает"
fi
echo

echo "=== Проверка завершена ==="
```

Сохранить как `/opt/monitoring/scripts/verify_sudo.sh` и запустить:

```bash
chmod +x /opt/monitoring/scripts/verify_sudo.sh
./opt/monitoring/scripts/verify_sudo.sh
```

---

## Описание предоставленных прав

### Права monitoring_ci

#### 1. Переключение на monitoring_svc
```bash
monitoring_ci ALL=(monitoring_svc) NOPASSWD: ALL
```
**Назначение**: Выполнение любых команд от имени сервисной УЗ  
**Использование**: `sudo -u monitoring_svc <команда>`  
**Пример**: `sudo -u monitoring_svc systemctl --user start prometheus`

#### 2. Управление user systemd units
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user daemon-reload
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable prometheus
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start prometheus
...
```
**Назначение**: Управление сервисами в пространстве пользователя  
**Использование**: Деплой, перезапуск, включение автозапуска  
**Сервисы**: prometheus, grafana, harvest, vault-agent-monitoring

#### 3. Управление /dev/shm для секретов
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/mkdir -p /dev/shm/monitoring_secrets
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 700 /dev/shm/monitoring_secrets
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chown monitoring_svc\:monitoring /dev/shm/monitoring_secrets
```
**Назначение**: Создание и настройка безопасного хранилища секретов в tmpfs  
**Использование**: Размещение сертификатов и паролей в RAM (не на диске)

#### 4. Управление правами на файлы секретов
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 600 /dev/shm/monitoring_secrets/server.key
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 640 /dev/shm/monitoring_secrets/server.crt
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chown monitoring_svc\:monitoring /dev/shm/monitoring_secrets/server.key
...
```
**Назначение**: Настройка правильных прав доступа на сертификаты  
**Использование**: Защита приватных ключей (600), публичных сертификатов (640)

#### 5. Создание структуры каталогов
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/mkdir -p /opt/monitoring/bin
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/mkdir -p /opt/monitoring/config
...
```
**Назначение**: Первоначальное создание структуры проекта  
**Использование**: Деплой при первой установке

#### 6. Управление правами на директории
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chmod 750 /opt/monitoring/bin
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/chown -R monitoring_ci\:monitoring /opt/monitoring/bin
...
```
**Назначение**: Настройка правильного разделения полномочий  
**Использование**: Установка владельцев и прав согласно матрице доступа

#### 7. Копирование конфигурационных файлов
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/cp /home/monitoring_ci/deployment/config/prometheus.yml /opt/monitoring/config/prometheus.yml
...
```
**Назначение**: Развертывание конфигураций  
**Использование**: Обновление конфигов при деплое

#### 8. Диагностика
```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/journalctl --user -u prometheus
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/ss -tlnp
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/sbin/lsof -i TCP\:9090
```
**Назначение**: Проверка статуса и диагностика проблем при деплое  
**Использование**: Автоматическая верификация после установки

### Права monitoring_admin

#### 1. Переключение на monitoring_svc
```bash
monitoring_admin ALL=(monitoring_svc) NOPASSWD: ALL
```
**Назначение**: Выполнение административных задач от имени сервисной УЗ  
**Использование**: Ручное управление и диагностика

#### 2. Управление сервисами
```bash
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start prometheus
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user stop prometheus
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user restart prometheus
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status prometheus
```
**Назначение**: Повседневное администрирование сервисов  
**Использование**: Перезапуск при проблемах, проверка статуса  
**Ограничения**: Нет прав на enable/disable (чтобы предотвратить изменение автозапуска)

#### 3. Просмотр логов
```bash
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/journalctl --user -u prometheus
```
**Назначение**: Диагностика проблем  
**Использование**: Анализ ошибок, мониторинг работы

#### 4. Диагностические команды
```bash
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/ss -tlnp
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/sbin/lsof -i TCP\:9090
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/ps aux
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/df -h
```
**Назначение**: Диагностика сети, процессов, дискового пространства  
**Использование**: Поиск проблем с портами, производительностью

#### 5. Создание бэкапов
```bash
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/tar -czf /opt/monitoring/backups/config_*.tar.gz /opt/monitoring/config/
```
**Назначение**: Резервное копирование конфигураций  
**Использование**: Перед изменениями, регулярные бэкапы

### Права monitoring_ro

#### 1. Просмотр статуса (без управления)
```bash
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status prometheus
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user is-active prometheus
```
**Назначение**: Только чтение состояния сервисов  
**Ограничения**: НЕТ прав на start/stop/restart

#### 2. Просмотр логов
```bash
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/journalctl --user -u prometheus
```
**Назначение**: Чтение логов для аудита или разработки  
**Ограничения**: Только чтение, без изменений

#### 3. Диагностика (только просмотр)
```bash
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/ss -tlnp
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/ps aux
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/df -h
```
**Назначение**: Просмотр состояния системы  
**Ограничения**: Только команды чтения, без возможности изменений

---

## Безопасность и аудит

### Логирование sudo команд

Все команды выполненные через sudo логируются:

```bash
# Просмотр sudo логов
sudo journalctl -t sudo

# Или в файле (если настроено)
sudo tail -f /var/log/secure | grep sudo

# Формат записи:
# <timestamp> <hostname> sudo: <user> : TTY=<tty> ; PWD=<pwd> ; USER=<target_user> ; COMMAND=<command>
```

### Аудит использования прав

Регулярно проверять использование sudo:

```bash
# За последние 24 часа
sudo journalctl -t sudo --since "24 hours ago"

# От конкретного пользователя
sudo journalctl -t sudo | grep "monitoring_ci"

# Конкретные команды
sudo journalctl -t sudo | grep "systemctl"
```

### Ротация прав

Рекомендуется периодически пересматривать предоставленные права:

- **Ежеквартально**: Проверка актуальности прав
- **При изменении архитектуры**: Обновление файла sudoers
- **При обнаружении проблем**: Ужесточение или уточнение прав

### Реагирование на инциденты

При обнаружении злоупотребления правами:

1. **Временная блокировка**:
   ```bash
   # Закомментировать права в /etc/sudoers.d/monitoring_system
   sudo visudo -f /etc/sudoers.d/monitoring_system
   ```

2. **Блокировка УЗ** через IDM (см. IDM_ACCOUNTS_GUIDE.md)

3. **Анализ логов** для определения масштаба инцидента

4. **Восстановление** после устранения угрозы

---

## Устранение неполадок

### Права sudo не работают после установки

**Проблема**: `sudo: command not found in sudoers`

**Решение**:
```bash
# 1. Проверить что файл установлен
ls -la /etc/sudoers.d/monitoring_system

# 2. Проверить права на файл
# Должны быть: -r--r----- root root

# 3. Проверить синтаксис
sudo visudo -c -f /etc/sudoers.d/monitoring_system

# 4. Проверить что директория sudoers.d подключена
sudo grep "sudoers.d" /etc/sudoers
# Должна быть строка: #includedir /etc/sudoers.d

# 5. Проверить текущего пользователя
whoami
# Должен совпадать с УЗ в sudoers файле

# 6. Обновить список прав
sudo -k  # Сбросить кэш sudo
sudo -l  # Перечитать права
```

### Ошибка "syntax error" в sudoers

**Проблема**: При проверке показывает ошибку синтаксиса

**Решение**:
```bash
# 1. Проверить детальную информацию об ошибке
sudo visudo -c -f /path/to/monitoring_system

# Покажет строку с ошибкой

# 2. Частые ошибки:

# Неправильное экранирование:
# ПЛОХО: chown root:grafana
# ХОРОШО: chown root\:grafana

# Неполный путь:
# ПЛОХО: systemctl restart prometheus
# ХОРОШО: /usr/bin/systemctl restart prometheus

# Лишние пробелы или табы:
# Проверить что между элементами один пробел

# 3. Исправить и проверить снова
sudo visudo -c -f /path/to/monitoring_system
```

### Команда не выполняется несмотря на права в sudoers

**Проблема**: Права есть в `sudo -l`, но команда не выполняется

**Решение**:
```bash
# 1. Проверить точное совпадение команды
sudo -l
# Сравнить с тем, что вы выполняете

# Пример:
# В sudoers: /usr/bin/systemctl --user restart prometheus
# Выполняете: sudo systemctl restart prometheus
# НЕ СОВПАДАЕТ - нет --user

# 2. Проверить порядок аргументов
# Должен точно совпадать с sudoers

# 3. Проверить путь к команде
which systemctl
# Должен совпадать с путем в sudoers (/usr/bin/systemctl)

# 4. Проверить что команда существует
ls -la /usr/bin/systemctl

# 5. Попробовать выполнить с полным путем
sudo /usr/bin/systemctl --user restart prometheus
```

### Не работает переключение на другого пользователя

**Проблема**: `sudo -u monitoring_svc` не работает

**Решение**:
```bash
# 1. Проверить что пользователь существует
id monitoring_svc

# 2. Проверить права в sudoers
sudo -l | grep monitoring_svc

# Должно быть:
# (monitoring_svc) NOPASSWD: ALL

# 3. Проверить синтаксис переключения
# ПРАВИЛЬНО:
sudo -u monitoring_svc id
sudo -u monitoring_svc bash

# 4. Для NoLogin пользователей использовать:
sudo -u monitoring_svc -s /bin/bash
```

### Права запрошены, но заявка отклонена

**Проблема**: Заявка в IDM отклонена службой безопасности

**Возможные причины и решения**:

1. **Слишком широкие права**
   - Уточнить права, убрать лишние команды
   - Обосновать каждую команду

2. **Использование переменных или звездочек**
   - Переписать все команды явно
   - Убрать все wildcards

3. **Недостаточное обоснование**
   - Детально описать для чего нужна каждая команда
   - Приложить архитектурную схему

4. **Деструктивные команды**
   - Пересмотреть необходимость команд типа `rm`, `kill`
   - Предложить альтернативный подход

### Обновление файла sudoers

**Задача**: Нужно добавить новые команды или изменить существующие

**Процесс**:

1. **Обновить локальный файл**:
   ```bash
   vim sudoers/monitoring_system
   # Внести изменения
   ```

2. **Проверить синтаксис**:
   ```bash
   sudo visudo -c -f sudoers/monitoring_system
   ```

3. **Создать новую заявку в IDM**:
   - Указать что это обновление существующих прав
   - Приложить новый файл
   - Описать что изменилось и почему

4. **Дождаться согласования**

5. **После применения проверить**:
   ```bash
   sudo -l
   # Должны появиться новые команды
   ```

---

## Полезные команды

### Просмотр текущих прав

```bash
# Все доступные команды
sudo -l

# В развернутом виде
sudo -l -l

# Для конкретного пользователя (от root)
sudo -U monitoring_ci -l
```

### Тестирование команды без выполнения

```bash
# Проверить можно ли выполнить команду
sudo -n <команда>

# Если можно - выполнится
# Если нельзя - ошибка без запроса пароля
```

### Просмотр sudoers файлов

```bash
# Основной файл
sudo cat /etc/sudoers

# Дополнительные файлы
sudo ls -la /etc/sudoers.d/

# Конкретный файл
sudo cat /etc/sudoers.d/monitoring_system
```

### Проверка логов sudo

```bash
# Все логи sudo
sudo journalctl -t sudo

# За последний час
sudo journalctl -t sudo --since "1 hour ago"

# От конкретного пользователя
sudo journalctl -t sudo | grep monitoring_ci

# Только ошибки
sudo journalctl -t sudo -p err
```

---

## Чек-лист настройки sudo

- [ ] Файл `sudoers/monitoring_system` подготовлен
- [ ] Синтаксис проверен: `sudo visudo -c -f sudoers/monitoring_system`
- [ ] Все команды указаны с полными путями
- [ ] Все переменные заменены на явные значения
- [ ] Все звездочки заменены на конкретные команды
- [ ] Специальные символы экранированы (`:` → `\:`)
- [ ] Заявка создана в IDM
- [ ] Файл sudoers приложен к заявке
- [ ] Обоснование написано
- [ ] Заявка согласована
- [ ] Права проверены: `sudo -l`
- [ ] Тестовые команды выполнены успешно
- [ ] Документация обновлена

**После выполнения всех пунктов права sudo настроены корректно.**

---

**Конец руководства**


