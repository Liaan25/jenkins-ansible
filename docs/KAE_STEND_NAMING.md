# Динамические имена пользователей на основе KAE_STEND

## Обзор

Система мониторинга использует **динамическое формирование имен пользователей** на основе KAE стенда (KAE_STEND), который автоматически извлекается из параметра `NAMESPACE_CI`.

Это обеспечивает:
- ✅ Уникальность пользователей для каждого стенда
- ✅ Соответствие корпоративной политике именования
- ✅ Упрощение управления множеством стендов
- ✅ Автоматизацию без ручного ввода имен

---

## Формирование имен пользователей

### Схема извлечения KAE_STEND

```
NAMESPACE_CI = "CI04523276_CI10742292"
                          ↓
            Извлечение части после последнего '_'
                          ↓
            KAE_STEND = "CI10742292"
                          ↓
            Формирование имен пользователей
                          ↓
┌─────────────────────────────────────────────────────┐
│ CI10742292-lnx-mon_sys      (Сервисная, СУЗ)      │
│ CI10742292-lnx-mon_admin    (Администратор, ПУЗ)  │
│ CI10742292-lnx-mon_ci       (CI/CD, ТУЗ)          │
│ CI10742292-lnx-mon_ro       (ReadOnly)            │
└─────────────────────────────────────────────────────┘
```

### Формат имени пользователя

```
{KAE_STEND}-lnx-mon_{тип}

Где:
- {KAE_STEND} - извлекается из NAMESPACE_CI
- lnx - Linux (платформа)
- mon - monitoring (система)
- {тип} - sys/admin/ci/ro (роль пользователя)
```

---

## Примеры

### Пример 1: Стандартный формат

**Входные данные:**
```
NAMESPACE_CI = CI04523276_CI10742292
```

**Результат:**
```yaml
KAE_STEND: CI10742292

Пользователи:
- user_sys: CI10742292-lnx-mon_sys
- user_admin: CI10742292-lnx-mon_admin
- user_ci: CI10742292-lnx-mon_ci
- user_ro: CI10742292-lnx-mon_ro
```

### Пример 2: Проектный формат

**Входные данные:**
```
NAMESPACE_CI = KPRJ_000123
```

**Результат:**
```yaml
KAE_STEND: 000123

Пользователи:
- user_sys: 000123-lnx-mon_sys
- user_admin: 000123-lnx-mon_admin
- user_ci: 000123-lnx-mon_ci
- user_ro: 000123-lnx-mon_ro
```

### Пример 3: Множественные разделители

**Входные данные:**
```
NAMESPACE_CI = PRJ_SUB_DEV_12345
```

**Результат:**
```yaml
KAE_STEND: 12345  (берется часть после последнего '_')

Пользователи:
- user_sys: 12345-lnx-mon_sys
- user_admin: 12345-lnx-mon_admin
- user_ci: 12345-lnx-mon_ci
- user_ro: 12345-lnx-mon_ro
```

---

## Требования и валидация

### Требования к NAMESPACE_CI

1. **Обязательно содержит разделитель `_`**
   ```
   ✅ Правильно: CI04523276_CI10742292
   ❌ Неправильно: CI04523276CI10742292
   ```

2. **Формат PREFIX_SUFFIX**
   - PREFIX - любая строка до последнего `_`
   - SUFFIX - становится KAE_STEND

### Требования к KAE_STEND

После извлечения KAE_STEND валидируется:

| Параметр | Требование | Пример |
|----------|-----------|--------|
| **Допустимые символы** | Только буквы, цифры, дефис | `CI10742292` ✅<br>`CI@10742` ❌ |
| **Минимальная длина** | 3 символа | `CI1` ✅<br>`C1` ❌ |
| **Максимальная длина** | 20 символов | `CI10742292` ✅<br>`VERYLONGSTENDNAME12345` ❌ |

### Требования к финальным именам пользователей

| Параметр | Требование | Проверка |
|----------|-----------|----------|
| **Формат** | `^[a-zA-Z0-9][a-zA-Z0-9_-]{0,30}[a-zA-Z0-9]$` | Начинается и заканчивается буквой/цифрой |
| **Максимальная длина** | 32 символа | Требование Linux/IDM |
| **Допустимые символы** | Буквы, цифры, `_`, `-` | В середине имени |

---

## Процесс валидации в Jenkins

### Этап 1: Проверка NAMESPACE_CI

```groovy
// Проверка наличия разделителя
if (!params.NAMESPACE_CI.contains('_')) {
    error("ОШИБКА: NAMESPACE_CI должен содержать '_'")
}
```

### Этап 2: Извлечение KAE_STEND

```groovy
// Извлечение части после последнего '_'
def namespaceParts = params.NAMESPACE_CI.split('_')
env.KAE_STEND = namespaceParts[-1]
```

### Этап 3: Валидация KAE_STEND

