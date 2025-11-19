# Руководство по DEBUG режиму Jenkins Pipeline

## Обзор

В Jenkinsfile добавлен параметр `DEBUG` для детальной диагностики проблем при развертывании системы мониторинга. DEBUG режим предоставляет дополнительную информацию о каждом этапе выполнения, помогая быстро локализовать и устранить проблемы.

## ⚠️ ВАЖНОЕ ПРЕДУПРЕЖДЕНИЕ О БЕЗОПАСНОСТИ

**DEBUG режим может выводить чувствительную информацию в логи Jenkins!**

- ✅ Выводятся **длины** паролей и секретов (безопасно)
- ✅ Выводится **статус** наличия секретов (SET/EMPTY)
- ❌ **НЕ выводятся** сами значения секретов в plain text
- ⚠️  Логи с DEBUG=true должны быть защищены
- ⚠️  Используйте DEBUG только для troubleshooting
- ⚠️  Отключайте DEBUG в production

## Включение DEBUG режима

### В Jenkins UI

При запуске pipeline установите параметр:
```
DEBUG: ✓ (checked)
```

### Через Jenkins API

```bash
curl -X POST "https://jenkins.example.com/job/deploy_monitoring/buildWithParameters" \
  --user "user:token" \
  --data "DEBUG=true" \
  --data "SERVER_ADDRESS=server.example.com" \
  ...
```

## Что показывает DEBUG режим

### 1. Валидация параметров

При DEBUG=true добавляется:

```
⚠️  ⚠️  ⚠️  WARNING  ⚠️  ⚠️  ⚠️
DEBUG РЕЖИМ ВКЛЮЧЕН!
Логи могут содержать чувствительные данные!
Убедитесь что логи pipeline защищены!
⚠️  ⚠️  ⚠️  WARNING  ⚠️  ⚠️  ⚠️

================================================
ВАЛИДАЦИЯ ПАРАМЕТРОВ
================================================
Целевой сервер: server.example.com
Namespace: CI04523276_CI10742292
NetApp кластер: siena.delta.sbrf.ru
Метод развертывания: ansible
DEBUG режим: true
================================================
```

### 2. Получение секретов из Vault

Детальная информация о секретах **БЕЗ plain text**:

```
DEBUG: Содержимое secretsData:
  - role_id length: 36
  - secret_id length: 36
  - harvest_rpm_url: SET
  - prometheus_rpm_url: SET
  - grafana_rpm_url: SET
  - grafana_user: SET
  - grafana_pass length: 16
  - netapp_user: SET
  - netapp_pass length: 12
DEBUG: Файл secrets.json создан, размер: 452 байт
✓ Секреты получены из Vault
```

**Если секреты не получены:**

```
DEBUG: Содержимое secretsData:
  - role_id length: 0   ← ПРОБЛЕМА!
  - secret_id length: 0  ← ПРОБЛЕМА!
  - harvest_rpm_url: EMPTY
  ...
ОШИБКА: Не получены критичные секреты из Vault: role_id, secret_id
```

### 3. Передача секретов на сервер

```
DEBUG: Проверка локального файла secrets.json...
-rw-r--r-- 1 jenkins jenkins 452 Nov 18 23:07 /workspace/secrets.json
1 /workspace/secrets.json

[INFO] Создание директории для секретов в /dev/shm...
[DEBUG] Локальный файл secrets.json:
-rw-r--r-- 1 jenkins jenkins 452 Nov 18 23:07 /workspace/secrets.json

[INFO] Передача секретов через SCP...
[DEBUG] Удаленный файл secrets.json после копирования:
-rw------- 1 monitoring_svc monitoring 452 Nov 18 23:07 /dev/shm/monitoring/secrets.json

[DEBUG] Права на secrets.json:
-rw------- 1 monitoring_svc monitoring 452 Nov 18 23:07 /dev/shm/monitoring/secrets.json

[DEBUG] Созданные файлы секретов:
total 12K
-rw------- 1 monitoring_svc monitoring 452 Nov 18 23:07 secrets.json
-rw------- 1 monitoring_svc monitoring  36 Nov 18 23:07 role_id.txt
-rw------- 1 monitoring_svc monitoring  36 Nov 18 23:07 secret_id.txt

[SUCCESS] Секреты успешно переданы и размещены в /dev/shm/monitoring
```

**При включении DEBUG в bash скрипте (set -x):**

Показываются все выполняемые команды с полным trace.

### 4. Развертывание через Ansible

DEBUG режим увеличивает verbosity Ansible:

```
ansible-playbook \
    -i inventories/dynamic_inventory \
    playbooks/deploy_monitoring.yml \
    --extra-vars "rlm_token=***" \
    --private-key=/tmp/ssh_key \
    -vvv                          ← Максимальная детализация
```

Вывод включает:
- Подключение к хостам
- Выполнение каждой task
- Изменения в файлах
- Вызовы handlers
- Значения переменных (не чувствительных)

### 5. Проверка безопасности

```
DEBUG: Проверка файлов на удаленном сервере перед security check...
total 32K
drwxr-xr-x 8 monitoring_ci  monitoring 4.0K Nov 18 23:10 .
drwxr-xr-x 5 root          root       4.0K Nov 18 20:00 ..
drwxr-x--- 2 monitoring_ci  monitoring 4.0K Nov 18 23:08 bin
drwxr-x--- 2 monitoring_svc monitoring 4.0K Nov 18 23:09 config
drwxr-x--- 3 monitoring_svc monitoring 4.0K Nov 18 23:10 data
drwxr-x--- 3 monitoring_svc monitoring 4.0K Nov 18 23:10 logs
drwxr-x--- 2 monitoring_ci  monitoring 4.0K Nov 18 23:08 scripts
drwx------ 2 monitoring_svc monitoring 4.0K Nov 18 23:07 .ssh
...
```

### 6. Success/Failure блоки

**При успешном завершении:**

```
DEBUG INFO:
  - Workspace: /var/lib/jenkins/workspace/deploy_monitoring
  - Build Number: 42
  - Build URL: https://jenkins.example.com/job/deploy_monitoring/42/
  - Deployment Method: ansible
```

**При ошибке:**

```
DEBUG: Failure Details
  - Stage: Получение секретов из Vault
  - Workspace files:
total 48K
-rw-r--r-- 1 jenkins jenkins  1.2K Nov 18 23:07 Jenkinsfile
-rw-r--r-- 1 jenkins jenkins   452 Nov 18 23:07 secrets.json
drwxr-xr-x 3 jenkins jenkins  4.0K Nov 18 23:07 ansible_project
...

[
  "vault-agent",
  "rpm_url",
  "grafana_web",
  "netapp_api"
]
```

## Примеры использования

### Сценарий 1: Не получены секреты из Vault

**Запуск с DEBUG=true**

Лог покажет:
```
DEBUG: Содержимое secretsData:
  - role_id length: 0   ← Секрет пустой!
  - secret_id length: 0  ← Секрет пустой!
ОШИБКА: Не получены критичные секреты из Vault: role_id, secret_id
```

**Решение:**
1. Проверить правильность пути `VAULT_AGENT_KV` в параметрах
2. Проверить доступ Jenkins к Vault с указанным namespace
3. Проверить что секреты существуют в Vault по указанному пути

### Сценарий 2: Ошибка передачи секретов на сервер

**DEBUG покажет на каком этапе произошла ошибка:**

```
[INFO] Создание директории для секретов в /dev/shm...
+ ssh -i /tmp/ssh_key monitoring_ci@server.example.com ...
Permission denied (publickey)   ← SSH ключ не подходит!
```

**Решение:**
1. Проверить `SSH_CREDENTIALS_ID` в параметрах
2. Проверить что ключ имеет доступ к целевому серверу
3. Проверить что пользователь `monitoring_ci` существует

### Сценарий 3: Ansible task завершается с ошибкой

**DEBUG (-vvv) покажет детали:**

```
TASK [vault_agent : Copy Vault Agent configuration] ***************************
fatal: [server.example.com]: FAILED! => {
    "changed": false,
    "checksum": "da39a3ee5e6b4b0d3255bfef95601890afd80709",
    "msg": "Destination directory /opt/monitoring/config does not exist"
}
```

**Решение:**
1. Убедиться что директория `/opt/monitoring/config` создана через RLM
2. Проверить владельца директории
3. Проверить права доступа

### Сценарий 4: Security check не проходит

**DEBUG покажет структуру файлов перед проверкой:**

```
DEBUG: Проверка файлов на удаленном сервере перед security check...
drwxrwxrwx 2 root root 4.0K Nov 18 23:09 config  ← Неправильные права!
```

**Решение:**
1. Исправить права через RLM или sudoers
2. Установить правильного владельца (monitoring_svc)
3. Перезапустить deployment

## Когда использовать DEBUG

### ✅ Используйте DEBUG когда:

1. Pipeline падает с неясной ошибкой
2. Секреты не получаются из Vault
3. Ansible tasks завершаются с ошибками
4. Нужно проверить что файлы создаются с правильными правами
5. Развертывание на тестовом окружении
6. Первое развертывание на новом сервере
7. Тестирование изменений в pipeline

### ❌ НЕ используйте DEBUG когда:

1. Production развертывание
2. Автоматическое развертывание по расписанию
3. Все работает корректно
4. Логи Jenkins доступны неограниченному кругу лиц
5. Нет необходимости в детальной диагностике

## Управление DEBUG режимом

### По умолчанию

```groovy
booleanParam(
    name: 'DEBUG',
    defaultValue: false,   ← Выключен по умолчанию
    description: '...'
)
```

### Временное включение

Для одной конкретной сборки установите `DEBUG=true` в UI.

### Постоянное включение (не рекомендуется)

Измените `defaultValue: true` в Jenkinsfile, но **это небезопасно для production!**

## Безопасность DEBUG режима

### Что выводится безопасно

```groovy
echo "  - role_id length: ${secretsData['vault-agent'].role_id?.length() ?: 0}"
echo "  - harvest_rpm_url: ${secretsData['rpm_url'].harvest ? 'SET' : 'EMPTY'}"
```

### Что НЕ выводится

```groovy
// ❌ НИКОГДА не выводим plain text:
// echo "  - role_id: ${secretsData['vault-agent'].role_id}"  // НЕПРАВИЛЬНО!
// echo "  - password: ${password}"                           // НЕПРАВИЛЬНО!
```

### Маскировка секретов

Jenkins автоматически маскирует значения из `withCredentials`, но будьте осторожны с:
- Выводом содержимого файлов секретов
- Dump переменных окружения
- Полным trace bash скриптов (set -x может показать аргументы команд)

## Отключение DEBUG после troubleshooting

После устранения проблемы **обязательно** отключите DEBUG:

1. Следующая сборка — убрать галочку `DEBUG`
2. Или перезапустить pipeline без параметра `DEBUG`
3. Проверить что логи не содержат чувствительной информации

## Архивирование логов

Логи с DEBUG=true сохраняются в Jenkins:
- Build → Console Output
- Build → Archived artifacts (если есть .log файлы)

**Ограничьте доступ** к логам если они содержат DEBUG вывод!

## Дополнительные инструменты диагностики

### SSH доступ к серверу

```bash
ssh monitoring_ci@server.example.com
sudo -u monitoring_svc bash
ls -la /opt/monitoring/
cat /opt/monitoring/logs/prometheus/prometheus.log
```

### Проверка секретов

```bash
ssh monitoring_ci@server.example.com
sudo ls -la /dev/shm/monitoring/
# Должны быть: secrets.json, role_id.txt, secret_id.txt
```

### Проверка сервисов

```bash
ssh monitoring_ci@server.example.com
sudo systemctl --user -M monitoring_svc@ status prometheus
sudo systemctl --user -M monitoring_svc@ status grafana
sudo systemctl --user -M monitoring_svc@ status harvest
```

### Проверка Vault Agent

```bash
ssh monitoring_ci@server.example.com
sudo systemctl --user -M monitoring_svc@ status vault-agent-monitoring
sudo journalctl --user -M monitoring_svc@ -u vault-agent-monitoring -f
```

## FAQ

### Q: DEBUG режим замедляет выполнение?

A: Минимально. Основное время — это `-vvv` в Ansible, но даже это несущественно для диагностики.

### Q: Можно ли включить DEBUG только для определенного stage?

A: Нет, параметр `DEBUG` глобальный. Но можно временно закомментировать `if (params.DEBUG)` блоки в Jenkinsfile.

### Q: Выводятся ли пароли в plain text?

A: **НЕТ**. Выводятся только длины и статусы (SET/EMPTY).

### Q: Как защитить логи с DEBUG?

A: Настройте Role-Based Access Control в Jenkins, ограничив доступ к job и его логам.

### Q: DEBUG работает и для script метода развертывания?

A: Да, все изменения универсальны. В script методе также есть bash `set -x` при DEBUG=true.

## Контакты и поддержка

При проблемах с DEBUG режимом или вопросах по диагностике:

1. Проверьте этот документ
2. Изучите Console Output в Jenkins
3. Обратитесь к команде SberInfra
4. Создайте тикет в JIRA с прикрепленным логом (убедитесь что нет чувствительных данных!)

---

**Версия документа:** 1.0  
**Дата создания:** 18 ноября 2024  
**Автор:** DevOps Team


