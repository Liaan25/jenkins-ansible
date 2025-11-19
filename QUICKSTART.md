# Быстрый старт - Безопасное развертывание системы мониторинга

## Предварительная подготовка (1-2 недели)

### 1. Создание учетных записей через IDM (3-5 дней)
```
См. docs/IDM_ACCOUNTS_GUIDE.md

Создать 4 УЗ:
- monitoring_svc (NoLogin) - сервисная
- monitoring_admin - администрирование
- monitoring_ci - CI/CD деплой
- monitoring_ro - только чтение
```

### 2. Запрос прав sudo через IDM (3-5 дней)
```
См. docs/SUDOERS_GUIDE.md

Приложить файл: sudoers/monitoring_system
Для УЗ: monitoring_ci, monitoring_admin, monitoring_ro
```

### 3. Создание файловой системы через RLM (1 день)
```
Общий размер: 7GB

Создать через RLM сценарий "Добавление/расширение ФС":
- /opt/monitoring - 1GB (владелец: monitoring_ci)
- /opt/monitoring/data - 4GB (владелец: monitoring_svc)
- /opt/monitoring/logs - 2GB (владелец: monitoring_svc, группа: monitoring_admin)
```

### 4. Настройка Vault (1 день)
```
В Vault создать пути KV:
- secret/data/monitoring/vault-agent (role_id, secret_id)
- secret/data/monitoring/rpm-urls (harvest, prometheus, grafana)
- secret/data/monitoring/netapp-api (addr, user, pass)
- secret/data/monitoring/grafana-web (user, pass)
- pki/issue/monitoring (для генерации сертификатов)

Политика доступа: monitoring-read
```

## Развертывание (30-60 минут)

### Вариант 1: Через Jenkins (рекомендуется)

1. **Настроить параметры Jenkins**:
```
SERVER_ADDRESS=<IP или FQDN сервера>
SSH_CREDENTIALS_ID=<ID SSH ключа для monitoring_ci>
SEC_MAN_ADDR=vault.sigma.sbrf.ru
NAMESPACE_CI=<ваш namespace>
NETAPP_API_ADDR=<FQDN NetApp кластера>
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
RLM_API_URL=https://rlm.sigma.sbrf.ru
... (остальные параметры из Vault)
```

2. **Запустить Pipeline**:
```
- Build with Parameters
- Заполнить все параметры
- Нажать Build
```

3. **Дождаться завершения** (20-30 минут)

### Вариант 2: Через Ansible

1. **Настроить inventory**:
```bash
cd ansible/inventories
cp production.example production
# Указать IP/FQDN сервера
```

2. **Настроить переменные**:
```bash
cd ansible/group_vars
cp monitoring.yml.example monitoring.yml
# Указать все параметры
```

3. **Запустить развертывание**:
```bash
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml
```

### Вариант 3: Вручную (тестирование)

См. полное руководство: `docs/DEPLOYMENT_GUIDE.md`, раздел "Ручная установка"

## Проверка после развертывания (5 минут)

### 1. Проверка сервисов
```bash
ssh monitoring_admin@<сервер>

# Статус сервисов
sudo systemctl --user status prometheus
sudo systemctl --user status grafana
sudo systemctl --user status harvest

# Все должны быть: active (running)
```

### 2. Проверка портов
```bash
ss -tlnp | grep -E ":(9090|3000|12990|12991)"

# Должны быть открыты все 4 порта
```

### 3. Проверка веб-интерфейсов
```bash
# Prometheus
curl -k https://localhost:9090/-/healthy
# Ожидается: Prometheus is Healthy.

# Grafana
curl -k https://localhost:3000/api/health
# Ожидается: {"database":"ok"}
```

### 4. Проверка безопасности
```bash
sudo bash /opt/monitoring/scripts/verify_security.sh

# Должно показать:
# ✓ Система соответствует требованиям безопасности
```

### 5. Проверка секретов
```bash
sudo -u monitoring_svc bash /opt/monitoring/scripts/manage_secrets.sh check

# Проверит срок действия сертификатов и соответствие ключей
```

## Доступ к системе

### Grafana Web UI
```
URL: https://<сервер>:3000
Логин: <из GRAFANA_WEB_KV в Vault>
Пароль: <из GRAFANA_WEB_KV в Vault>
```

### Prometheus Web UI (только localhost)
```
URL: https://<сервер>:9090
Доступ только с localhost и IP сервера
```

### Harvest Metrics
```
NetApp: https://<сервер>:12990/metrics
Unix: http://localhost:12991/metrics
```

## Повседневное обслуживание

### Просмотр логов
```bash
ssh monitoring_admin@<сервер>

# Логи Prometheus
sudo journalctl --user -u prometheus -f

# Логи Grafana
sudo journalctl --user -u grafana -f

# Логи Harvest
sudo journalctl --user -u harvest -f
```

### Перезапуск сервисов
```bash
ssh monitoring_admin@<сервер>

# Перезапуск Prometheus
sudo systemctl --user restart prometheus

# Перезапуск всех
sudo systemctl --user restart prometheus grafana harvest
```

### Обновление конфигурации
```bash
ssh monitoring_ci@<сервер>

# Редактировать конфиг
vim /opt/monitoring/config/prometheus.yml

# Проверить синтаксис (если есть promtool)
promtool check config /opt/monitoring/config/prometheus.yml

# Перезапустить
sudo systemctl --user restart prometheus
```

## Устранение неполадок

### Сервис не запускается
```bash
# 1. Проверить логи
sudo journalctl --user -u <service> -n 50

# 2. Проверить секреты
sudo -u monitoring_svc ls -la /dev/shm/monitoring_secrets/

# 3. Проверить конфигурацию
cat /opt/monitoring/config/<service>.yml

# 4. Запустить вручную для диагностики
sudo -u monitoring_svc /opt/monitoring/bin/<service> --help
```

### Vault Agent не работает
```bash
# Проверить статус
systemctl --user status vault-agent-monitoring

# Проверить логи
journalctl --user -u vault-agent-monitoring -n 100

# Перезапустить
systemctl --user restart vault-agent-monitoring
```

### Сертификаты истекли
```bash
# Проверить срок
sudo -u monitoring_svc bash /opt/monitoring/scripts/manage_secrets.sh check

# Обновить
sudo -u monitoring_svc systemctl --user restart vault-agent-monitoring

# Перезапустить сервисы
sudo systemctl --user restart prometheus grafana harvest
```

## Полезные команды

```bash
# Статус всех сервисов
systemctl --user list-units | grep monitoring

# Использование ресурсов
systemctl --user status

# Размер данных
du -sh /opt/monitoring/data/*

# Размер логов
du -sh /opt/monitoring/logs/*

# Проверка конфигурации Prometheus
promtool check config /opt/monitoring/config/prometheus.yml

# Экспорт метрик
curl -k https://localhost:9090/api/v1/query?query=up > /tmp/metrics.json
```

## Важные ссылки

- **Полная документация**: `docs/DEPLOYMENT_GUIDE.md`
- **Модель безопасности**: `docs/SECURITY_MODEL.md`
- **Создание УЗ**: `docs/IDM_ACCOUNTS_GUIDE.md`
- **Настройка sudo**: `docs/SUDOERS_GUIDE.md`
- **Работа с Vault**: `docs/VAULT_SECRETS_GUIDE.md`

## Контакты поддержки

- **Техподдержка**: ServiceNow, категория "Мониторинг"
- **Vault Admin**: vault-admin@example.com
- **Security Team**: security@example.com

---

**Успешного развертывания!** 🚀