```groovy
// Проверка символов
if (!env.KAE_STEND.matches(/^[a-zA-Z0-9-]+$/)) {
    error("KAE_STEND содержит недопустимые символы")
}

// Проверка длины
if (env.KAE_STEND.length() < 3 || env.KAE_STEND.length() > 20) {
    error("KAE_STEND имеет недопустимую длину")
}
```

### Этап 4: Формирование имен

```groovy
env.USER_SYS = "${env.KAE_STEND}-lnx-mon_sys"
env.USER_ADMIN = "${env.KAE_STEND}-lnx-mon_admin"
env.USER_CI = "${env.KAE_STEND}-lnx-mon_ci"
env.USER_RO = "${env.KAE_STEND}-lnx-mon_ro"
```

### Этап 5: Валидация финальных имен

```groovy
def userNamePattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,30}[a-zA-Z0-9]$/

[env.USER_SYS, env.USER_ADMIN, env.USER_CI, env.USER_RO].each { userName ->
    if (!userName.matches(userNamePattern)) {
        error("Недопустимое имя пользователя: ${userName}")
    }
    if (userName.length() > 32) {
        error("Имя слишком длинное: ${userName}")
    }
}
```

---

## Создание пользователей в IDM

### Шаг 1: Определение KAE_STEND

Перед созданием УЗ в IDM узнайте ваш KAE_STEND:

```bash
# Из NAMESPACE_CI
NAMESPACE_CI="CI04523276_CI10742292"
KAE_STEND="${NAMESPACE_CI##*_}"  # Результат: CI10742292
```

### Шаг 2: Формирование имен

```bash
USER_SYS="${KAE_STEND}-lnx-mon_sys"
USER_ADMIN="${KAE_STEND}-lnx-mon_admin"
USER_CI="${KAE_STEND}-lnx-mon_ci"
USER_RO="${KAE_STEND}-lnx-mon_ro"

echo "Создайте следующие УЗ в IDM:"
echo "- $USER_SYS (СУЗ, NoLogin)"
echo "- $USER_ADMIN (ПУЗ, Interactive)"
echo "- $USER_CI (ТУЗ, Interactive)"
echo "- $USER_RO (ReadOnly, Interactive)"
```

### Шаг 3: Создание в IDM

Для каждого пользователя создать заявку:

**1. СУЗ (Сервисная)**
```
Имя УЗ: CI10742292-lnx-mon_sys
Тип: NoLogin
Назначение: Запуск сервисов мониторинга
```

**2. ПУЗ (Администратор)**
```
Имя УЗ: CI10742292-lnx-mon_admin
Тип: Interactive
Назначение: Администрирование системы мониторинга
```

**3. ТУЗ (CI/CD)**
```
Имя УЗ: CI10742292-lnx-mon_ci
Тип: Interactive
Назначение: Автоматизированный деплой через Jenkins
```

**4. ReadOnly**
```
Имя УЗ: CI10742292-lnx-mon_ro
Тип: Interactive
Назначение: Аудит и просмотр логов
```

---

## Использование в Ansible

### Автоматическая подстановка

Ansible автоматически получает имена пользователей из Jenkins:

```yaml
# В group_vars/monitoring.yml
kae_stend: "{{ kae_stend | default('KPRJ000000') }}"

monitoring_service_user: "{{ user_sys | default(kae_stend + '-lnx-mon_sys') }}"
monitoring_admin_user: "{{ user_admin | default(kae_stend + '-lnx-mon_admin') }}"
monitoring_ci_user: "{{ user_ci | default(kae_stend + '-lnx-mon_ci') }}"
monitoring_ro_user: "{{ user_ro | default(kae_stend + '-lnx-mon_ro') }}"
```

### Использование в tasks

```yaml
- name: Создать директорию для данных
  file:
    path: /opt/monitoring/data
    state: directory
    owner: "{{ monitoring_service_user }}"  # → CI10742292-lnx-mon_sys
    group: "{{ monitoring_group }}"
    mode: '0770'
```

---

## Sudoers файлы

### ⚠️ Важное замечание

**Sudoers файлы НЕ поддерживают переменные!**

Согласно корпоративным требованиям:
> "Без переменных. Каждая команда должна быть указана явно и без звездочек."

### Решение: Отдельные sudoers для каждого стенда

Для каждого KAE_STEND нужно создавать **свои sudoers файлы** с явно указанными именами:

**Пример для KAE_STEND = CI10742292:**

```bash
# sudoers/CI10742292-lnx-mon_ci
CI10742292-lnx-mon_ci ALL=(CI10742292-lnx-mon_sys) NOPASSWD: ALL
CI10742292-lnx-mon_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start prometheus
...
```

### Генерация sudoers файлов

Используйте шаблоны для генерации:

