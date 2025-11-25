#!/bin/bash
################################################################################
# Wrapper: Извлечение секретов из JSON в отдельные файлы
################################################################################
# Назначение: Безопасное извлечение role_id и secret_id из secrets.json
# Использование: sudo -u SYS_USER /opt/monitoring/scripts/extract_vault_secrets.sh
# Требования: jq установлен, secrets.json существует в /dev/shm/monitoring_secrets
################################################################################

set -euo pipefail

# ==========================================
# КОНСТАНТЫ
# ==========================================

readonly SECRETS_DIR="/dev/shm/monitoring_secrets"
readonly SECRETS_FILE="${SECRETS_DIR}/secrets.json"
readonly ROLE_ID_FILE="${SECRETS_DIR}/role_id.txt"
readonly SECRET_ID_FILE="${SECRETS_DIR}/secret_id.txt"

# ==========================================
# ФУНКЦИИ
# ==========================================

print_error() {
    echo "[ERROR] $*" >&2
}

print_info() {
    echo "[INFO] $*"
}

# ==========================================
# ВАЛИДАЦИЯ
# ==========================================

# Проверка существования директории
if [[ ! -d "$SECRETS_DIR" ]]; then
    print_error "Директория ${SECRETS_DIR} не существует"
    exit 1
fi

# Проверка существования secrets.json
if [[ ! -f "$SECRETS_FILE" ]]; then
    print_error "Файл ${SECRETS_FILE} не существует"
    exit 1
fi

# Проверка прав на чтение secrets.json
if [[ ! -r "$SECRETS_FILE" ]]; then
    print_error "Нет прав на чтение ${SECRETS_FILE}"
    exit 1
fi

# Проверка что это валидный JSON
if ! jq empty "$SECRETS_FILE" 2>/dev/null; then
    print_error "Файл ${SECRETS_FILE} содержит невалидный JSON"
    exit 1
fi

# Проверка наличия ключа vault-agent
if ! jq -e '.["vault-agent"]' "$SECRETS_FILE" >/dev/null 2>&1; then
    print_error "Ключ 'vault-agent' не найден в ${SECRETS_FILE}"
    exit 1
fi

# ==========================================
# ИЗВЛЕЧЕНИЕ СЕКРЕТОВ
# ==========================================

print_info "Извлечение role_id из secrets.json..."
if ! jq -r '.["vault-agent"].role_id' "$SECRETS_FILE" > "$ROLE_ID_FILE"; then
    print_error "Не удалось извлечь role_id"
    exit 1
fi

print_info "Извлечение secret_id из secrets.json..."
if ! jq -r '.["vault-agent"].secret_id' "$SECRETS_FILE" > "$SECRET_ID_FILE"; then
    print_error "Не удалось извлечь secret_id"
    exit 1
fi

# ==========================================
# УСТАНОВКА ПРАВ
# ==========================================

print_info "Установка прав 600 на извлеченные файлы..."
if ! chmod 600 "$ROLE_ID_FILE" "$SECRET_ID_FILE"; then
    print_error "Не удалось установить права на файлы"
    exit 1
fi

# ==========================================
# ПРОВЕРКА РЕЗУЛЬТАТА
# ==========================================

# Проверка что файлы не пустые
if [[ ! -s "$ROLE_ID_FILE" ]]; then
    print_error "Файл ${ROLE_ID_FILE} пустой"
    exit 1
fi

if [[ ! -s "$SECRET_ID_FILE" ]]; then
    print_error "Файл ${SECRET_ID_FILE} пустой"
    exit 1
fi

print_info "✓ Секреты успешно извлечены:"
print_info "  - ${ROLE_ID_FILE} ($(wc -c < "$ROLE_ID_FILE") bytes)"
print_info "  - ${SECRET_ID_FILE} ($(wc -c < "$SECRET_ID_FILE") bytes)"

exit 0


