#!/bin/bash
# Скрипт управления секретами в /dev/shm
# Должен запускаться от имени monitoring_svc

set -euo pipefail

# ==============================================================================
# КОНФИГУРАЦИЯ
# ==============================================================================

SECRETS_DIR="/dev/shm/monitoring_secrets"
REQUIRED_USER="monitoring_svc"
VAULT_BUNDLE="/opt/vault/certs/server_bundle.pem"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==============================================================================
# ФУНКЦИИ
# ==============================================================================

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo "[INFO] $1"
}

# Проверка пользователя
check_user() {
    local current_user
    current_user=$(whoami)
    
    if [[ "$current_user" != "$REQUIRED_USER" ]]; then
        print_error "Этот скрипт должен запускаться от имени $REQUIRED_USER"
        print_info "Текущий пользователь: $current_user"
        print_info "Используйте: sudo -u $REQUIRED_USER $0"
        exit 1
    fi
}

# Создание директории для секретов
create_secrets_dir() {
    print_info "Создание директории для секретов..."
    
    if [[ ! -d "$SECRETS_DIR" ]]; then
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        print_success "Директория создана: $SECRETS_DIR"
    else
        print_info "Директория уже существует: $SECRETS_DIR"
    fi
    
    # Проверка прав
    local perms
    perms=$(stat -c '%a' "$SECRETS_DIR")
    
    if [[ "$perms" != "700" ]]; then
        print_warning "Неправильные права на $SECRETS_DIR: $perms (ожидается: 700)"
        chmod 700 "$SECRETS_DIR"
        print_success "Права исправлены на 700"
    fi
}

# Разделение bundle на отдельные файлы
split_certificates() {
    print_info "Разделение сертификатов..."
    
    if [[ ! -f "$VAULT_BUNDLE" ]]; then
        print_error "Файл bundle не найден: $VAULT_BUNDLE"
        return 1
    fi
    
    # Извлечь приватный ключ
    if openssl pkey -in "$VAULT_BUNDLE" -out "$SECRETS_DIR/server.key" 2>/dev/null; then
        chmod 600 "$SECRETS_DIR/server.key"
        print_success "Приватный ключ извлечен: $SECRETS_DIR/server.key"
    else
        print_error "Не удалось извлечь приватный ключ"
        return 1
    fi
    
    # Извлечь сертификат
    if openssl crl2pkcs7 -nocrl -certfile "$VAULT_BUNDLE" | \
       openssl pkcs7 -print_certs -out "$SECRETS_DIR/server.crt" 2>/dev/null; then
        chmod 640 "$SECRETS_DIR/server.crt"
        print_success "Сертификат извлечен: $SECRETS_DIR/server.crt"
    else
        print_error "Не удалось извлечь сертификат"
        return 1
    fi
}

# Проверка срока действия сертификата
check_certificate_expiry() {
    print_info "Проверка срока действия сертификатов..."
    
    for cert_file in "$SECRETS_DIR"/*.crt; do
        if [[ ! -f "$cert_file" ]]; then
            continue
        fi
        
        local cert_name
        cert_name=$(basename "$cert_file")
        
        local expiry_date
        expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [[ -z "$expiry_date" ]]; then
            print_warning "Не удалось определить срок действия: $cert_name"
            continue
        fi
        
        local expiry_epoch
        expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch
        current_epoch=$(date +%s)
        local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_left -lt 0 ]]; then
            print_error "$cert_name: ИСТЕК $((days_left * -1)) дней назад!"
        elif [[ $days_left -lt 7 ]]; then
            print_warning "$cert_name: Истекает через $days_left дней"
        else
            print_success "$cert_name: Действителен еще $days_left дней"
        fi
    done
}

# Проверка соответствия ключа и сертификата
verify_key_cert_match() {
    print_info "Проверка соответствия ключа и сертификата..."
    
    local cert="$SECRETS_DIR/server.crt"
    local key="$SECRETS_DIR/server.key"
    
    if [[ ! -f "$cert" ]] || [[ ! -f "$key" ]]; then
        print_error "Сертификат или ключ не найдены"
        return 1
    fi
    
    local cert_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert" 2>/dev/null | openssl md5)
    
    local key_modulus
    key_modulus=$(openssl rsa -noout -modulus -in "$key" 2>/dev/null | openssl md5)
    
    if [[ "$cert_modulus" == "$key_modulus" ]]; then
        print_success "Ключ и сертификат соответствуют друг другу"
    else
        print_error "Ключ и сертификат НЕ СООТВЕТСТВУЮТ!"
        return 1
    fi
}

# Вывод информации о секретах
list_secrets() {
    print_info "Список секретов в $SECRETS_DIR:"
    
    if [[ ! -d "$SECRETS_DIR" ]]; then
        print_warning "Директория не существует: $SECRETS_DIR"
        return 1
    fi
    
    echo ""
    ls -lh "$SECRETS_DIR"
    echo ""
    
    # Подсчет файлов
    local file_count
    file_count=$(find "$SECRETS_DIR" -type f | wc -l)
    print_info "Всего файлов: $file_count"
}

# Очистка секретов
cleanup_secrets() {
    print_info "Очистка секретов..."
    
    if [[ ! -d "$SECRETS_DIR" ]]; then
        print_info "Директория не существует: $SECRETS_DIR"
        return 0
    fi
    
    print_warning "Это удалит ВСЕ файлы из $SECRETS_DIR"
    read -p "Продолжить? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_info "Отменено пользователем"
        return 0
    fi
    
    rm -rf "$SECRETS_DIR"/*
    print_success "Секреты удалены"
}

# ==============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# ==============================================================================

main() {
    local action="${1:-help}"
    
    case "$action" in
        create)
            check_user
            create_secrets_dir
            ;;
        split)
            check_user
            create_secrets_dir
            split_certificates
            verify_key_cert_match
            check_certificate_expiry
            ;;
        check)
            check_user
            check_certificate_expiry
            verify_key_cert_match
            ;;
        list)
            check_user
            list_secrets
            ;;
        cleanup)
            check_user
            cleanup_secrets
            ;;
        help|*)
            echo "Использование: $0 {create|split|check|list|cleanup}"
            echo ""
            echo "Команды:"
            echo "  create   - Создать директорию для секретов"
            echo "  split    - Разделить bundle на отдельные файлы"
            echo "  check    - Проверить срок действия и соответствие"
            echo "  list     - Показать список секретов"
            echo "  cleanup  - Удалить все секреты"
            echo ""
            echo "Пример:"
            echo "  sudo -u monitoring_svc $0 create"
            echo "  sudo -u monitoring_svc $0 split"
            echo "  sudo -u monitoring_svc $0 check"
            exit 0
            ;;
    esac
}

main "$@"