```bash
#!/bin/bash
KAE_STEND="CI10742292"

# Генерация sudoers для CI
sed "s/{{KAE_STEND}}/${KAE_STEND}/g" templates/monitoring_ci.template > sudoers/${KAE_STEND}-lnx-mon_ci
```

---

## Безопасность

### Защита от injection

**Проблема:** Злоумышленник может попытаться внедрить вредоносный код через NAMESPACE_CI

**Пример атаки:**
```
NAMESPACE_CI = "CI04523276_$(rm -rf /)"
```

**Защита:**

1. **Строгая валидация символов**
   ```groovy
   if (!env.KAE_STEND.matches(/^[a-zA-Z0-9-]+$/)) {
       error("Недопустимые символы")
   }
   ```

2. **Проверка длины**
   ```groovy
   if (env.KAE_STEND.length() < 3 || env.KAE_STEND.length() > 20) {
       error("Недопустимая длина")
   }
   ```

3. **Валидация финального результата**
   ```groovy
   if (!userName.matches(/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,30}[a-zA-Z0-9]$/)) {
       error("Недопустимое имя")
   }
   ```

### Соответствие корпоративным требованиям

✅ **Принцип наименьших привилегий** - каждый стенд имеет свои изолированные УЗ
✅ **Разделение полномочий** - сохранена схема СУЗ/ПУЗ/ТУЗ/RO
✅ **Прослеживаемость** - имя пользователя содержит KAE стенда
✅ **Автоматизация** - без ручного ввода имен
✅ **Явное указание** - sudoers создаются с явными именами

---

## Troubleshooting

### Проблема 1: NAMESPACE_CI не содержит '_'

**Ошибка:**
```
ОШИБКА: NAMESPACE_CI должен содержать разделитель '_'
```

**Решение:**
```
Проверьте формат NAMESPACE_CI:
✅ Правильно: CI04523276_CI10742292
❌ Неправильно: CI04523276
```

### Проблема 2: KAE_STEND содержит недопустимые символы

**Ошибка:**
```
ОШИБКА: KAE_STEND содержит недопустимые символы: 'CI@10742'
```

**Решение:**
```
KAE_STEND может содержать только:
- Буквы (a-z, A-Z)
- Цифры (0-9)
- Дефис (-)

Проверьте NAMESPACE_CI на спецсимволы
```

### Проблема 3: Имя пользователя слишком длинное

**Ошибка:**
```
ОШИБКА: Имя слишком длинное (длина: 35 > 32)
```

**Решение:**
```
Максимальная длина имени: 32 символа
Максимальная длина KAE_STEND: 20 символов

Если KAE_STEND очень длинный, используйте сокращение:
- VERYLONGSTENDNAME → VLSN
- CI04523276_VERYLONGSTENDNAME → CI04523276_VLSN
```

### Проблема 4: Пользователь не существует в IDM

**Ошибка:**
```
ssh: User CI10742292-lnx-mon_ci not found
```

**Решение:**
```
1. Проверить что УЗ созданы в IDM:
   - CI10742292-lnx-mon_sys
   - CI10742292-lnx-mon_admin
   - CI10742292-lnx-mon_ci
   - CI10742292-lnx-mon_ro

2. Дождаться синхронизации IDM → Linux (обычно 5-15 минут)

3. Проверить на сервере:
   id CI10742292-lnx-mon_ci
```

---

## FAQ

### Q: Можно ли использовать статические имена?

**A:** Да, если у вас один стенд. Но для множественных стендов рекомендуется динамический подход.

### Q: Что если KAE_STEND одинаковый для разных проектов?

**A:** Невозможно. KAE_STEND извлекается из уникального NAMESPACE_CI, который всегда уникален в рамках корпорации.

### Q: Нужно ли обновлять sudoers при каждом деплое?

**A:** Нет. Sudoers создаются один раз при первичной настройке стенда и не меняются.

### Q: Как узнать какие пользователи используются на сервере?

**A:** Посмотреть вывод Jenkins Pipeline на этапе "Валидация параметров":

```
Пользователи (динамически сформированы):
- Сервисная (СУЗ): CI10742292-lnx-mon_sys
- Администратор (ПУЗ): CI10742292-lnx-mon_admin
- CI/CD (ТУЗ): CI10742292-lnx-mon_ci
- ReadOnly: CI10742292-lnx-mon_ro
```

---

## Ссылки на документацию

- `docs/IDM_ACCOUNTS_GUIDE.md` - Создание УЗ в IDM
- `docs/SUDOERS_GUIDE.md` - Настройка sudo прав
- `docs/SECURITY_MODEL.md` - Модель безопасности
- `Jenkinsfile` - Реализация извлечения KAE_STEND
- `ansible/group_vars/monitoring.yml` - Ansible переменные

---

**Дата создания**: 19.11.2024  
**Версия**: 1.0  
**Статус**: ✅ Готово к использованию



