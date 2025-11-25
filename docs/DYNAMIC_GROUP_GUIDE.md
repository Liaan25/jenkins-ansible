# Руководство: Динамическая группа (Группа = СУЗ)

**Дата**: 19.11.2024  
**Версия**: 2.2  
**Статус**: ✅ Production Ready

---

## 📋 Концепция

В системе используется **динамическая группа**, которая равна имени **сервисного пользователя (СУЗ)**.

### Почему группа = СУЗ?

✅ **Автоматическое создание** - IDM создает группу при создании пользователя  
✅ **Изоляция стендов** - каждый стенд имеет свою уникальную группу  
✅ **Простота управления** - не нужно создавать отдельную группу  
✅ **Безопасность** - членство контролируется через IDM  
✅ **Стандартная практика** - так делается в Enterprise Linux  

---

## 🎯 Схема для стенда

### Пример для NAMESPACE_CI = "CI04523276_CI10742292"

```
KAE_STEND = "CI10742292"

┌─────────────────────────────────────────────────────────┐
│ Сервисный пользователь (СУЗ):                          │
│ User: CI10742292-lnx-mon_sys                           │
│ Primary Group: CI10742292-lnx-mon_sys ← Группа!        │
│ Shell: /sbin/nologin                                   │
│ Назначение: Владелец всех сервисных файлов            │
└─────────────────────────────────────────────────────────┘
                        ↓
        Группа: CI10742292-lnx-mon_sys
                        ↓
┌─────────────────────────────────────────────────────────┐
│ Члены группы (secondary):                              │
│                                                         │
│ - CI10742292-lnx-mon_sys (primary member)              │
│ - CI10742292-lnx-mon_admin (secondary member)          │
│ - CI10742292-lnx-mon_ci (secondary member)             │
│ - CI10742292-lnx-mon_ro (secondary member)             │
└─────────────────────────────────────────────────────────┘
```

---

## 🔧 Создание пользователей в IDM

### Порядок создания (ВАЖНО!)

#### 1. Создать СУЗ (первым!)

**Заявка в IDM:**
```
Тип заявки: Создание учетной записи Linux
Имя УЗ: CI10742292-lnx-mon_sys
Тип: NoLogin (СУЗ - Сервисная учетная запись)
Shell: /sbin/nologin
Primary Group: CI10742292-lnx-mon_sys (создается автоматически)
Назначение: Запуск сервисов мониторинга (Prometheus, Grafana, Harvest)
```

**Результат:**
- ✅ Пользователь: `CI10742292-lnx-mon_sys`
- ✅ Группа: `CI10742292-lnx-mon_sys` (создана автоматически)

#### 2. Создать ПУЗ (Администратор)

**Заявка в IDM:**
```
Имя УЗ: CI10742292-lnx-mon_admin
Тип: Interactive (ПУЗ - Привилегированная учетная запись)
Shell: /bin/bash
Primary Group: CI10742292-lnx-mon_admin (auto)
Secondary Groups: CI10742292-lnx-mon_sys  ← ВАЖНО!
Назначение: Администрирование системы мониторинга
```

#### 3. Создать ТУЗ (CI/CD)

**Заявка в IDM:**
```
Имя УЗ: CI10742292-lnx-mon_ci
Тип: Interactive (ТУЗ - Техническая учетная запись)
Shell: /bin/bash
Primary Group: CI10742292-lnx-mon_ci (auto)
Secondary Groups: CI10742292-lnx-mon_sys  ← ВАЖНО!
Назначение: Автоматизированный деплой через Jenkins/Ansible
```

#### 4. Создать ReadOnly

**Заявка в IDM:**
```
Имя УЗ: CI10742292-lnx-mon_ro
Тип: Interactive (ReadOnly)
Shell: /bin/bash
Primary Group: CI10742292-lnx-mon_ro (auto)
Secondary Groups: CI10742292-lnx-mon_sys  ← ВАЖНО!
Назначение: Аудит, просмотр логов и статуса (без прав изменения)
```

---

## 📊 Структура прав на файлы

### Владение файлами

