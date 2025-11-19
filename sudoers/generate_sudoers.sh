#!/bin/bash
################################################################################
# Скрипт генерации sudoers файлов для динамических имен пользователей
################################################################################
#
# Назначение:
#   Генерация sudoers файлов для конкретного KAE_STEND на основе шаблонов
#
# Использование:
#   ./generate_sudoers.sh <NAMESPACE_CI>
#
# Пример:
#   ./generate_sudoers.sh CI04523276_CI10742292
#
# Результат:
#   Создается директория sudoers/{KAE_STEND}/ с файлами:
#   - {KAE_STEND}-lnx-mon_ci
#   - {KAE_STEND}-lnx-mon_admin
#   - {KAE_STEND}-lnx-mon_ro
#
################################################################################

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Функция помощи
usage() {
    cat << EOF
${BLUE}================================================================
  Генератор sudoers файлов для динамических пользователей
================================================================${NC}

${GREEN}Использование:${NC}
  $0 <NAMESPACE_CI>

${GREEN}Пример:${NC}
  $0 CI04523276_CI10742292

${GREEN}Описание:${NC}
  Скрипт извлекает KAE_STEND из NAMESPACE_CI и генерирует
  sudoers файлы с явно указанными именами пользователей.

${GREEN}Требования:${NC}
  - NAMESPACE_CI должен содержать разделитель '_'
  - KAE_STEND может содержать только: буквы, цифры, дефис
  - Длина KAE_STEND: 3-20 символов
  - Наличие шаблонов: monitoring_ci, monitoring_admin, monitoring_ro

${GREEN}Вывод:${NC}
  sudoers/{KAE_STEND}/
  ├── {KAE_STEND}-lnx-mon_ci
  ├── {KAE_STEND}-lnx-mon_admin
  └── {KAE_STEND}-lnx-mon_ro

EOF
    exit 1
}

