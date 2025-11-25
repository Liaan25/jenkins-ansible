#!/bin/bash
# Скрипт автоматической очистки секретов
# Используется при деплое или перезагрузке

set -euo pipefail

SECRETS_DIR="/dev/shm/monitoring_secrets"

echo "[INFO] Очистка секретов в $SECRETS_DIR"

if [[ -d "$SECRETS_DIR" ]]; then
    # Удалить все файлы внутри, но не саму директорию
    rm -f "$SECRETS_DIR"/*
    echo "[SUCCESS] Секреты удалены"
else
    echo "[INFO] Директория не существует: $SECRETS_DIR"
fi

# Также очистить временные файлы credentials
if [[ -f "/tmp/temp_data_cred.json" ]]; then
    rm -f "/tmp/temp_data_cred.json"
    echo "[INFO] Временные credentials удалены"
fi

echo "[INFO] Очистка завершена"






