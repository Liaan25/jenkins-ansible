# Sudoers файлы и динамические имена пользователей

## ⚠️ Важное замечание

**Sudoers файлы НЕ поддерживают переменные или динамические имена!**

Согласно корпоративным требованиям безопасности:
> "Без переменных. Каждая команда должна быть указана явно и без звездочек."

## Текущие sudoers файлы

Файлы в этой директории используют **статические имена** для примера и reference:

```
sudoers/
├── monitoring_ci       # Пример для ТУЗ (CI/CD)
├── monitoring_admin    # Пример для ПУЗ (Администратор)
├── monitoring_ro       # Пример для ReadOnly
└── monitoring_svc      # Документация (пустой)
```

**Эти имена:**
- `monitoring_ci`
- `monitoring_admin`
- `monitoring_ro`
- `monitoring_svc`

---

## Для динамических имен пользователей

Если вы используете **динамические имена** (например, `CI10742292-lnx-mon_ci`), необходимо:

### Вариант 1: Генерация sudoers файлов (рекомендуется)

Создать sudoers файлы для вашего конкретного KAE_STEND:

```bash
#!/bin/bash
# Скрипт генерации sudoers для конкретного KAE_STEND

# Ваш KAE_STEND (извлечь из NAMESPACE_CI)
NAMESPACE_CI="CI04523276_CI10742292"
KAE_STEND="${NAMESPACE_CI##*_}"  # Результат: CI10742292

# Формирование имен пользователей
USER_SYS="${KAE_STEND}-lnx-mon_sys"
USER_ADMIN="${KAE_STEND}-lnx-mon_admin"
USER_CI="${KAE_STEND}-lnx-mon_ci"
USER_RO="${KAE_STEND}-lnx-mon_ro"

# Генерация sudoers файлов
echo "Генерация sudoers для KAE_STEND: $KAE_STEND"

# Для monitoring_ci
sed "s/monitoring_ci/$USER_CI/g; s/monitoring_svc/$USER_SYS/g" monitoring_ci > "${KAE_STEND}-lnx-mon_ci"

# Для monitoring_admin
sed "s/monitoring_admin/$USER_ADMIN/g; s/monitoring_svc/$USER_SYS/g" monitoring_admin > "${KAE_STEND}-lnx-mon_admin"

# Для monitoring_ro
sed "s/monitoring_ro/$USER_RO/g; s/monitoring_svc/$USER_SYS/g" monitoring_ro > "${KAE_STEND}-lnx-mon_ro"

echo "✓ Созданы файлы:"
echo "  - ${KAE_STEND}-lnx-mon_ci"
echo "  - ${KAE_STEND}-lnx-mon_admin"
echo "  - ${KAE_STEND}-lnx-mon_ro"
```

### Вариант 2: Ручное создание

Вручную создать файлы с явными именами:

**Пример для `CI10742292-lnx-mon_ci`:**

```bash
# sudoers/CI10742292-lnx-mon_ci

# Переключение на пользователя CI10742292-lnx-mon_sys
CI10742292-lnx-mon_ci ALL=(CI10742292-lnx-mon_sys) NOPASSWD: ALL

# Управление systemd units
CI10742292-lnx-mon_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user daemon-reload
CI10742292-lnx-mon_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable grafana
...
```

---

## Размещение в /etc/sudoers.d/

После генерации файлов, разместите их на целевом сервере:

```bash
# Проверка синтаксиса
sudo visudo -c -f sudoers/CI10742292-lnx-mon_ci

# Копирование на сервер
sudo cp sudoers/CI10742292-lnx-mon_ci /etc/sudoers.d/CI10742292-lnx-mon_ci
sudo cp sudoers/CI10742292-lnx-mon_admin /etc/sudoers.d/CI10742292-lnx-mon_admin
sudo cp sudoers/CI10742292-lnx-mon_ro /etc/sudoers.d/CI10742292-lnx-mon_ro

# Установка прав
sudo chmod 440 /etc/sudoers.d/CI10742292-lnx-mon_*
sudo chown root:root /etc/sudoers.d/CI10742292-lnx-mon_*

# Проверка
sudo -l -U CI10742292-lnx-mon_ci
```

---

## Запрос через IDM

При создании заявки в IDM на права sudo:

**Вариант A: Для каждого пользователя отдельно**

Создать 3 заявки:
1. Права для `CI10742292-lnx-mon_ci` → приложить файл `CI10742292-lnx-mon_ci`
2. Права для `CI10742292-lnx-mon_admin` → приложить файл `CI10742292-lnx-mon_admin`
3. Права для `CI10742292-lnx-mon_ro` → приложить файл `CI10742292-lnx-mon_ro`

**Вариант B: Использовать шаблоны**

Если в IDM есть поддержка шаблонов, можно создать:
- Шаблон "monitoring_ci_template"
- При применении указать: заменить `monitoring_ci` на `CI10742292-lnx-mon_ci`

---

## Автоматизация через Ansible

**⚠️ Важно:** Даже через Ansible нельзя использовать переменные в sudoers!

**Правильный подход:**

```yaml
# playbook
- name: Генерация sudoers файла для CI пользователя
  template:
    src: sudoers_ci.j2
    dest: "/tmp/{{ user_ci }}"
    mode: '0440'

- name: Проверка синтаксиса sudoers
  command: visudo -c -f "/tmp/{{ user_ci }}"
  
- name: Копирование sudoers в /etc/sudoers.d/
  copy:
    src: "/tmp/{{ user_ci }}"
    dest: "/etc/sudoers.d/{{ user_ci }}"
    owner: root
    group: root
    mode: '0440'
  become: yes
```

