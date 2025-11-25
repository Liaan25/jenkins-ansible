---
# Руководство по исправлению: Отсутствие исполняемых файлов

## Проблема

Диагностика показала, что исполняемые файлы не существуют в `/opt/monitoring/bin/`:
- ❌ `/opt/monitoring/bin/grafana-server`
- ❌ `/opt/monitoring/bin/prometheus`  
- ❌ `/opt/monitoring/bin/harvest`

Это вызывает ошибку `status=203/EXEC` в systemd.

## Решение

### Единый скрипт для исправления

```bash
# Запустить единый скрипт
sudo /opt/monitoring/scripts/fix_missing_binaries.sh
```

**Скрипт выполнит:**
1. ✅ Проверку текущего состояния
2. ✅ Поиск исполняемых файлов в системе
3. ✅ Проверку установленных RPM пакетов
4. ✅ Создание символических ссылок
5. ✅ Проверку результата
6. ✅ Тестирование запуска
7. ✅ Выдачу рекомендаций

### Проверка результата

```bash
# Проверить что ссылки созданы
ls -la /opt/monitoring/bin/

# Проверить что сервисы могут запускаться
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user start grafana'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status grafana'
```

## Альтернативные решения

### Если бинари не найдены:

1. **Проверить установку RPM пакетов:**
   ```bash
   rpm -qa | grep -E "(grafana|prometheus|harvest)"
   ```

2. **Переустановить через RLM:**
   - Запустить RLM сценарий установки RPM пакетов
   - Убедиться что пакеты устанавливаются корректно

3. **Проверить пути установки в RPM:**
   ```bash
   rpm -ql grafana | grep bin
   rpm -ql prometheus | grep bin  
   rpm -ql harvest | grep bin
   ```

## Ожидаемый результат

После создания ссылок:
- ✅ Сервисы должны запускаться без ошибки `status=203/EXEC`
- ✅ В `/opt/monitoring/bin/` появятся символические ссылки
- ✅ Статус сервисов изменится на `active (running)`
---
# Руководство по исправлению: Отсутствие исполняемых файлов

## Проблема

Диагностика показала, что исполняемые файлы не существуют в `/opt/monitoring/bin/`:
- ❌ `/opt/monitoring/bin/grafana-server`
- ❌ `/opt/monitoring/bin/prometheus`  
- ❌ `/opt/monitoring/bin/harvest`

Это вызывает ошибку `status=203/EXEC` в systemd.

## Решение

### Единый скрипт для исправления

```bash
# Запустить единый скрипт
sudo /opt/monitoring/scripts/fix_missing_binaries.sh
```

**Скрипт выполнит:**
1. ✅ Проверку текущего состояния
2. ✅ Поиск исполняемых файлов в системе
3. ✅ Проверку установленных RPM пакетов
4. ✅ Создание символических ссылок
5. ✅ Проверку результата
6. ✅ Тестирование запуска
7. ✅ Выдачу рекомендаций

### Проверка результата

```bash
# Проверить что ссылки созданы
ls -la /opt/monitoring/bin/

# Проверить что сервисы могут запускаться
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user start grafana'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status grafana'
```

## Альтернативные решения

### Если бинари не найдены:

1. **Проверить установку RPM пакетов:**
   ```bash
   rpm -qa | grep -E "(grafana|prometheus|harvest)"
   ```

2. **Переустановить через RLM:**
   - Запустить RLM сценарий установки RPM пакетов
   - Убедиться что пакеты устанавливаются корректно

3. **Проверить пути установки в RPM:**
   ```bash
   rpm -ql grafana | grep bin
   rpm -ql prometheus | grep bin  
   rpm -ql harvest | grep bin
   ```

## Ожидаемый результат

После создания ссылок:
- ✅ Сервисы должны запускаться без ошибки `status=203/EXEC`
- ✅ В `/opt/monitoring/bin/` появятся символические ссылки
- ✅ Статус сервисов изменится на `active (running)`
