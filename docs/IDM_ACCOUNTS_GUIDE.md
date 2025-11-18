# Руководство по созданию учетных записей в IDM

## Оглавление

1. [Введение](#введение)
2. [Общие сведения об АС СУУПТ (IDM)](#общие-сведения-об-ас-суупт-idm)
3. [Типы учетных записей](#типы-учетных-записей)
4. [Требуемые учетные записи для системы мониторинга](#требуемые-учетные-записи-для-системы-мониторинга)
5. [Создание учетных записей](#создание-учетных-записей)
6. [Настройка прав между УЗ](#настройка-прав-между-уз)
7. [Проверка созданных УЗ](#проверка-созданных-уз)
8. [Управление учетными записями](#управление-учетными-записями)
9. [Устранение неполадок](#устранение-неполадок)

---

## Введение

Данное руководство описывает процесс создания учетных записей Linux через АС СУУПТ (IDM) для безопасной работы системы мониторинга в соответствии с корпоративными требованиями и принципом наименьших привилегий.

### Почему важно правильно настроить УЗ

- **Безопасность**: Разделение полномочий предотвращает несанкционированные действия
- **Аудит**: Каждое действие отслеживается и привязано к конкретному пользователю
- **Отказоустойчивость**: Компрометация одной УЗ не влияет на всю систему
- **Соответствие требованиям**: Выполнение корпоративных политик безопасности

---

## Общие сведения об АС СУУПТ (IDM)

### Что такое IDM

**IDM (Identity Management)** - автоматизированная система управления учетными записями и правами доступа в корпоративной инфраструктуре.

### Доступ к IDM

- **URL**: https://idm.sigma.sbrf.ru
- **Требуется**: Корпоративная учетная запись с правами на создание УЗ Linux
- **Документация**: Инструкция по работе с УЗ Linux (доступна в IDM)

### Основные возможности

- Создание интерактивных и сервисных УЗ Linux
- Управление группами и правами
- Запрос прав sudo
- Аудит действий

---

## Типы учетных записей

### 1. СУЗ (Сервисная учетная запись)

**Назначение**: Запуск системных сервисов и демонов

**Характеристики**:
- Тип: NoLogin (без интерактивного входа)
- Shell: /sbin/nologin или /bin/false
- Используется только для запуска процессов
- Не может войти в систему интерактивно

**Пример**: `monitoring_svc`

### 2. ПУЗ (Привилегированная учетная запись)

**Назначение**: Администрирование системы, просмотр логов, управление сервисами

**Характеристики**:
- Тип: Интерактивная
- Shell: /bin/bash
- Может выполнять команды от имени СУЗ через sudo
- Используется для повседневного обслуживания

**Пример**: `monitoring_admin`

### 3. ТУЗ (Техническая учетная запись)

**Назначение**: Автоматизированный деплой, CI/CD, обновление бинарников

**Характеристики**:
- Тип: Интерактивная
- Shell: /bin/bash
- Права на обновление файлов в /opt/monitoring/bin
- Используется Jenkins/Ansible для развертывания

**Пример**: `monitoring_ci`

### 4. ReadOnly УЗ

**Назначение**: Только чтение конфигураций и логов

**Характеристики**:
- Тип: Интерактивная
- Shell: /bin/bash
- Только права на чтение
- Для аудиторов, разработчиков без прав изменения

**Пример**: `monitoring_ro`

---

## Требуемые учетные записи для системы мониторинга

### Схема разделения полномочий

```
┌─────────────────────────────────────────────────────────────┐
│                  Учетные записи системы                      │
└─────────────────────────────────────────────────────────────┘

┌───────────────────┐
│  monitoring_svc   │  СУЗ (NoLogin)
│  (Service)        │  - Запуск Prometheus, Grafana, Harvest
└─────────┬─────────┘  - Владелец процессов
          │            - Доступ к /dev/shm/monitoring_secrets/
          │
          ├─────────> Может читать: /opt/monitoring/config/
          ├─────────> Может писать: /opt/monitoring/data/
          └─────────> Может писать: /opt/monitoring/logs/

┌───────────────────┐
│ monitoring_admin  │  ПУЗ (Interactive)
│  (Admin)          │  - Управление сервисами
└─────────┬─────────┘  - Просмотр логов
          │            - Перезапуск через systemctl
          │
          ├─────────> Может выполнять: sudo -u monitoring_svc <cmd>
          ├─────────> Может читать: /opt/monitoring/logs/
          └─────────> Может читать: /opt/monitoring/config/

┌───────────────────┐
│  monitoring_ci    │  ТУЗ (Interactive, CI/CD)
│  (Deploy)         │  - Деплой через Jenkins/Ansible
└─────────┬─────────┘  - Обновление бинарников
          │            - Обновление конфигураций
          │
          ├─────────> Может писать: /opt/monitoring/bin/
          ├─────────> Может писать: /opt/monitoring/config/
          ├─────────> Может выполнять: sudo -u monitoring_svc <cmd>
          └─────────> Владелец: /opt/monitoring/

┌───────────────────┐
│  monitoring_ro    │  ReadOnly (Interactive)
│  (ReadOnly)       │  - Только чтение
└─────────┬─────────┘  - Аудит, разработка
          │
          ├─────────> Может читать: /opt/monitoring/config/
          └─────────> Может читать: /opt/monitoring/logs/
```

### Матрица прав доступа

| Каталог/Файл                      | monitoring_svc | monitoring_admin | monitoring_ci | monitoring_ro |
|-----------------------------------|----------------|------------------|---------------|---------------|
| /opt/monitoring/                  | r-x            | r-x              | rwx           | r-x           |
| /opt/monitoring/bin/              | r-x            | r-x              | rwx           | r-x           |
| /opt/monitoring/config/           | r-x            | r-x              | rwx           | r-x           |
| /opt/monitoring/data/             | rwx            | ---              | ---           | ---           |
| /opt/monitoring/logs/             | rwx            | r-x              | ---           | r-x           |
| /dev/shm/monitoring_secrets/      | rwx            | ---              | ---           | ---           |

**Легенда**: r=read, w=write, x=execute, -=нет доступа

---

## Создание учетных записей

### Шаг 1: Вход в IDM

1. Открыть браузер
2. Перейти на https://idm.sigma.sbrf.ru
3. Войти с корпоративной учетной записью
4. Перейти в раздел **"Учетные записи Linux"** или **"Linux Accounts"**

### Шаг 2: Создание СУЗ (monitoring_svc)

#### 2.1. Создание заявки

1. Нажать **"Создать заявку"** или **"New Request"**
2. Выбрать **"Создание учетной записи Linux"**
3. Заполнить форму:

**Основная информация**:
```
Имя УЗ:           monitoring_svc
Тип УЗ:           Сервисная (NoLogin)
Описание:         Сервисная УЗ для запуска сервисов мониторинга (Prometheus, Grafana, Harvest)
Проект/ФП:        <ваш проект>
Целевой сервер:   <IP или FQDN сервера>
```

**Настройки**:
```
Shell:            /sbin/nologin
Home Directory:   /home/monitoring_svc
Primary Group:    monitoring
UID:              <автоматически> или указать явно
```

**Обоснование**:
```
Требуется для запуска сервисов системы мониторинга без возможности 
интерактивного входа в соответствии с принципом наименьших привилегий.
```

#### 2.2. Согласование и создание

1. Нажать **"Отправить на согласование"**
2. Дождаться согласования (обычно 1-3 рабочих дня)
3. После согласования УЗ будет автоматически создана на целевом сервере

### Шаг 3: Создание ПУЗ (monitoring_admin)

#### 3.1. Создание заявки

1. Нажать **"Создать заявку"**
2. Выбрать **"Создание учетной записи Linux"**
3. Заполнить форму:

**Основная информация**:
```
Имя УЗ:           monitoring_admin
Тип УЗ:           Интерактивная (Interactive)
Описание:         Административная УЗ для управления системой мониторинга
Проект/ФП:        <ваш проект>
Целевой сервер:   <IP или FQDN сервера>
```

**Настройки**:
```
Shell:            /bin/bash
Home Directory:   /home/monitoring_admin
Primary Group:    monitoring
Secondary Groups: monitoring_svc (для чтения файлов сервиса)
UID:              <автоматически>
```

**Обоснование**:
```
Требуется для администрирования системы мониторинга: управление сервисами,
просмотр логов, диагностика проблем. Интерактивный вход необходим для
выполнения административных задач.
```

#### 3.2. Согласование

1. Отправить на согласование
2. Дождаться создания УЗ

### Шаг 4: Создание ТУЗ (monitoring_ci)

#### 4.1. Создание заявки

**Основная информация**:
```
Имя УЗ:           monitoring_ci
Тип УЗ:           Техническая (Technical)
Описание:         Техническая УЗ для автоматизированного деплоя через Jenkins/Ansible
Проект/ФП:        <ваш проект>
Целевой сервер:   <IP или FQDN сервера>
```

**Настройки**:
```
Shell:            /bin/bash
Home Directory:   /home/monitoring_ci
Primary Group:    monitoring
Secondary Groups: monitoring_svc
UID:              <автоматически>
```

**SSH ключи**:
```
Добавить публичный SSH-ключ для Jenkins:
- Указать публичный ключ из Jenkins credentials
- Или сгенерировать новый и добавить в Jenkins
```

**Обоснование**:
```
Требуется для автоматизированного развертывания системы мониторинга через 
Jenkins CI/CD pipeline и Ansible. Используется только для деплоя, не для 
интерактивной работы администраторов.
```

### Шаг 5: Создание ReadOnly УЗ (monitoring_ro)

#### 5.1. Создание заявки

**Основная информация**:
```
Имя УЗ:           monitoring_ro
Тип УЗ:           Интерактивная (Interactive)
Описание:         ReadOnly УЗ для просмотра конфигураций и логов
Проект/ФП:        <ваш проект>
Целевой сервер:   <IP или FQDN сервера>
```

**Настройки**:
```
Shell:            /bin/bash
Home Directory:   /home/monitoring_ro
Primary Group:    monitoring_ro
Secondary Groups: (нет)
UID:              <автоматически>
```

**Обоснование**:
```
Требуется для предоставления доступа аудиторам и разработчикам для просмотра
конфигураций и логов без возможности изменения системы.
```

---

## Настройка прав между УЗ

После создания всех УЗ необходимо настроить права для выполнения команд от имени других пользователей.

### Права для monitoring_admin

#### Запрос прав через IDM

1. В IDM перейти в раздел **"Права на серверах Linux"** или **"Linux Server Rights"**
2. Нажать **"Запросить права sudo"**
3. Заполнить форму:

**Основная информация**:
```
Пользователь:     monitoring_admin
Целевой сервер:   <IP или FQDN>
Тип прав:         sudo
```

**Команды**:
```
Разрешить выполнение от имени пользователя monitoring_svc:

monitoring_admin ALL=(monitoring_svc) NOPASSWD: ALL
```

**Обоснование**:
```
Требуется для управления сервисами от имени сервисной УЗ (monitoring_svc),
что необходимо для администрирования системы мониторинга в соответствии
с принципом наименьших привилегий.
```

#### Альтернативный вариант (ограниченные команды)

Если политика безопасности требует явного указания команд:

```bash
monitoring_admin ALL=(monitoring_svc) NOPASSWD: /usr/bin/systemctl --user status *
monitoring_admin ALL=(monitoring_svc) NOPASSWD: /usr/bin/systemctl --user restart *
monitoring_admin ALL=(monitoring_svc) NOPASSWD: /usr/bin/systemctl --user stop *
monitoring_admin ALL=(monitoring_svc) NOPASSWD: /usr/bin/systemctl --user start *
monitoring_admin ALL=(monitoring_svc) NOPASSWD: /usr/bin/journalctl --user *
```

### Права для monitoring_ci

#### Запрос прав через IDM

**Команды**:
```
Разрешить выполнение от имени пользователя monitoring_svc:

monitoring_ci ALL=(monitoring_svc) NOPASSWD: ALL
```

**Обоснование**:
```
Требуется для автоматизированного деплоя системы мониторинга через Jenkins/Ansible.
ТУЗ должна иметь возможность управлять файлами и сервисами от имени СУЗ для
обеспечения корректной установки и обновления компонентов.
```

### Проверка выданных прав

После согласования и выдачи прав проверить их можно следующим образом:

```bash
# Войти под monitoring_admin
ssh monitoring_admin@<server>

# Проверить права sudo
sudo -l

# Должно показать:
# User monitoring_admin may run the following commands on <hostname>:
#     (monitoring_svc) NOPASSWD: ALL

# Проверить выполнение команды
sudo -u monitoring_svc id

# Должно показать:
# uid=<UID>(monitoring_svc) gid=<GID>(monitoring) groups=<GID>(monitoring)
```

---

## Проверка созданных УЗ

### Проверка на целевом сервере

```bash
# Войти на сервер под любой УЗ с правами
ssh <your_user>@<server>

# Проверить наличие УЗ в системе
getent passwd | grep monitoring

# Должно показать:
# monitoring_svc:x:<UID>:<GID>:Monitoring Service Account:/home/monitoring_svc:/sbin/nologin
# monitoring_admin:x:<UID>:<GID>:Monitoring Admin Account:/home/monitoring_admin:/bin/bash
# monitoring_ci:x:<UID>:<GID>:Monitoring CI Account:/home/monitoring_ci:/bin/bash
# monitoring_ro:x:<UID>:<GID>:Monitoring ReadOnly Account:/home/monitoring_ro:/bin/bash

# Проверить группы
getent group | grep monitoring

# Должно показать:
# monitoring:x:<GID>:monitoring_svc,monitoring_admin,monitoring_ci
# monitoring_ro:x:<GID>:monitoring_ro
```

### Проверка домашних каталогов

```bash
# Проверить создание домашних каталогов
ls -la /home/ | grep monitoring

# Должно показать:
# drwx------  monitoring_svc   monitoring   ... monitoring_svc
# drwx------  monitoring_admin monitoring   ... monitoring_admin
# drwx------  monitoring_ci    monitoring   ... monitoring_ci
# drwx------  monitoring_ro    monitoring_ro ... monitoring_ro
```

### Проверка возможности входа

```bash
# Проверка СУЗ (должно запретить вход)
ssh monitoring_svc@<server>
# Ожидается: Permission denied или "This account is currently not available"

# Проверка ПУЗ (должно разрешить вход)
ssh monitoring_admin@<server>
# Ожидается: успешный вход

# Проверка ТУЗ (должно разрешить вход)
ssh monitoring_ci@<server>
# Ожидается: успешный вход

# Проверка ReadOnly (должно разрешить вход)
ssh monitoring_ro@<server>
# Ожидается: успешный вход
```

### Проверка принадлежности к группам

```bash
# Для monitoring_admin
ssh monitoring_admin@<server>
id

# Должно показать:
# uid=<UID>(monitoring_admin) gid=<GID>(monitoring) groups=<GID>(monitoring),<GID2>(monitoring_svc)

# Для monitoring_ci
ssh monitoring_ci@<server>
id

# Должно показать:
# uid=<UID>(monitoring_ci) gid=<GID>(monitoring) groups=<GID>(monitoring),<GID2>(monitoring_svc)
```

---

## Управление учетными записями

### Изменение пароля

```bash
# Для интерактивных УЗ (admin, ci, ro)
# Войти под нужной УЗ
ssh monitoring_admin@<server>

# Сменить пароль
passwd

# Ввести текущий пароль
# Ввести новый пароль дважды
```

### Добавление SSH-ключа

```bash
# Для monitoring_ci (для Jenkins)
ssh monitoring_ci@<server>

# Создать директорию для ключей (если нет)
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Добавить публичный ключ
echo "<публичный_ключ_Jenkins>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Проверить
cat ~/.ssh/authorized_keys
```

### Блокировка УЗ

Если УЗ скомпрометирована, временно заблокировать через IDM:

1. Зайти в IDM
2. Найти УЗ
3. Нажать **"Заблокировать"** или **"Lock"**
4. Указать причину
5. Отправить заявку

Блокировка произойдет автоматически после согласования.

### Удаление УЗ

**ВНИМАНИЕ**: Удаление УЗ приведет к удалению всех файлов в домашнем каталоге!

1. Создать backup важных данных:
```bash
sudo tar -czf /backup/monitoring_<user>_$(date +%Y%m%d).tar.gz /home/monitoring_<user>
```

2. В IDM создать заявку на удаление УЗ
3. Указать причину удаления
4. Дождаться согласования

---

## Устранение неполадок

### УЗ не создана после согласования

**Проблема**: Заявка согласована, но УЗ отсутствует на сервере

**Решение**:
1. Проверить статус заявки в IDM
2. Проверить логи создания УЗ (если доступны)
3. Обратиться в поддержку IDM через ServiceNow
4. Проверить что сервер доступен для IDM (сетевая связность)

### Не удается войти под созданной УЗ

**Проблема**: SSH отказывает в доступе

**Решение**:
```bash
# 1. Проверить что УЗ существует
getent passwd monitoring_admin

# 2. Проверить shell
grep monitoring_admin /etc/passwd
# Должен быть /bin/bash для интерактивных УЗ

# 3. Проверить что УЗ не заблокирована
passwd -S monitoring_admin
# Не должно быть "L" (locked)

# 4. Проверить SSH ключи (если используются)
ls -la /home/monitoring_admin/.ssh/

# 5. Проверить права на домашний каталог
ls -ld /home/monitoring_admin/
# Должен быть: drwx------ monitoring_admin monitoring

# 6. Попробовать вход с паролем (если SSH ключи не работают)
ssh -o PreferredAuthentications=password monitoring_admin@<server>
```

### Права sudo не работают

**Проблема**: `sudo -u monitoring_svc <command>` выдает ошибку

**Решение**:
```bash
# 1. Проверить выданные права
sudo -l

# 2. Проверить файл sudoers
sudo cat /etc/sudoers.d/monitoring_admin

# 3. Проверить синтаксис sudoers
sudo visudo -c

# 4. Если прав нет - повторно запросить через IDM

# 5. Проверить что пользователь monitoring_svc существует
id monitoring_svc
```

### Нет доступа к файлам

**Проблема**: Permission denied при доступе к /opt/monitoring

**Решение**:
```bash
# 1. Проверить владельца и права
ls -la /opt/monitoring/

# 2. Проверить принадлежность к группам
id

# 3. Проверить ACL (если используются)
getfacl /opt/monitoring/

# 4. При необходимости запросить добавление в группу через IDM
```

### УЗ есть, но домашний каталог отсутствует

**Проблема**: УЗ создана, но /home/<user> не существует

**Решение**:
```bash
# Создать вручную (от root или через sudo)
sudo mkdir -p /home/monitoring_admin
sudo chown monitoring_admin:monitoring /home/monitoring_admin
sudo chmod 700 /home/monitoring_admin

# Скопировать базовые конфиги
sudo cp /etc/skel/.bash* /home/monitoring_admin/
sudo chown monitoring_admin:monitoring /home/monitoring_admin/.bash*
```

---

## Дополнительная информация

### Политики паролей

Пароли для УЗ должны соответствовать корпоративным требованиям:
- Минимум 12 символов
- Заглавные и строчные буквы
- Цифры и специальные символы
- Не совпадать с предыдущими 5 паролями
- Срок действия: 90 дней

### Ротация учетных данных

Рекомендуется регулярно:
- Менять пароли (каждые 90 дней)
- Обновлять SSH ключи (каждые 6 месяцев)
- Проверять права sudo (каждый квартал)
- Проводить аудит использования УЗ

### Аудит действий

Все действия под УЗ логируются:
- История команд: ~/.bash_history
- Системные логи: /var/log/secure
- Audit логи: /var/log/audit/audit.log
- Sudo логи: /var/log/sudo.log (если настроено)

### Контакты поддержки

- **IDM Support**: через ServiceNow
- **Документация IDM**: https://wiki.sigma.sbrf.ru/idm
- **Linux Support**: через ServiceNow, категория "Linux"

---

## Чек-лист создания УЗ

- [ ] Создана СУЗ `monitoring_svc` (NoLogin)
- [ ] Создана ПУЗ `monitoring_admin` (Interactive)
- [ ] Создана ТУЗ `monitoring_ci` (Interactive, SSH key)
- [ ] Создана ReadOnly УЗ `monitoring_ro` (Interactive)
- [ ] Все УЗ добавлены в группу `monitoring`
- [ ] Группа `monitoring_ro` создана
- [ ] Запрошены права sudo для `monitoring_admin` → `monitoring_svc`
- [ ] Запрошены права sudo для `monitoring_ci` → `monitoring_svc`
- [ ] Проверен вход под `monitoring_admin`
- [ ] Проверен вход под `monitoring_ci`
- [ ] Проверен вход под `monitoring_ro`
- [ ] Проверено что `monitoring_svc` не позволяет интерактивный вход
- [ ] Проверена работа `sudo -u monitoring_svc id` от `monitoring_admin`
- [ ] Проверена работа `sudo -u monitoring_svc id` от `monitoring_ci`
- [ ] SSH ключ добавлен для `monitoring_ci` (для Jenkins)
- [ ] Домашние каталоги созданы для всех УЗ

**После выполнения всех пунктов можно переходить к настройке файловой системы.**

---

**Конец руководства**