```bash
# Сервисные данные
/opt/monitoring/data/
  Owner: CI10742292-lnx-mon_sys
  Group: CI10742292-lnx-mon_sys
  Perms: 770 (rwxrwx---)

# Логи
/opt/monitoring/logs/
  Owner: CI10742292-lnx-mon_sys
  Group: CI10742292-lnx-mon_sys
  Perms: 770 (rwxrwx---)

# Конфигурация
/opt/monitoring/config/
  Owner: CI10742292-lnx-mon_ci
  Group: CI10742292-lnx-mon_sys
  Perms: 750 (rwxr-x---)

# Бинарники
/opt/monitoring/bin/
  Owner: CI10742292-lnx-mon_ci
  Group: CI10742292-lnx-mon_sys
  Perms: 750 (rwxr-x---)
```

### Что может каждый пользователь?

```
┌─────────────────────┬──────────┬──────────┬──────────┐
│ Действие            │ Owner    │ Group    │ Others   │
├─────────────────────┼──────────┼──────────┼──────────┤
│ Читать data/        │ ✅ СУЗ   │ ✅ Все   │ ❌       │
│ Записать в data/    │ ✅ СУЗ   │ ✅ Все   │ ❌       │
│ Выполнить в data/   │ ✅ СУЗ   │ ✅ Все   │ ❌       │
├─────────────────────┼──────────┼──────────┼──────────┤
│ Читать config/      │ ✅ ТУЗ   │ ✅ Все   │ ❌       │
│ Записать config/    │ ✅ ТУЗ   │ ❌       │ ❌       │
│ Выполнить config/   │ ✅ ТУЗ   │ ✅ Все   │ ❌       │
├─────────────────────┼──────────┼──────────┼──────────┤
│ Читать bin/         │ ✅ ТУЗ   │ ✅ Все   │ ❌       │
│ Записать bin/       │ ✅ ТУЗ   │ ❌       │ ❌       │
│ Выполнить bin/      │ ✅ ТУЗ   │ ✅ Все   │ ❌       │
└─────────────────────┴──────────┴──────────┴──────────┘

"Все" = все члены группы CI10742292-lnx-mon_sys
```

---

## 🔒 Безопасность

### Изоляция между стендами

```bash
# Стенд CI10742292
Group: CI10742292-lnx-mon_sys
Files: /opt/monitoring/data (owned by CI10742292-lnx-mon_sys)

# Стенд DEV123456
Group: DEV123456-lnx-mon_sys
Files: /opt/monitoring/data (owned by DEV123456-lnx-mon_sys)

# Результат:
# Пользователи DEV123456 НЕ МОГУТ получить доступ к файлам CI10742292 ✅
```

### Контроль членства в группе

```
┌─────────────────────────────────────────────────────────┐
│ Управление группой через IDM                            │
│                                                         │
│ ✅ Добавить пользователя → Заявка в IDM               │
│ ✅ Удалить пользователя → Заявка в IDM                │
│ ❌ Локальное изменение → НЕ работает (IDM перезапишет)│
└─────────────────────────────────────────────────────────┘
```

### Дополнительная защита через sudoers

```bash
# Даже если пользователь в группе, sudoers ограничивает действия

# ReadOnly может только читать
CI10742292-lnx-mon_ro:
  ✅ systemctl --user status
  ✅ journalctl --user -u
  ❌ systemctl --user start (нет в sudoers)
  ❌ systemctl --user stop (нет в sudoers)

# Admin может управлять, но не деплоить
CI10742292-lnx-mon_admin:
  ✅ systemctl --user start/stop/restart
  ✅ journalctl
  ❌ chown (нет прав менять владельца)

# CI может деплоить
CI10742292-lnx-mon_ci:
  ✅ Все что нужно для деплоя
  ✅ chown, chmod
  ✅ systemctl управление
```

---

## 📝 Проверка настройки

### На сервере проверить:

