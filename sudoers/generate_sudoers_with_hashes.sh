#!/bin/bash
################################################################################
# Скрипт генерации sudoers файлов с SHA256 хешами для IDM
################################################################################
#
# Назначение:
#   1. Генерация скриптов-оберток
#   2. Вычисление SHA256 хешей для скриптов
#   3. Генерация sudoers файлов с подставленными хешами
#   4. Сохранение результата для копирования в IDM
#
# Использование:
#   ./generate_sudoers_with_hashes.sh <NAMESPACE_CI> <OUTPUT_DIR>
#
# Параметры:
#   NAMESPACE_CI - Namespace из Jenkins (например: CI04523276_CI10742292)
#   OUTPUT_DIR   - Директория для сохранения (например: /tmp/monitoring_sudoers)
#
# Примеры:
#   ./generate_sudoers_with_hashes.sh CI04523276_CI10742292 /tmp/monitoring_sudoers
#   ./generate_sudoers_with_hashes.sh CI04523276_CI10742292 $HOME/monitoring_sudoers
#
################################################################################

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Функции вывода
print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ INFO: $1${NC}"
}

print_step() {
    echo -e "${CYAN}▶ $1${NC}"
}

# ==========================================
# BANNER
# ==========================================

show_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                        ║"
    echo "║    ГЕНЕРАТОР SUDOERS С SHA256 ХЕШАМИ ДЛЯ IDM                          ║"
    echo "║                                                                        ║"
    echo "║    Этап 1: Подготовка sudoers файлов для согласования в IDM          ║"
    echo "║                                                                        ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ==========================================
# ПРОВЕРКА АРГУМЕНТОВ
# ==========================================

