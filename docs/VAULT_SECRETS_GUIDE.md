# Руководство по работе с Vault Agent и секретами

## Краткое описание

Vault Agent - это инструмент для автоматического получения секретов из HashiCorp Vault и размещения их на целевом сервере в безопасном виде.

## Архитектура

```
Vault (SecMan) → Vault Agent → /dev/shm/monitoring_secrets/ → Services
```

## Основные компоненты

### 1. Конфигурация Vault Agent

Файл: `/opt/vault/conf/agent.hcl`

```hcl
pid_file = "/opt/vault/log/vault-agent.pidfile"

vault {
  address = "https://vault.sigma.sbrf.ru"
  tls_skip_verify = "false"
  ca_path = "/opt/vault/conf/ca-trust"
}

auto_auth {
  method "approle" {
    namespace = "KPRJ_000000"
    mount_path = "auth/approle"
    
    config = {
      role_id_file_path = "/opt/vault/conf/role_id.txt"
      secret_id_file_path = "/opt/vault/conf/secret_id.txt"
      remove_secret_id_file_after_reading = false
    }
  }
}

# Шаблон для сертификатов
template {
  destination = "/dev/shm/monitoring_secrets/server_bundle.pem"
  contents    = <<EOT
{{- with secret "pki/issue/monitoring" "common_name=server.example.com" "email=admin@example.com" -}}
{{ .Data.private_key }}
{{ .Data.certificate }}
{{ .Data.issuing_ca }}
{{- end -}}
  EOT
  perms = "0600"
}

# Разделение на отдельные файлы через скрипт
template {
  destination = "/dev/shm/monitoring_secrets/split_certs.sh"
  command     = "/bin/bash /dev/shm/monitoring_secrets/split_certs.sh"
  contents    = <<EOT
#!/bin/bash
cd /dev/shm/monitoring_secrets
openssl pkey -in server_bundle.pem -out server.key
openssl crl2pkcs7 -nocrl -certfile server_bundle.pem | openssl pkcs7 -print_certs -out server.crt
chmod 600 server.key
chmod 640 server.crt
chown monitoring_svc:monitoring server.key server.crt
  EOT
  perms = "0700"
}
```

### 2. AppRole credentials

**role_id.txt** - идентификатор роли (аналог username)
**secret_id.txt** - секрет роли (аналог password)

Получение через Jenkins из Vault перед деплоем.

### 3. Размещение секретов в /dev/shm

**Почему /dev/shm?**
- tmpfs - файловая система в RAM
- Не записывается на диск
- Автоматически очищается при перезагрузке
- Быстрый доступ

**Структура**:
```
/dev/shm/monitoring_secrets/
├── server.crt          (640, monitoring_svc:monitoring)
├── server.key          (600, monitoring_svc:monitoring)
├── client.crt          (640, monitoring_svc:monitoring)
├── client.key          (600, monitoring_svc:monitoring)
├── grafana-client.crt  (640, monitoring_svc:monitoring)
├── grafana-client.key  (600, monitoring_svc:monitoring)
└── ca_chain.crt        (644, monitoring_svc:monitoring)
```

## Жизненный цикл секретов

1. **Запуск Vault Agent** (при старте сервера)
2. **Аутентификация** в Vault через AppRole
3. **Получение токена** с ограниченными правами
4. **Запрос секретов** через шаблоны
5. **Размещение** в /dev/shm с нужными правами
6. **Автоматическое обновление** при приближении срока истечения
7. **Уведомление сервисов** о новых секретах (через HUP signal)

## Ротация секретов

### Автоматическая

Vault Agent автоматически обновляет секреты:
- За 7 дней до истечения сертификата
- При изменении секрета в Vault
- При перезапуске Vault Agent

### Ручная

```bash
# Перезапустить Vault Agent для получения новых секретов
sudo -u monitoring_svc systemctl --user restart vault-agent-monitoring

# Проверить обновление
ls -lt /dev/shm/monitoring_secrets/

# Перезапустить сервисы
sudo -u monitoring_svc systemctl --user restart prometheus grafana harvest
```

## Проверка работы Vault Agent

```bash
# Статус
systemctl --user status vault-agent-monitoring

# Логи
journalctl --user -u vault-agent-monitoring -f

# Проверка секретов
ls -la /dev/shm/monitoring_secrets/

# Проверка срока действия сертификата
openssl x509 -in /dev/shm/monitoring_secrets/server.crt -noout -dates
```

## Безопасность

### Защита AppRole credentials

1. **role_id.txt** и **secret_id.txt** с правами 640
2. Владелец: monitoring_svc
3. Размещение в /opt/vault/conf (не в /dev/shm)
4. Регулярная ротация secret_id (90 дней)

### Защита секретов в /dev/shm

1. Права 700 на директорию
2. Владелец monitoring_svc (только он может читать)
3. Приватные ключи с правами 600
4. Публичные сертификаты с правами 640

### Аудит

Все обращения к Vault логируются:
- Кто запросил
- Какой секрет
- Когда
- Успешно или нет

## Устранение неполадок

### Vault Agent не запускается

1. Проверить конфигурацию: `vault-agent -config=/opt/vault/conf/agent.hcl -log-level=debug`
2. Проверить доступность Vault: `curl -k https://vault.sigma.sbrf.ru/v1/sys/health`
3. Проверить AppRole credentials: `cat /opt/vault/conf/role_id.txt`

### Секреты не появляются в /dev/shm

1. Проверить логи Vault Agent
2. Проверить права на /dev/shm/monitoring_secrets
3. Проверить политики доступа в Vault
4. Проверить срок действия secret_id

### Сертификаты истекли

1. Vault Agent должен обновить автоматически
2. Если не обновил - перезапустить: `systemctl --user restart vault-agent-monitoring`
3. Проверить что обновились: `openssl x509 -in /dev/shm/monitoring_secrets/server.crt -noout -dates`

## Полный список путей в Vault

- `pki/issue/monitoring` - генерация сертификатов
- `secret/data/monitoring/rpm-urls` - URL RPM пакетов
- `secret/data/monitoring/netapp-api` - credentials для NetApp API
- `secret/data/monitoring/grafana-web` - credentials для Grafana Web UI
- `secret/data/monitoring/vault-agent` - AppRole credentials