# Проверка аргументов
if [[ $# -ne 1 ]]; then
    print_error "Неверное количество аргументов"
    usage
fi

NAMESPACE_CI="$1"

echo -e "${BLUE}================================================================"
echo "  Генерация sudoers файлов"
echo -e "================================================================${NC}"
echo ""

# ==========================================
# ВАЛИДАЦИЯ NAMESPACE_CI
# ==========================================

print_info "Валидация NAMESPACE_CI: ${NAMESPACE_CI}"

# Проверка формата
if [[ ! "$NAMESPACE_CI" =~ _ ]]; then
    print_error "NAMESPACE_CI должен содержать разделитель '_'"
    echo "Пример правильного формата: CI04523276_CI10742292"
    exit 1
fi

print_success "NAMESPACE_CI содержит разделитель '_'"

# ==========================================
# ИЗВЛЕЧЕНИЕ KAE_STEND
# ==========================================

# Извлечение части после последнего '_'
KAE_STEND="${NAMESPACE_CI##*_}"

print_info "Извлеченный KAE_STEND: ${KAE_STEND}"

# ==========================================
# ВАЛИДАЦИЯ KAE_STEND
# ==========================================

# Проверка на недопустимые символы
if [[ ! "$KAE_STEND" =~ ^[a-zA-Z0-9-]+$ ]]; then
    print_error "KAE_STEND содержит недопустимые символы: ${KAE_STEND}"
    echo "Допустимы только: буквы (a-z, A-Z), цифры (0-9), дефис (-)"
    exit 1
fi

print_success "KAE_STEND содержит только допустимые символы"

# Проверка длины
if [[ ${#KAE_STEND} -lt 3 ]]; then
    print_error "KAE_STEND слишком короткий: ${KAE_STEND} (${#KAE_STEND} символов)"
    echo "Минимальная длина: 3 символа"
    exit 1
fi

if [[ ${#KAE_STEND} -gt 20 ]]; then
    print_error "KAE_STEND слишком длинный: ${KAE_STEND} (${#KAE_STEND} символов)"
    echo "Максимальная длина: 20 символов"
    exit 1
fi

print_success "Длина KAE_STEND допустима: ${#KAE_STEND} символов"

# ==========================================
# ФОРМИРОВАНИЕ ИМЕН ПОЛЬЗОВАТЕЛЕЙ
# ==========================================

USER_SYS="${KAE_STEND}-lnx-mon_sys"
USER_ADMIN="${KAE_STEND}-lnx-mon_admin"
USER_CI="${KAE_STEND}-lnx-mon_ci"
USER_RO="${KAE_STEND}-lnx-mon_ro"

echo ""
echo -e "${BLUE}Сформированные имена пользователей:${NC}"
echo "  - Сервисная (СУЗ):     ${USER_SYS}"
echo "  - Администратор (ПУЗ): ${USER_ADMIN}"
echo "  - CI/CD (ТУЗ):         ${USER_CI}"
echo "  - ReadOnly:            ${USER_RO}"
echo ""

# Проверка длины финальных имен (max 32 символа для Linux/IDM)
for user in "$USER_SYS" "$USER_ADMIN" "$USER_CI" "$USER_RO"; do
    if [[ ${#user} -gt 32 ]]; then
        print_error "Имя пользователя слишком длинное (>${#user}): ${user}"
        echo "Максимальная длина: 32 символа (требование Linux/IDM)"
        exit 1
    fi
done

print_success "Все имена пользователей соответствуют требованиям (≤32 символа)"

# ==========================================
# ПОДГОТОВКА ДИРЕКТОРИИ
# ==========================================

# Определение базовой директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/${KAE_STEND}"

print_info "Создание директории: ${OUTPUT_DIR}"

if [[ -d "$OUTPUT_DIR" ]]; then
    print_warning "Директория уже существует: ${OUTPUT_DIR}"
    read -p "Перезаписать? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Отменено пользователем"
        exit 0
    fi
    rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"
print_success "Директория создана"

# ==========================================
# ПРОВЕРКА ШАБЛОНОВ
# ==========================================

echo ""
print_info "Проверка наличия шаблонов..."

TEMPLATES=("monitoring_ci.template" "monitoring_admin.template" "monitoring_ro.template")
MISSING_TEMPLATES=()

for template in "${TEMPLATES[@]}"; do
    if [[ ! -f "${SCRIPT_DIR}/${template}" ]]; then
        MISSING_TEMPLATES+=("$template")
        print_error "Шаблон не найден: ${template}"
    else
        print_success "Шаблон найден: ${template}"
    fi
done

if [[ ${#MISSING_TEMPLATES[@]} -gt 0 ]]; then
    print_error "Отсутствуют необходимые шаблоны!"
    echo "Убедитесь что в директории ${SCRIPT_DIR} есть файлы:"
    for template in "${MISSING_TEMPLATES[@]}"; do
        echo "  - ${template}"
    done
    exit 1
fi

# ==========================================
# ГЕНЕРАЦИЯ ФАЙЛОВ
# ==========================================

echo ""
echo -e "${BLUE}================================================================"
echo "  Генерация sudoers файлов"
echo -e "================================================================${NC}"
echo ""

GENERATED_FILES=()

# Маппинг шаблонов (используем .template файлы)
declare -A TEMPLATE_MAP=(
    ["monitoring_ci.template"]="${USER_CI}"
    ["monitoring_admin.template"]="${USER_ADMIN}"
    ["monitoring_ro.template"]="${USER_RO}"
)

# Обновляем список шаблонов
TEMPLATES=("monitoring_ci.template" "monitoring_admin.template" "monitoring_ro.template")

for template in "${TEMPLATES[@]}"; do
    output_name="${TEMPLATE_MAP[$template]}"
    output_file="${OUTPUT_DIR}/${output_name}"
    
    print_info "Обработка шаблона: ${template} → ${output_name}"
    
    # Замена плейсхолдеров {{USER_*}} на реальные имена
    sed -e "s/{{USER_CI}}/${USER_CI}/g" \
        -e "s/{{USER_ADMIN}}/${USER_ADMIN}/g" \
        -e "s/{{USER_RO}}/${USER_RO}/g" \
        -e "s/{{USER_SYS}}/${USER_SYS}/g" \
        "${SCRIPT_DIR}/${template}" > "${output_file}"
    
    if [[ -f "$output_file" ]]; then
        file_size=$(wc -c < "$output_file")
        print_success "Создан: ${output_name} (${file_size} байт)"
        GENERATED_FILES+=("$output_file")
    else
        print_error "Не удалось создать: ${output_name}"
        exit 1
    fi
done

# ==========================================
# ПРОВЕРКА СИНТАКСИСА
# ==========================================

echo ""
echo -e "${BLUE}================================================================"
echo "  Проверка синтаксиса sudoers"
echo -e "================================================================${NC}"
echo ""

if ! command -v visudo &> /dev/null; then
    print_warning "Утилита 'visudo' не найдена, пропускаем проверку синтаксиса"
    print_info "Установите sudo для проверки: yum install sudo"
else
    SYNTAX_ERRORS=0
    
    for file in "${GENERATED_FILES[@]}"; do
        filename=$(basename "$file")
        print_info "Проверка: ${filename}"
        
        if sudo visudo -c -f "$file" &> /dev/null; then
            print_success "Синтаксис корректен: ${filename}"
        else
            print_error "Ошибка синтаксиса: ${filename}"
            sudo visudo -c -f "$file"
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    done
    
    if [[ $SYNTAX_ERRORS -gt 0 ]]; then
        print_error "Обнаружены ошибки синтаксиса в ${SYNTAX_ERRORS} файл(ах)"
        exit 1
    fi
fi

# ==========================================
# ИТОГОВАЯ ИНФОРМАЦИЯ
# ==========================================

echo ""
echo -e "${GREEN}================================================================"
echo "  ✓ ГЕНЕРАЦИЯ ЗАВЕРШЕНА УСПЕШНО"
echo -e "================================================================${NC}"
echo ""
echo -e "${BLUE}Созданные файлы:${NC}"
for file in "${GENERATED_FILES[@]}"; do
    echo "  ✓ $(basename "$file")"
done
echo ""
echo -e "${BLUE}Директория с файлами:${NC}"
echo "  ${OUTPUT_DIR}"
echo ""

# ==========================================
# СЛЕДУЮЩИЕ ШАГИ
# ==========================================

echo -e "${YELLOW}================================================================"
echo "  СЛЕДУЮЩИЕ ШАГИ"
echo -e "================================================================${NC}"
echo ""
echo "1. Просмотреть сгенерированные файлы:"
echo "   cd ${OUTPUT_DIR}"
echo "   ls -lah"
echo ""
echo "2. Скопировать на целевой сервер:"
echo "   scp ${OUTPUT_DIR}/* user@server:/tmp/"
echo ""
echo "3. На сервере разместить в /etc/sudoers.d/:"
echo "   sudo cp /tmp/${USER_CI} /etc/sudoers.d/"
echo "   sudo cp /tmp/${USER_ADMIN} /etc/sudoers.d/"
echo "   sudo cp /tmp/${USER_RO} /etc/sudoers.d/"
echo ""
echo "4. Установить права:"
echo "   sudo chmod 440 /etc/sudoers.d/${USER_CI}"
echo "   sudo chmod 440 /etc/sudoers.d/${USER_ADMIN}"
echo "   sudo chmod 440 /etc/sudoers.d/${USER_RO}"
echo "   sudo chown root:root /etc/sudoers.d/${USER_CI}"
echo "   sudo chown root:root /etc/sudoers.d/${USER_ADMIN}"
echo "   sudo chown root:root /etc/sudoers.d/${USER_RO}"
echo ""
echo "5. Проверить права пользователей:"
echo "   sudo -l -U ${USER_CI}"
echo "   sudo -l -U ${USER_ADMIN}"
echo "   sudo -l -U ${USER_RO}"
echo ""
echo -e "${GREEN}Готово!${NC}"