if [[ $# -lt 1 ]]; then
    print_error "Недостаточно аргументов"
    echo ""
    echo "Использование: $0 <NAMESPACE_CI> [OUTPUT_DIR]"
    echo ""
    echo "Параметры:"
    echo "  NAMESPACE_CI - Namespace из Jenkins (обязательный)"
    echo "  OUTPUT_DIR   - Директория для сохранения (опционально, по умолчанию: \$HOME/monitoring_sudoers_generated)"
    echo ""
    echo "Примеры:"
    echo "  $0 CI04523276_CI10742292"
    echo "  $0 CI04523276_CI10742292 /tmp/monitoring_sudoers"
    exit 1
fi

NAMESPACE_CI="$1"
OUTPUT_BASE_DIR="${2:-$HOME/monitoring_sudoers_generated}"

show_banner

# ==========================================
# ВАЛИДАЦИЯ NAMESPACE_CI
# ==========================================

print_step "ЭТАП 1: Валидация параметров"
echo ""

print_info "NAMESPACE_CI: ${NAMESPACE_CI}"

if [[ ! "$NAMESPACE_CI" =~ _ ]]; then
    print_error "NAMESPACE_CI должен содержать разделитель '_'"
    echo "Пример: CI04523276_CI10742292"
    exit 1
fi

print_success "NAMESPACE_CI валиден"

# ==========================================
# ИЗВЛЕЧЕНИЕ KAE_STEND
# ==========================================

KAE_STEND="${NAMESPACE_CI##*_}"
print_info "Извлеченный KAE_STEND: ${KAE_STEND}"

# Валидация KAE_STEND
if [[ ! "$KAE_STEND" =~ ^[a-zA-Z0-9-]+$ ]]; then
    print_error "KAE_STEND содержит недопустимые символы: ${KAE_STEND}"
    exit 1
fi

if [[ ${#KAE_STEND} -lt 3 || ${#KAE_STEND} -gt 20 ]]; then
    print_error "Длина KAE_STEND должна быть от 3 до 20 символов"
    exit 1
fi

print_success "KAE_STEND валиден"

# ==========================================
# ФОРМИРОВАНИЕ ИМЕН ПОЛЬЗОВАТЕЛЕЙ
# ==========================================

USER_SYS="${KAE_STEND}-lnx-mon_sys"
USER_ADMIN="${KAE_STEND}-lnx-mon_admin"
USER_CI="${KAE_STEND}-lnx-mon_ci"
USER_RO="${KAE_STEND}-lnx-mon_ro"

echo ""
print_info "Сформированные имена пользователей:"
echo "  СУЗ (Service):     ${USER_SYS}"
echo "  ПУЗ (Admin):       ${USER_ADMIN}"
echo "  ТУЗ (CI/CD):       ${USER_CI}"
echo "  ReadOnly:          ${USER_RO}"
echo ""

# Проверка длины (max 32 символа)
for user in "$USER_SYS" "$USER_ADMIN" "$USER_CI" "$USER_RO"; do
    if [[ ${#user} -gt 32 ]]; then
        print_error "Имя пользователя слишком длинное (${#user}): ${user}"
        exit 1
    fi
done

print_success "Все имена пользователей корректны"

# ==========================================
# ПОДГОТОВКА ДИРЕКТОРИЙ
# ==========================================

echo ""
print_step "ЭТАП 2: Подготовка директорий"
echo ""

OUTPUT_DIR="${OUTPUT_BASE_DIR}/${KAE_STEND}"
SCRIPTS_DIR="${OUTPUT_DIR}/scripts"
SUDOERS_DIR="${OUTPUT_DIR}/sudoers"

print_info "Базовая директория: ${OUTPUT_DIR}"

if [[ -d "$OUTPUT_DIR" ]]; then
    print_warning "Директория уже существует, будет пересоздана"
    rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$SCRIPTS_DIR"
mkdir -p "$SUDOERS_DIR"

print_success "Директории созданы"

# ==========================================
# ГЕНЕРАЦИЯ СКРИПТОВ-ОБЕРТОК
# ==========================================

echo ""
print_step "ЭТАП 3: Генерация скриптов-оберток"
echo ""

# Определение пути к шаблонам скриптов
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPERS_SRC_DIR="${SCRIPT_DIR}/../scripts/wrappers"

if [[ ! -d "$WRAPPERS_SRC_DIR" ]]; then
    print_error "Директория со скриптами-обертками не найдена: ${WRAPPERS_SRC_DIR}"
    exit 1
fi

# Список скриптов для копирования
WRAPPER_SCRIPTS=(
    "manage_firewall.sh"
    "manage_vault_certs.sh"
    "call_rlm_api.sh"
)

declare -A SCRIPT_HASHES

for script in "${WRAPPER_SCRIPTS[@]}"; do
    src_file="${WRAPPERS_SRC_DIR}/${script}"
    dest_file="${SCRIPTS_DIR}/${script}"
    
    if [[ ! -f "$src_file" ]]; then
        print_error "Скрипт не найден: ${src_file}"
        exit 1
    fi
    
    print_info "Копирование: ${script}"
    cp "$src_file" "$dest_file"
    chmod +x "$dest_file"
    
    # Вычисление SHA256
    print_info "Вычисление SHA256 для: ${script}"
    local hash
    hash=$(sha256sum "$dest_file" | awk '{print $1}')
    SCRIPT_HASHES["$script"]="$hash"
    
    print_success "${script}: ${hash:0:16}..."
done

echo ""
print_success "Все скрипты-обертки сгенерированы и хеши вычислены"

# ==========================================
# ГЕНЕРАЦИЯ SUDOERS С ХЕШАМИ
# ==========================================

echo ""
print_step "ЭТАП 4: Генерация sudoers файлов"
echo ""

# Проверка наличия templates
TEMPLATES_DIR="$SCRIPT_DIR"
TEMPLATES=(
    "monitoring_ci_wrappers.template"
    "monitoring_admin_wrappers.template"
    "monitoring_ro_wrappers.template"
)

for template in "${TEMPLATES[@]}"; do
    if [[ ! -f "${TEMPLATES_DIR}/${template}" ]]; then
        print_error "Template не найден: ${template}"
        exit 1
    fi
done

print_success "Все templates найдены"
echo ""

# Генерация sudoers файлов
declare -A TEMPLATE_TO_USER=(
    ["monitoring_ci_wrappers.template"]="$USER_CI"
    ["monitoring_admin_wrappers.template"]="$USER_ADMIN"
    ["monitoring_ro_wrappers.template"]="$USER_RO"
)

for template in "${TEMPLATES[@]}"; do
    user="${TEMPLATE_TO_USER[$template]}"
    input_file="${TEMPLATES_DIR}/${template}"
    output_file="${SUDOERS_DIR}/${user}"
    
    print_info "Генерация sudoers для: ${user}"
    
    # Замена всех плейсхолдеров
    sed -e "s|{{USER_CI}}|${USER_CI}|g" \
        -e "s|{{USER_ADMIN}}|${USER_ADMIN}|g" \
        -e "s|{{USER_RO}}|${USER_RO}|g" \
        -e "s|{{USER_SYS}}|${USER_SYS}|g" \
        -e "s|{{SHA256_FIREWALL}}|${SCRIPT_HASHES['manage_firewall.sh']}|g" \
        -e "s|{{SHA256_CERTS}}|${SCRIPT_HASHES['manage_vault_certs.sh']}|g" \
        -e "s|{{SHA256_RLM}}|${SCRIPT_HASHES['call_rlm_api.sh']}|g" \
        "$input_file" > "$output_file"
    
    # Установка прав (readonly для безопасности)
    chmod 440 "$output_file"
    
    local file_size
    file_size=$(wc -c < "$output_file")
    print_success "Создан: ${user} (${file_size} байт)"
done

# ==========================================
# СОЗДАНИЕ ИНСТРУКЦИИ
# ==========================================

echo ""
print_step "ЭТАП 5: Создание инструкции для IDM"
echo ""

INSTRUCTIONS_FILE="${OUTPUT_DIR}/INSTRUCTIONS.md"

cat > "$INSTRUCTIONS_FILE" << EOF
# Инструкция по развертыванию sudoers через IDM

## Общая информация

**Стенд:** ${KAE_STEND}  
**Namespace:** ${NAMESPACE_CI}  
**Дата генерации:** $(date '+%Y-%m-%d %H:%M:%S')

---

## Сгенерированные файлы

### Sudoers файлы (готовы для копирования в IDM):

1. **${USER_CI}** - для ТУЗ (CI/CD)
2. **${USER_ADMIN}** - для ПУЗ (Admin)
3. **${USER_RO}** - для ReadOnly

### Скрипты-обертки:

1. **manage_firewall.sh** - управление firewall правилами
   - SHA256: \`${SCRIPT_HASHES['manage_firewall.sh']}\`

2. **manage_vault_certs.sh** - управление сертификатами
   - SHA256: \`${SCRIPT_HASHES['manage_vault_certs.sh']}\`

3. **call_rlm_api.sh** - вызовы RLM API
   - SHA256: \`${SCRIPT_HASHES['call_rlm_api.sh']}\`

---

## Шаг 1: Развертывание скриптов-оберток на сервере

Скрипты должны быть размещены в каталоге: \`/opt/monitoring/scripts/wrappers/\`

### Через Ansible (рекомендуется):

\`\`\`bash
# В playbook добавить задачу:
- name: Deploy wrapper scripts
  copy:
    src: scripts/{{ item }}
    dest: /opt/monitoring/scripts/wrappers/{{ item }}
    owner: ${USER_CI}
    group: ${USER_SYS}
    mode: '0750'
  loop:
    - manage_firewall.sh
    - manage_vault_certs.sh
    - call_rlm_api.sh
\`\`\`

### Вручную (для тестирования):

\`\`\`bash
# Создать директорию
sudo mkdir -p /opt/monitoring/scripts/wrappers

# Скопировать скрипты
sudo cp scripts/manage_firewall.sh /opt/monitoring/scripts/wrappers/
sudo cp scripts/manage_vault_certs.sh /opt/monitoring/scripts/wrappers/
sudo cp scripts/call_rlm_api.sh /opt/monitoring/scripts/wrappers/

# Установить права
sudo chown ${USER_CI}:${USER_SYS} /opt/monitoring/scripts/wrappers/*.sh
sudo chmod 750 /opt/monitoring/scripts/wrappers/*.sh
\`\`\`

**ВАЖНО:** После копирования проверить SHA256 хеши!

\`\`\`bash
sha256sum /opt/monitoring/scripts/wrappers/*.sh
\`\`\`

Хеши должны совпадать с указанными выше.

---

## Шаг 2: Создание заявок в IDM

### Для каждого пользователя (${USER_CI}, ${USER_ADMIN}, ${USER_RO}):

1. **Открыть IDM:** https://idm.sberbank.ru/

2. **Создать заявку** на предоставление sudo прав:
   - Тип заявки: "Права sudo для Linux"
   - Пользователь: \`${USER_CI}\` (или ${USER_ADMIN}, ${USER_RO})
   - Целевые серверы: [указать FQDN серверов]

3. **Содержимое sudoers** - скопировать из соответствующего файла:
   - Для ${USER_CI}: \`sudoers/${USER_CI}\`
   - Для ${USER_ADMIN}: \`sudoers/${USER_ADMIN}\`
   - Для ${USER_RO}: \`sudoers/${USER_RO}\`

4. **Обоснование:**
   ```
   Предоставление прав для развертывания и управления системой мониторинга.
   Используются скрипт-обертки с SHA256 хешами для обеспечения безопасности.
   Соответствует корпоративным требованиям кибербезопасности.
   ```

5. **Отправить на согласование**

---

## Шаг 3: Ожидание согласования

Заявки должны быть согласованы:
- Администраторами ОС целевых серверов
- Службой кибербезопасности
- IDM администраторами

**Время согласования:** обычно 1-3 рабочих дня

---

## Шаг 4: Проверка предоставленных прав

После согласования заявок, проверить права на сервере:

\`\`\`bash
# Проверка прав для CI_USER
sudo -l -U ${USER_CI}

# Проверка прав для ADMIN_USER
sudo -l -U ${USER_ADMIN}

# Проверка прав для RO_USER
sudo -l -U ${USER_RO}
\`\`\`

---

## Шаг 5: Повторный запуск Jenkins Pipeline

После того как:
1. ✅ Скрипты-обертки развернуты на сервере
2. ✅ SHA256 хеши проверены
3. ✅ Заявки в IDM согласованы
4. ✅ Права проверены на сервере

Можно запускать Jenkins Pipeline с параметром: **STAGE_MODE = deploy**

---

## Проверка корректности

### Проверка SHA256 хешей:

\`\`\`bash
# На сервере
sha256sum /opt/monitoring/scripts/wrappers/manage_firewall.sh
# Должно быть: ${SCRIPT_HASHES['manage_firewall.sh']}

sha256sum /opt/monitoring/scripts/wrappers/manage_vault_certs.sh
# Должно быть: ${SCRIPT_HASHES['manage_vault_certs.sh']}

sha256sum /opt/monitoring/scripts/wrappers/call_rlm_api.sh
# Должно быть: ${SCRIPT_HASHES['call_rlm_api.sh']}
\`\`\`

### Тестирование скриптов:

\`\`\`bash
# Тест firewall (от CI_USER)
sudo /opt/monitoring/scripts/wrappers/manage_firewall.sh check prometheus

# Тест RLM API (от CI_USER, требуются переменные окружения)
export RLM_API_URL="https://rlm.sigma.sbrf.ru"
export RLM_TOKEN="<your_token>"
sudo /opt/monitoring/scripts/wrappers/call_rlm_api.sh GET get_task_status 12345
\`\`\`

---

## Troubleshooting

### Проблема: SHA256 не совпадает

**Причина:** Скрипт был изменен после генерации sudoers.

**Решение:**
1. Удалить скрипт на сервере
2. Скопировать скрипт из директории \`scripts/\` (из этого архива)
3. Проверить хеш снова

### Проблема: sudo команда не работает

**Причина:** Заявка в IDM еще не обработана или отклонена.

**Решение:**
1. Проверить статус заявки в IDM
2. Убедиться что заявка согласована
3. Подождать 10-15 минут после согласования (синхронизация)

### Проблема: "Permission denied" при запуске скрипта

**Причина:** Неправильные права на скрипт.

**Решение:**
\`\`\`bash
sudo chmod 750 /opt/monitoring/scripts/wrappers/*.sh
sudo chown ${USER_CI}:${USER_SYS} /opt/monitoring/scripts/wrappers/*.sh
\`\`\`

---

## Контакты

При возникновении вопросов обращайтесь:
- Команда DevOps: [email]
- IDM поддержка: @idminfra
- Кибербезопасность: [email]

---

**Генератор:** \`generate_sudoers_with_hashes.sh\`  
**Версия:** 1.0
EOF

print_success "Инструкция создана: INSTRUCTIONS.md"

# ==========================================
# СОЗДАНИЕ README
# ==========================================

README_FILE="${OUTPUT_DIR}/README.txt"

cat > "$README_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════
  СГЕНЕРИРОВАННЫЕ SUDOERS ФАЙЛЫ ДЛЯ IDM
═══════════════════════════════════════════════════════════════════════════

Стенд:     ${KAE_STEND}
Namespace: ${NAMESPACE_CI}
Дата:      $(date '+%Y-%m-%d %H:%M:%S')

───────────────────────────────────────────────────────────────────────────
  СТРУКТУРА ДИРЕКТОРИИ
───────────────────────────────────────────────────────────────────────────

${OUTPUT_DIR}/
├── sudoers/                    # Sudoers файлы для IDM
│   ├── ${USER_CI}              # ТУЗ (CI/CD)
│   ├── ${USER_ADMIN}           # ПУЗ (Admin)
│   └── ${USER_RO}              # ReadOnly
├── scripts/                    # Скрипты-обертки
│   ├── manage_firewall.sh
│   ├── manage_vault_certs.sh
│   └── call_rlm_api.sh
├── INSTRUCTIONS.md             # Подробная инструкция
└── README.txt                  # Этот файл

───────────────────────────────────────────────────────────────────────────
  БЫСТРЫЙ СТАРТ
───────────────────────────────────────────────────────────────────────────

1. Прочитать INSTRUCTIONS.md (полная инструкция)

2. Развернуть скрипты на сервере:
   cp scripts/*.sh /opt/monitoring/scripts/wrappers/

3. Создать 3 заявки в IDM:
   - Для ${USER_CI}
   - Для ${USER_ADMIN}
   - Для ${USER_RO}

4. Скопировать содержимое файлов из sudoers/ в заявки IDM

5. Дождаться согласования

6. Запустить Jenkins Pipeline с STAGE_MODE=deploy

───────────────────────────────────────────────────────────────────────────
  SHA256 ХЕШИ СКРИПТОВ
───────────────────────────────────────────────────────────────────────────

manage_firewall.sh:
  ${SCRIPT_HASHES['manage_firewall.sh']}

manage_vault_certs.sh:
  ${SCRIPT_HASHES['manage_vault_certs.sh']}

call_rlm_api.sh:
  ${SCRIPT_HASHES['call_rlm_api.sh']}

───────────────────────────────────────────────────────────────────────────
  ВАЖНО!
───────────────────────────────────────────────────────────────────────────

После копирования скриптов на сервер, ОБЯЗАТЕЛЬНО проверьте SHA256:

  sha256sum /opt/monitoring/scripts/wrappers/*.sh

Хеши ДОЛЖНЫ совпадать с указанными выше!

═══════════════════════════════════════════════════════════════════════════
EOF

print_success "README создан: README.txt"

# ==========================================
# ФИНАЛЬНАЯ ИНФОРМАЦИЯ
# ==========================================

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                        ║${NC}"
echo -e "${GREEN}║  ✓ ГЕНЕРАЦИЯ ЗАВЕРШЕНА УСПЕШНО!                                       ║${NC}"
echo -e "${GREEN}║                                                                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  РЕЗУЛЬТАТЫ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Директория с файлами:${NC}"
echo "  ${OUTPUT_DIR}"
echo ""
echo -e "${BLUE}Сгенерированные sudoers файлы:${NC}"
echo "  ✓ ${USER_CI}"
echo "  ✓ ${USER_ADMIN}"
echo "  ✓ ${USER_RO}"
echo ""
echo -e "${BLUE}Скрипты-обертки:${NC}"
echo "  ✓ manage_firewall.sh"
echo "  ✓ manage_vault_certs.sh"
echo "  ✓ call_rlm_api.sh"
echo ""
echo -e "${BLUE}Документация:${NC}"
echo "  ✓ INSTRUCTIONS.md - подробная инструкция"
echo "  ✓ README.txt - краткое описание"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  СЛЕДУЮЩИЕ ШАГИ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "1️⃣  Прочитать инструкцию:"
echo "   ${CYAN}cat ${OUTPUT_DIR}/INSTRUCTIONS.md${NC}"
echo ""
echo "2️⃣  Развернуть скрипты на сервере:"
echo "   ${CYAN}scp -r ${OUTPUT_DIR}/scripts/*.sh user@server:/opt/monitoring/scripts/wrappers/${NC}"
echo ""
echo "3️⃣  Создать заявки в IDM (3 штуки):"
echo "   ${CYAN}https://idm.sberbank.ru/${NC}"
echo ""
echo "4️⃣  После согласования запустить Jenkins Pipeline:"
echo "   ${CYAN}STAGE_MODE = deploy${NC}"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Сохранение пути для дальнейшего использования
echo "$OUTPUT_DIR" > "${OUTPUT_BASE_DIR}/.last_generated_path"

print_success "Путь сохранен в: ${OUTPUT_BASE_DIR}/.last_generated_path"
echo ""

exit 0

