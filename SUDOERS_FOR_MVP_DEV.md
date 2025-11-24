# 📋 Sudoers права для mvp_dev (SSH_USER)

> **Для заявки в IDM**: Явные sudo права без переменных и звездочек

**Дата:** November 24, 2024  
**Пользователь:** `mvp_dev` (SSH_USER для Jenkins)  
**Целевой сервер:** `tvlds-mvp001939.cloud.delta.sbrf.ru`

---

## ✅ Требуемые sudo права

### Создание директории для секретов

```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/mkdir -p /dev/shm/monitoring_secrets
```

---

### Изменение владельца директории

**Для временной передачи владения SSH_USER (запись файла):**
```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chown mvp_dev\:CI10742292-lnx-mon_sys /dev/shm/monitoring_secrets
```

**Для финальной передачи владения SYS_USER:**
```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chown -R CI10742292-lnx-mon_sys\:CI10742292-lnx-mon_sys /dev/shm/monitoring_secrets
```

---

### Изменение прав доступа

**Временные права (для записи):**
```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chmod 750 /dev/shm/monitoring_secrets
```

**Финальные права (директория):**
```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chmod 700 /dev/shm/monitoring_secrets
```

**Финальные права (файл секретов):**
```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chmod 600 /dev/shm/monitoring_secrets/secrets.json
```

---

## 📝 Полный файл sudoers для копирования в IDM

```sudoers
# ============================================================================
# Sudoers для mvp_dev (SSH_USER для Jenkins Pipeline)
# ============================================================================
# Назначение: Безопасная передача секретов в /dev/shm/monitoring_secrets
# Требования: Без переменных, без звездочек, явные пути
# ============================================================================

# Создание директории для секретов в /dev/shm
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/mkdir -p /dev/shm/monitoring_secrets

# Изменение владельца директории (временно для SSH_USER, затем для SYS_USER)
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chown mvp_dev\:CI10742292-lnx-mon_sys /dev/shm/monitoring_secrets
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chown -R CI10742292-lnx-mon_sys\:CI10742292-lnx-mon_sys /dev/shm/monitoring_secrets

# Изменение прав доступа (временные и финальные)
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chmod 750 /dev/shm/monitoring_secrets
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chmod 700 /dev/shm/monitoring_secrets
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/chmod 600 /dev/shm/monitoring_secrets/secrets.json

# ============================================================================
# КОНЕЦ ФАЙЛА
# ============================================================================
```

---

## 🔐 Обоснование для кибербезопасности

### Почему нужны эти права?

**Проблема:**
- Jenkins Pipeline через SSH подключается как `mvp_dev`
- Нужно безопасно передать секреты в `/dev/shm/monitoring_secrets/`
- Финальный владелец должен быть `CI10742292-lnx-mon_sys` (сервисный пользователь)

**Процесс:**
1. `root` создает директорию в `/dev/shm` (только root может это сделать из-за sticky bit)
2. `root` временно передает владение `mvp_dev` (для записи файла секретов)
3. `mvp_dev` записывает файл (как владелец директории)
4. `root` передает владение `CI10742292-lnx-mon_sys` (финальный владелец)
5. `root` устанавливает финальные права `700`/`600` (максимальная защита)

**Безопасность:**
- ✅ Нет переменных в командах
- ✅ Нет звездочек (wildcards)
- ✅ Явные пути к файлам
- ✅ Явные значения прав (750, 700, 600)
- ✅ Минимальное время уязвимости (mvp_dev владелец только на время записи)
- ✅ Финальные права максимально защищены (только SYS_USER)

---

## 📋 Workflow (визуализация)

```
┌─────────────────────────────────────────────────────────────────┐
│  1. sudo mkdir -p /dev/shm/monitoring_secrets                   │
│     Владелец: root, Права: 755 (по умолчанию)                   │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. sudo chown mvp_dev:CI10742292-lnx-mon_sys ...               │
│     Владелец: mvp_dev (временно для записи)                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. sudo chmod 750 /dev/shm/monitoring_secrets                  │
│     Права: rwxr-x--- (владелец может писать)                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. cat > /dev/shm/monitoring_secrets/secrets.json              │
│     Запись от mvp_dev (владелец, есть права)                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. sudo chown -R CI10742292-lnx-mon_sys:...                    │
│     Владелец: CI10742292-lnx-mon_sys (финальный)                │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  6. sudo chmod 700 /dev/shm/monitoring_secrets                  │
│     sudo chmod 600 /dev/shm/monitoring_secrets/secrets.json     │
│     Права: rwx------ и rw------- (только SYS_USER)              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
                  ✅ БЕЗОПАСНО!
```

---

## 🔍 Альтернативные подходы (НЕ используются)

### ❌ Вариант 1: bash -c с переменными
```sudoers
mvp_dev ALL=(root:root) NOPASSWD: /usr/bin/bash -c *
```
**Проблема:** Звездочка запрещена, небезопасно.

---

### ❌ Вариант 2: sudo -u CI_USER
```sudoers
mvp_dev ALL=(CI10742292-lnx-mon_ci:CI10742292-lnx-mon_sys) NOPASSWD: /usr/bin/bash -c *
```
**Проблема:** Требует `bash -c *` (звездочка запрещена).

---

### ❌ Вариант 3: Широкие права 777
```bash
sudo chmod 777 /dev/shm/monitoring_secrets
```
**Проблема:** Создает окно уязвимости, любой пользователь может писать.

---

### ✅ Выбранный подход
Временная передача владения `mvp_dev` с минимальными правами, затем безопасная передача `SYS_USER`.

---

## 📞 Контакты

**Для вопросов:**
- DevOps команда: [email]
- Заявка IDM: [номер]

---

**Соответствует корпоративным требованиям:** ✅  
**Проверено:** 24.11.2024  
**Версия:** 1.0

