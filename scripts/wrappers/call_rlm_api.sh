#!/bin/bash
################################################################################
# Скрипт-обертка для вызовов RLM API
################################################################################
#
# Назначение:
#   Безопасное обращение к RLM API с валидацией всех параметров
#
# Использование:
#   ./call_rlm_api.sh <METHOD> <ENDPOINT> <TASK_ID>
#
# Параметры:
#   METHOD   - HTTP метод: POST | GET
#   ENDPOINT - API endpoint: create_task | get_task_status
#   TASK_ID  - ID задачи (только для GET, опционально для POST)
#
# Примеры:
#   ./call_rlm_api.sh POST create_task
#   ./call_rlm_api.sh GET get_task_status 12345
#
# Переменные окружения:
#   RLM_API_URL - Base URL для RLM API
#   RLM_TOKEN   - Токен авторизации
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
# WHITELIST ENDPOINTS И МЕТОДОВ
# ==========================================

# Допустимые HTTP методы
declare -A ALLOWED_METHODS=(
    ["POST"]="1"
    ["GET"]="1"
)

# Допустимые endpoints (IMMUTABLE)
declare -A ALLOWED_ENDPOINTS=(
    ["create_task"]="/api/tasks.json"
    ["get_task_status"]="/api/tasks/"
)

# Базовый URL для RLM (должен быть в whitelist)
readonly RLM_BASE_DOMAIN="rlm.sigma.sbrf.ru"

# ==========================================
# ВАЛИДАЦИЯ
# ==========================================

validate_method() {
    local method="$1"
    
    if [[ ! -v ALLOWED_METHODS["$method"] ]]; then
        print_error "Недопустимый HTTP метод: ${method}"
        echo "Допустимые методы: ${!ALLOWED_METHODS[*]}"
        return 1
    fi
    
    return 0
}

validate_endpoint() {
    local endpoint="$1"
    
    if [[ ! -v ALLOWED_ENDPOINTS["$endpoint"] ]]; then
        print_error "Недопустимый endpoint: ${endpoint}"
        echo "Допустимые endpoints: ${!ALLOWED_ENDPOINTS[*]}"
        return 1
    fi
    
    return 0
}

validate_task_id() {
    local task_id="$1"
    
    # Task ID должен содержать только цифры
    if [[ ! "$task_id" =~ ^[0-9]+$ ]]; then
        print_error "Недопустимый Task ID: ${task_id}"
        echo "Task ID должен содержать только цифры"
        return 1
    fi
    
    # Проверка длины (разумное ограничение)
    if [[ ${#task_id} -gt 20 ]]; then
        print_error "Task ID слишком длинный: ${task_id}"
        return 1
    fi
    
    return 0
}

validate_rlm_url() {
    local url="$1"
    
    # Проверка что URL содержит разрешенный домен
    if [[ ! "$url" =~ ${RLM_BASE_DOMAIN} ]]; then
        print_error "Недопустимый RLM URL: ${url}"
        echo "URL должен содержать: ${RLM_BASE_DOMAIN}"
        return 1
    fi
    
    # Проверка протокола (только https)
    if [[ ! "$url" =~ ^https:// ]]; then
        print_error "URL должен использовать HTTPS протокол"
        return 1
    fi
    
    return 0
}

validate_token() {
    local token="$1"
    
    # Токен не должен быть пустым
    if [[ -z "$token" ]]; then
        print_error "RLM_TOKEN не установлен"
        return 1
    fi
    
    # Минимальная длина токена (для безопасности)
    if [[ ${#token} -lt 20 ]]; then
        print_error "RLM_TOKEN слишком короткий (возможно некорректный)"
        return 1
    fi
    
    # Токен должен содержать только безопасные символы
    if [[ ! "$token" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "RLM_TOKEN содержит недопустимые символы"
        return 1
    fi
    
    return 0
}

# ==========================================
# ФУНКЦИИ API
# ==========================================

call_rlm_api() {
    local method="$1"
    local endpoint_key="$2"
    local task_id="${3:-}"
    
    # Получение endpoint из whitelist
    local endpoint_path="${ALLOWED_ENDPOINTS[$endpoint_key]}"
    
    # Формирование полного URL
    local full_url
    if [[ "$endpoint_key" == "get_task_status" ]]; then
        if [[ -z "$task_id" ]]; then
            print_error "Для get_task_status требуется Task ID"
            return 1
        fi
        full_url="${RLM_API_URL}${endpoint_path}${task_id}/"
    else
        full_url="${RLM_API_URL}${endpoint_path}"
    fi
    
    print_info "URL: ${full_url}"
    
    # Базовые параметры curl
    local curl_opts=(
        -k                                    # Игнорировать SSL (внутренний сертификат)
        -s                                    # Silent mode
        -X "$method"                          # HTTP метод
        -H "Accept: application/json"        # Accept header
        -H "Authorization: Token ${RLM_TOKEN}" # Auth header
        -H "Content-Type: application/json"  # Content-Type
    )
    
    # Выполнение запроса
    local response
    response=$(/usr/bin/curl "${curl_opts[@]}" "$full_url")
    
    # Проверка что ответ не пустой
    if [[ -z "$response" ]]; then
        print_error "Получен пустой ответ от RLM API"
        return 1
    fi
    
    # Проверка что ответ - валидный JSON
    if ! echo "$response" | /usr/bin/jq empty 2>/dev/null; then
        print_error "Получен невалидный JSON от RLM API"
        echo "Ответ: ${response}"
        return 1
    fi
    
    # Вывод ответа
    echo "$response"
}

# ==========================================
# ОСНОВНАЯ ЛОГИКА
# ==========================================

main() {
    if [[ $# -lt 2 ]]; then
        print_error "Недостаточно аргументов"
        echo "Использование: $0 <METHOD> <ENDPOINT> [TASK_ID]"
        echo "  METHOD:   POST | GET"
        echo "  ENDPOINT: create_task | get_task_status"
        echo "  TASK_ID:  ID задачи (для GET)"
        exit 1
    fi
    
    local method="$1"
    local endpoint="$2"
    local task_id="${3:-}"
    
    # Проверка переменных окружения
    if [[ -z "${RLM_API_URL:-}" ]]; then
        print_error "Переменная RLM_API_URL не установлена"
        exit 1
    fi
    
    if [[ -z "${RLM_TOKEN:-}" ]]; then
        print_error "Переменная RLM_TOKEN не установлена"
        exit 1
    fi
    
    # Валидация параметров
    if ! validate_method "$method"; then
        exit 1
    fi
    
    if ! validate_endpoint "$endpoint"; then
        exit 1
    fi
    
    if ! validate_rlm_url "$RLM_API_URL"; then
        exit 1
    fi
    
    if ! validate_token "$RLM_TOKEN"; then
        exit 1
    fi
    
    if [[ -n "$task_id" ]] && ! validate_task_id "$task_id"; then
        exit 1
    fi
    
    # Вызов API
    print_info "Вызов RLM API: ${method} ${endpoint}"
    
    local response
    if ! response=$(call_rlm_api "$method" "$endpoint" "$task_id"); then
        print_error "Ошибка при вызове RLM API"
        exit 1
    fi
    
    print_success "Запрос выполнен успешно"
    echo "$response"
}

# Запуск
main "$@"





