# DEBUG Режим - Краткая Справка

## Быстрый старт

### Включить DEBUG

Jenkins UI → Build with Parameters → ✓ DEBUG

### Выключить DEBUG

Jenkins UI → Build with Parameters → ☐ DEBUG (по умолчанию)

---

## Что показывает DEBUG

| Этап | Информация |
|------|-----------|
| **Валидация** | ⚠️ WARNING о чувствительных данных, статус DEBUG |
| **Vault секреты** | Длины секретов, статус (SET/EMPTY), размер файла |
| **Передача секретов** | Размер файлов, права доступа, владельцы |
| **Ansible** | Детальный вывод (-vvv) |
| **Security check** | Структура файлов /opt/monitoring |
| **Success/Failure** | Workspace info, файлы, причина ошибки |

---

## Примеры вывода

### ✅ Секреты получены успешно

```
DEBUG: Содержимое secretsData:
  - role_id length: 36       ← OK
  - secret_id length: 36     ← OK
  - harvest_rpm_url: SET     ← OK
  - prometheus_rpm_url: SET  ← OK
  - grafana_rpm_url: SET     ← OK
  - grafana_user: SET        ← OK
  - grafana_pass length: 16  ← OK
  - netapp_user: SET         ← OK
  - netapp_pass length: 12   ← OK
DEBUG: Файл secrets.json создан, размер: 452 байт
✓ Секреты получены из Vault
```

### ❌ Секреты НЕ получены

```
DEBUG: Содержимое secretsData:
  - role_id length: 0        ← ПРОБЛЕМА!
  - secret_id length: 0      ← ПРОБЛЕМА!
  - harvest_rpm_url: EMPTY   ← ПРОБЛЕМА!
ОШИБКА: Не получены критичные секреты из Vault: role_id, secret_id
```

**Решение:** Проверить пути к секретам в Vault и права доступа

---

## Типичные проблемы

### Проблема 1: Секреты не получены

**DEBUG покажет:**
```
- role_id length: 0
- secret_id length: 0
```

**Решение:**
1. Проверить `VAULT_AGENT_KV` параметр
2. Проверить namespace в Vault
3. Проверить что секреты существуют

### Проблема 2: SSH ключ не работает

**DEBUG покажет:**
```
[DEBUG] Локальный файл secrets.json:
-rw-r--r-- 1 jenkins jenkins 452 ...
Permission denied (publickey)  ← Ошибка здесь
```

**Решение:**
1. Проверить `SSH_CREDENTIALS_ID`
2. Проверить доступ ключа к серверу
3. Проверить пользователя `monitoring_ci`

### Проблема 3: Неправильные права на файлах

**DEBUG покажет:**
```
DEBUG: Проверка файлов на удаленном сервере...
drwxrwxrwx 2 root root 4.0K config  ← 777 - неправильно!
```

**Решение:**
1. Исправить права через RLM
2. Установить правильного владельца
3. Перезапустить deployment

### Проблема 4: Ansible task падает

**DEBUG (-vvv) покажет:**
```
fatal: [server]: FAILED! => {
    "msg": "Destination directory /opt/monitoring/config does not exist"
}
```

**Решение:**
1. Проверить что директории созданы через RLM
2. Проверить владельцев и права
3. Проверить структуру /opt/monitoring

---

## Безопасность

### ✅ Безопасно выводится

- Длины паролей: `pass length: 16`
- Статусы: `SET` или `EMPTY`
- Размеры файлов: `452 байт`
- Права доступа: `-rw------- 1 user group`

### ❌ НЕ выводится

- Сами пароли
- Токены
- role_id/secret_id значения
- Содержимое secrets.json

### ⚠️ Предупреждение

```
⚠️  ⚠️  ⚠️  WARNING  ⚠️  ⚠️  ⚠️
DEBUG РЕЖИМ ВКЛЮЧЕН!
Логи могут содержать чувствительные данные!
Убедитесь что логи pipeline защищены!
⚠️  ⚠️  ⚠️  WARNING  ⚠️  ⚠️  ⚠️
```

---

## Когда использовать

### ✅ Используйте DEBUG

- Pipeline падает с неясной ошибкой
- Первое развертывание на новом сервере
- Тестирование изменений
- Диагностика проблем
- Dev/Test окружение

### ❌ НЕ используйте DEBUG

- Production развертывание
- Автоматическое развертывание
- Все работает корректно
- Публичные логи
- Нет необходимости в диагностике

---

## Быстрые команды

### Проверка на сервере

```bash
# Подключение
ssh monitoring_ci@server.example.com

# Проверка секретов
sudo ls -la /dev/shm/monitoring/

# Проверка сервисов
sudo systemctl --user -M monitoring_svc@ status prometheus
sudo systemctl --user -M monitoring_svc@ status grafana
sudo systemctl --user -M monitoring_svc@ status harvest

# Проверка Vault Agent
sudo systemctl --user -M monitoring_svc@ status vault-agent-monitoring
sudo journalctl --user -M monitoring_svc@ -u vault-agent-monitoring -f

# Проверка структуры
ls -laR /opt/monitoring/
```

---

## Контакты

- **Документация:** `docs/DEBUG_MODE_GUIDE.md`
- **Отчет:** `DEBUG_IMPLEMENTATION_SUMMARY.md`
- **Поддержка:** DevOps Team / SberInfra

---

**Версия:** 1.0  
**Дата:** 18.11.2024




