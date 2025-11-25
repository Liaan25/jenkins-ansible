#!/bin/bash
################################################################################
# Скрипт-обертка для управления сертификатами из Vault
################################################################################
#
# Назначение:
#   Безопасная обработка сертификатов с валидацией путей и прав доступа
#
# Использование:
#   ./manage_vault_certs.sh <ACTION> <SOURCE> <DEST> [OWNER:GROUP]
#
# Параметры:
#   ACTION - Действие: split_bundle | copy | set_permissions
#   SOURCE - Путь к источнику (только /opt/monitoring/certs/)
#   DEST   - Путь к назначению (только /opt/monitoring/certs/)
#   OWNER  - Владелец:группа (опционально)
#
# Примеры:
#   ./manage_vault_certs.sh split_bundle /opt/monitoring/certs/server_bundle.pem /opt/monitoring/certs/
#   ./manage_vault_certs.sh copy /opt/monitoring/certs/ca.crt /opt/monitoring/certs/prometheus/
#   ./manage_vault_certs.sh set_permissions /opt/monitoring/certs/server.key monitoring_sys:monitoring_sys
#
################################################################################

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Функции вывода
print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ==========================================
# WHITELIST ПУТЕЙ
# ==========================================

# Базовый каталог для сертификатов (IMMUTABLE)
readonly ALLOWED_BASE_DIR="/opt/monitoring/certs"

# Допустимые действия
declare -A ALLOWED_ACTIONS=(
    ["split_bundle"]="1"
    ["copy"]="1"
    ["set_permissions"]="1"
)

# ==========================================
# ВАЛИДАЦИЯ
# ==========================================

validate_action() {
    local action="$1"
    
    if [[ ! -v ALLOWED_ACTIONS["$action"] ]]; then
        print_error "Недопустимое действие: ${action}"
        echo "Допустимые действия: ${!ALLOWED_ACTIONS[*]}"
        return 1
    fi
    
    return 0
}

validate_path() {
    local path="$1"
    local path_type="$2"
    
    # Преобразование в абсолютный путь
    local abs_path
    abs_path=$(readlink -m "$path")
    
    # Проверка что путь начинается с разрешенного базового каталога
    if [[ ! "$abs_path" =~ ^${ALLOWED_BASE_DIR} ]]; then
        print_error "Недопустимый путь (${path_type}): ${path}"
        echo "Путь должен быть внутри: ${ALLOWED_BASE_DIR}"
        return 1
    fi
    
    # Проверка на path traversal атаки
    if [[ "$path" =~ \.\. ]]; then
        print_error "Обнаружена попытка path traversal: ${path}"
        return 1
    fi
    
    return 0
}

validate_owner() {
    local owner="$1"
    
    # Формат: user:group
    if [[ ! "$owner" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$ ]]; then
        print_error "Недопустимый формат владельца: ${owner}"
        echo "Формат должен быть: user:group"
        return 1
    fi
    
    return 0
}

# ==========================================
# ФУНКЦИИ ОБРАБОТКИ СЕРТИФИКАТОВ
# ==========================================

split_bundle() {
    local bundle_path="$1"
    local output_dir="$2"
    
    if [[ ! -f "$bundle_path" ]]; then
        print_error "Файл bundle не найден: ${bundle_path}"
        return 1
    fi
    
    if [[ ! -d "$output_dir" ]]; then
        print_error "Директория назначения не найдена: ${output_dir}"
        return 1
    fi
    
    local basename
    basename=$(basename "$bundle_path" .pem)
    
    local key_file="${output_dir}/${basename}.key"
    local cert_file="${output_dir}/${basename}.crt"
    
    print_info "Извлечение private key в ${key_file}"
    /usr/bin/openssl pkey -in "$bundle_path" -out "$key_file" 2>/dev/null
    
    print_info "Извлечение certificate в ${cert_file}"
    /usr/bin/openssl crl2pkcs7 -nocrl -certfile "$bundle_path" | \
        /usr/bin/openssl pkcs7 -print_certs -out "$cert_file" 2>/dev/null
    
    print_success "Bundle разделен: ${basename}.key, ${basename}.crt"
}

copy_cert() {
    local source="$1"
    local dest="$2"
    
    if [[ ! -f "$source" ]]; then
        print_error "Исходный файл не найден: ${source}"
        return 1
    fi
    
    # Если dest - директория, создаем файл с тем же именем
    if [[ -d "$dest" ]]; then
        dest="${dest}/$(basename "$source")"
    fi
    
    /usr/bin/cp -f "$source" "$dest"
    print_success "Файл скопирован: $(basename "$dest")"
}

set_cert_permissions() {
    local cert_path="$1"
    local owner="$2"
    
    if [[ ! -e "$cert_path" ]]; then
        print_error "Файл/директория не найдена: ${cert_path}"
        return 1
    fi
    
    # Определение типа файла и установка соответствующих прав
    if [[ -f "$cert_path" ]]; then
        if [[ "$cert_path" =~ \.key$ ]]; then
            # Private key - 600
            /usr/bin/chmod 600 "$cert_path"
            print_info "Установлены права 600 для private key"
        else
            # Certificate - 644
            /usr/bin/chmod 644 "$cert_path"
            print_info "Установлены права 644 для certificate"
        fi
    elif [[ -d "$cert_path" ]]; then
        # Директория - 750
        /usr/bin/chmod 750 "$cert_path"
        print_info "Установлены права 750 для директории"
    fi
    
    # Установка владельца
    /usr/bin/chown "$owner" "$cert_path"
    print_success "Владелец установлен: ${owner}"
}

# ==========================================
# ОСНОВНАЯ ЛОГИКА
# ==========================================

main() {
    if [[ $# -lt 3 ]]; then
        print_error "Недостаточно аргументов"
        echo "Использование: $0 <ACTION> <SOURCE> <DEST> [OWNER:GROUP]"
        exit 1
    fi
    
    local action="$1"
    local source="$2"
    local dest="$3"
    local owner="${4:-}"
    
    print_info "Действие: ${action}"
    
    # Валидация действия
    if ! validate_action "$action"; then
        exit 1
    fi
    
    # Валидация путей
    if ! validate_path "$source" "source"; then
        exit 1
    fi
    
    if ! validate_path "$dest" "dest"; then
        exit 1
    fi
    
    # Валидация владельца (если указан)
    if [[ -n "$owner" ]] && ! validate_owner "$owner"; then
        exit 1
    fi
    
    # Выполнение действия
    case "$action" in
        split_bundle)
            split_bundle "$source" "$dest"
            ;;
        copy)
            copy_cert "$source" "$dest"
            ;;
        set_permissions)
            if [[ -z "$owner" ]]; then
                print_error "Для действия set_permissions требуется параметр OWNER:GROUP"
                exit 1
            fi
            set_cert_permissions "$source" "$owner"
            ;;
    esac
    
    print_success "Операция завершена"
}

# Запуск
main "$@"