**Template `sudoers_ci.j2`:**

```jinja2
# Sudoers for {{ user_ci }}

# Переключение на {{ user_sys }}
{{ user_ci }} ALL=({{ user_sys }}) NOPASSWD: ALL

# Управление systemd units
{{ user_ci }} ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user daemon-reload
{{ user_ci }} ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user enable grafana
...
```

---

## Пример структуры для множественных стендов

```
sudoers/
├── templates/
│   ├── monitoring_ci.template
│   ├── monitoring_admin.template
│   └── monitoring_ro.template
├── CI10742292/
│   ├── CI10742292-lnx-mon_ci
│   ├── CI10742292-lnx-mon_admin
│   └── CI10742292-lnx-mon_ro
├── DEV123456/
│   ├── DEV123456-lnx-mon_ci
│   ├── DEV123456-lnx-mon_admin
│   └── DEV123456-lnx-mon_ro
└── PROD789012/
    ├── PROD789012-lnx-mon_ci
    ├── PROD789012-lnx-mon_admin
    └── PROD789012-lnx-mon_ro
```

---

## Инструменты для генерации

### generate_sudoers.sh

```bash
#!/bin/bash
set -euo pipefail

# Скрипт генерации sudoers файлов для конкретного KAE_STEND

usage() {
    echo "Usage: $0 <NAMESPACE_CI>"
    echo "Example: $0 CI04523276_CI10742292"
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

NAMESPACE_CI="$1"

# Проверка формата
if [[ ! "$NAMESPACE_CI" =~ _ ]]; then
    echo "ERROR: NAMESPACE_CI must contain '_' separator"
    exit 1
fi

# Извлечение KAE_STEND
KAE_STEND="${NAMESPACE_CI##*_}"

# Валидация
if [[ ! "$KAE_STEND" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "ERROR: KAE_STEND contains invalid characters: $KAE_STEND"
    exit 1
fi

if [[ ${#KAE_STEND} -lt 3 || ${#KAE_STEND} -gt 20 ]]; then
    echo "ERROR: KAE_STEND length must be 3-20 characters: $KAE_STEND"
    exit 1
fi

# Формирование имен
USER_SYS="${KAE_STEND}-lnx-mon_sys"
USER_ADMIN="${KAE_STEND}-lnx-mon_admin"
USER_CI="${KAE_STEND}-lnx-mon_ci"
USER_RO="${KAE_STEND}-lnx-mon_ro"

# Создание директории
OUTPUT_DIR="sudoers/${KAE_STEND}"
mkdir -p "$OUTPUT_DIR"

echo "Generating sudoers files for KAE_STEND: $KAE_STEND"
echo "Output directory: $OUTPUT_DIR"

# Генерация файлов
for type in ci admin ro; do
    template="monitoring_${type}"
    output="${KAE_STEND}-lnx-mon_${type}"
    
    if [[ ! -f "sudoers/${template}" ]]; then
        echo "WARNING: Template not found: sudoers/${template}"
        continue
    fi
    
    sed "s/monitoring_ci/$USER_CI/g; \
         s/monitoring_admin/$USER_ADMIN/g; \
         s/monitoring_ro/$USER_RO/g; \
         s/monitoring_svc/$USER_SYS/g" \
        "sudoers/${template}" > "${OUTPUT_DIR}/${output}"
    
    echo "✓ Created: ${OUTPUT_DIR}/${output}"
    
    # Проверка синтаксиса
    if command -v visudo &> /dev/null; then
        if sudo visudo -c -f "${OUTPUT_DIR}/${output}" &> /dev/null; then
            echo "  ✓ Syntax OK"
        else
            echo "  ✗ Syntax ERROR"
            exit 1
        fi
    fi
done

echo ""
echo "✓ All files generated successfully!"
echo ""
echo "Next steps:"
echo "1. Review files in ${OUTPUT_DIR}/"
echo "2. Copy to target server"
echo "3. Place in /etc/sudoers.d/"
echo "4. Set permissions: chmod 440, chown root:root"
```

---

## FAQ

### Q: Можно ли использовать wildcards в sudoers?

**A:** Нет! Согласно корпоративным требованиям:
```
❌ monitoring_* ALL=(ALL) NOPASSWD: ALL
✅ CI10742292-lnx-mon_ci ALL=(CI10742292-lnx-mon_sys) NOPASSWD: ALL
```

### Q: Можно ли использовать переменные окружения?

**A:** Нет! sudoers не поддерживает переменные:
```
❌ ${USER_CI} ALL=(ALL) NOPASSWD: ALL
✅ CI10742292-lnx-mon_ci ALL=(ALL) NOPASSWD: ALL
```

### Q: Нужно ли генерировать sudoers при каждом деплое?

**A:** Нет! Sudoers создаются **один раз** при первичной настройке стенда.

### Q: Что делать если KAE_STEND изменился?

**A:** Это означает новый стенд:
1. Создать новые УЗ в IDM
2. Сгенерировать новые sudoers файлы
3. Разместить на целевом сервере
4. Старые файлы можно удалить (если старый стенд больше не используется)

---

## Ссылки

- `docs/KAE_STEND_NAMING.md` - Полное руководство по динамическим именам
- `docs/SUDOERS_GUIDE.md` - Настройка sudo прав
- `docs/IDM_ACCOUNTS_GUIDE.md` - Создание УЗ в IDM

---

**Дата**: 19.11.2024  
**Версия**: 1.0  
**Статус**: ✅ Справочная информация


