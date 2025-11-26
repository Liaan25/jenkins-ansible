# Краткое руководство по развертыванию

## Быстрый старт

### 1. Jenkins Pipeline

1. **Запустите Jenkins pipeline** с параметрами:
   - `SERVER_ADDRESS`: IP/FQDN целевого сервера
   - `NAMESPACE_CI`: Namespace в Vault
   - `NETAPP_API_ADDR`: FQDN NetApp кластера
   - `USE_RLM_STANDARD_SETUP`: Выбор режима

2. **Выберите режим установки:**
   - ✅ `USE_RLM_STANDARD_SETUP = true` - Стандартная RLM установка
   - ✅ `USE_RLM_STANDARD_SETUP = false` - Безопасная установка

3. **Pipeline автоматически выполнит:**
   - Настройку групп пользователей через RLM
   - Получение секретов из Vault
   - Установку RPM пакетов через RLM
   - Настройку сервисов в выбранном режиме
   - Проверку безопасности и верификацию

### 2. Ручное развертывание через Ansible

```bash
# Стандартный RLM режим
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml \
  --extra-vars "use_rlm_standard_setup=true"

# Безопасный режим  
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml \
  --extra-vars "use_rlm_standard_setup=false"
```

## Проверка установки

### Стандартный RLM режим

```bash
# Проверка системных сервисов
systemctl status prometheus grafana-server harvest

# Проверка конфигурации
sudo bash /opt/monitoring/scripts/verify_rlm_standard_setup.sh

# Доступ к сервисам
curl -k https://localhost:9090/-/healthy  # Prometheus
curl -k https://localhost:3000/api/health  # Grafana
```

### Безопасный режим

```bash
# Проверка пользовательских сервисов
sudo -u monitoring_svc -g monitoring_svc systemctl --user status prometheus grafana harvest

# Проверка безопасности
sudo bash /opt/monitoring/scripts/verify_security.sh

# Доступ к сервисам
curl -k https://localhost:9090/-/healthy  # Prometheus
curl -k https://localhost:3000/api/health  # Grafana
```

## Режимы установки

### 🔧 Стандартный RLM режим (`USE_RLM_STANDARD_SETUP = true`)

**Рекомендуется для:**
- Простых развертываний
- Совместимости с существующими системами
- Использования стандартных путей

**Особенности:**
- Системные пользователи: `prometheus`, `grafana`, `harvest`
- Стандартные пути: `/etc/prometheus/`, `/etc/grafana/`, `/opt/harvest/`
- Системные сервисы: `prometheus`, `grafana-server`, `harvest`

### 🔒 Безопасный режим (`USE_RLM_STANDARD_SETUP = false`)

**Рекомендуется для:**
- Высоких требований безопасности
- Изоляции приложений
- Соответствия корпоративным политикам

**Особенности:**
- Непривилегированные пользователи: `monitoring_svc`, `monitoring_ci`, `monitoring_admin`
- Изолированные пути: `/opt/monitoring/config/`, `/opt/monitoring/data/`
- Пользовательские сервисы: `prometheus`, `grafana`, `harvest`

## Устранение неполадок

### Проблемы с сервисами

**Стандартный режим:**
```bash
# Проверка логов
journalctl -u prometheus -f
journalctl -u grafana-server -f
journalctl -u harvest -f

# Перезапуск сервисов
systemctl restart prometheus grafana-server harvest
```

**Безопасный режим:**
```bash
# Проверка логов
sudo -u monitoring_svc journalctl --user -u prometheus -f
sudo -u monitoring_svc journalctl --user -u grafana -f
sudo -u monitoring_svc journalctl --user -u harvest -f

# Перезапуск сервисов
sudo -u monitoring_svc systemctl --user restart prometheus grafana harvest
```

### Проблемы с сертификатами

```bash
# Проверка сертификатов
openssl x509 -in /etc/prometheus/cert/server.crt -text -noout
openssl x509 -in /etc/grafana/cert/crt.crt -text -noout

# Проверка Vault Agent
systemctl status vault-agent
journalctl -u vault-agent -f
```






