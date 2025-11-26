# Детальная диагностика ошибок сервисов

## Текущее состояние

✅ **Символические ссылки созданы** - бинари доступны
❌ **Сервисы падают с ошибками:**
- Grafana: `status=5` - ошибка конфигурации/зависимостей
- Prometheus: `status=2` - ошибка аргументов командной строки  
- Harvest: `status=1/FAILURE` - общая ошибка

## Диагностика

### 1. Проверить логи сервисов

```bash
# Запустить скрипт проверки логов
sudo /opt/monitoring/scripts/check_service_logs.sh
```

**Или вручную:**

```bash
# Проверить логи каждого сервиса
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u grafana -n 20 --no-pager'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u prometheus -n 20 --no-pager'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) journalctl --user -u harvest -n 20 --no-pager'
```

### 2. Проверить конфигурационные файлы

```bash
# Проверить существование и права конфигов
ls -la /opt/monitoring/config/

# Проверить синтаксис YAML файлов
python3 -c "import yaml; yaml.safe_load(open('/opt/monitoring/config/prometheus.yml'))"
python3 -c "import yaml; yaml.safe_load(open('/opt/monitoring/config/harvest.yml'))"
```

### 3. Проверить запуск бинарей вручную

```bash
# Попробовать запустить бинари с минимальными аргументами
sudo -u CI10742292-lnx-mon_sys /opt/monitoring/bin/grafana-server --version
sudo -u CI10742292-lnx-mon_sys /opt/monitoring/bin/prometheus --version
sudo -u CI10742292-lnx-mon_sys /opt/monitoring/bin/harvest version
```

### 4. Проверить директории данных

```bash
# Проверить существование директорий данных
ls -la /opt/monitoring/data/
ls -la /opt/monitoring/logs/

# Проверить права
ls -ld /opt/monitoring/data/grafana
ls -ld /opt/monitoring/data/prometheus
```

## Возможные причины ошибок

### Grafana (status=5)
- ❌ Отсутствует файл конфигурации `/opt/monitoring/config/grafana.ini`
- ❌ Неправильный синтаксис в `grafana.ini`
- ❌ Отсутствуют директории данных
- ❌ Проблемы с правами доступа

### Prometheus (status=2)  
- ❌ Ошибка в `prometheus.yml` (неправильный YAML)
- ❌ Отсутствует `web-config.yml`
- ❌ Неправильные аргументы командной строки
- ❌ Проблемы с директорией данных

### Harvest (status=1/FAILURE)
- ❌ Ошибка в `harvest.yml`
- ❌ Проблемы с подключением к NetApp
- ❌ Отсутствуют зависимости
- ❌ Проблемы с правами

## Быстрое исправление

Если логи покажут конкретные ошибки:

```bash
# Пересоздать конфигурационные файлы через Ansible
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml --tags config

# Или перезапустить полный деплой
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml
```

**Сначала выполните диагностику, чтобы понять конкретные ошибки!**