```bash
# 1. Проверка пользователя СУЗ
id CI10742292-lnx-mon_sys
# Ожидаемый вывод:
# uid=5001(CI10742292-lnx-mon_sys) gid=5001(CI10742292-lnx-mon_sys) groups=5001(CI10742292-lnx-mon_sys)

# 2. Проверка пользователя Admin
id CI10742292-lnx-mon_admin
# Ожидаемый вывод:
# uid=5002(CI10742292-lnx-mon_admin) gid=5002(CI10742292-lnx-mon_admin) groups=5002(CI10742292-lnx-mon_admin),5001(CI10742292-lnx-mon_sys)
#                                                                                                                       ↑
#                                                                                          Есть secondary group СУЗ ✅

# 3. Проверка пользователя CI
id CI10742292-lnx-mon_ci
# Должна быть secondary group: CI10742292-lnx-mon_sys ✅

# 4. Проверка пользователя RO
id CI10742292-lnx-mon_ro
# Должна быть secondary group: CI10742292-lnx-mon_sys ✅

# 5. Проверка прав на файлы
ls -la /opt/monitoring/data/
# Должно быть:
# drwxrwx--- CI10742292-lnx-mon_sys CI10742292-lnx-mon_sys

# 6. Проверка из-под Admin (должен иметь доступ через группу)
su - CI10742292-lnx-mon_admin
ls /opt/monitoring/data/
# Должно работать ✅
```

---

## 🎨 Ansible конфигурация

### В `group_vars/monitoring.yml`:

```yaml
# Динамическая группа = имя СУЗ
monitoring_group: "{{ user_sys | default(kae_stend + '-lnx-mon_sys') }}"
```

### Результат в systemd units:

```ini
[Service]
User=CI10742292-lnx-mon_sys
Group=CI10742292-lnx-mon_sys
```

### Результат в командах chown:

```bash
chown CI10742292-lnx-mon_sys:CI10742292-lnx-mon_sys /opt/monitoring/data
```

---

## 🔄 Миграция со статической группы

### Если ранее использовалась статическая группа "monitoring":

#### Шаг 1: Обновить Ansible
```yaml
# Было:
monitoring_group: "monitoring"

# Стало:
monitoring_group: "{{ user_sys | default(kae_stend + '-lnx-mon_sys') }}"
```

#### Шаг 2: Пересоздать УЗ в IDM
```bash
# Создать новые УЗ с динамическими именами
# С правильной схемой групп (СУЗ + secondary для остальных)
```

#### Шаг 3: Перезапустить Ansible playbook
```bash
# Ansible обновит все файлы с новой группой
ansible-playbook playbooks/deploy_monitoring.yml
```

#### Шаг 4: Проверить права
```bash
ls -la /opt/monitoring/
# Все файлы должны принадлежать группе CI10742292-lnx-mon_sys
```

---

## ✅ Чеклист для внедрения

- [ ] Создать СУЗ в IDM (создается группа автоматически)
- [ ] Создать ПУЗ в IDM с secondary group = СУЗ
- [ ] Создать ТУЗ в IDM с secondary group = СУЗ
- [ ] Создать ReadOnly в IDM с secondary group = СУЗ
- [ ] Обновить `ansible/group_vars/monitoring.yml` (группа = СУЗ)
- [ ] Запустить Jenkins Pipeline с NAMESPACE_CI
- [ ] Проверить на сервере членство в группах (`id <user>`)
- [ ] Проверить права на файлы (`ls -la /opt/monitoring/`)
- [ ] Проверить доступ из-под разных пользователей

---

## 📚 Ссылки

- `docs/IDM_ACCOUNTS_GUIDE.md` - Создание УЗ в IDM
- `docs/KAE_STEND_NAMING.md` - Динамические имена пользователей
- `ansible/group_vars/monitoring.yml` - Конфигурация группы
- `QUICKSTART_DYNAMIC_USERS.md` - Быстрый старт

---

## 🎯 Итог

**Группа = СУЗ** обеспечивает:

✅ **Автоматизацию** - группа создается при создании СУЗ  
✅ **Изоляцию** - каждый стенд имеет свою группу  
✅ **Безопасность** - контроль через IDM + sudoers  
✅ **Простоту** - одна группа для всех пользователей стенда  
✅ **Соответствие стандартам** - типичная практика Enterprise Linux  

**Статус**: ✅ Production Ready  
**Дата**: 19.11.2024  
**Версия**: 2.2





