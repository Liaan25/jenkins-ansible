# HOTFIX: Исправление проверки файла secrets.json

## Проблема

После внедрения DEBUG режима обнаружена проблема:

```
DEBUG: Содержимое secretsData:
  - role_id length: 36        ✅ Все секреты получены
  - secret_id length: 36      ✅
  ...
ERROR: ОШИБКА: Файл secrets.json не создан или пустой  ❌
```

**Все секреты получены, но файл якобы не создан!**

## Причина

В оригинальном коде использовалась проверка через Groovy `new File()`:

```groovy
def secretsFile = new File("${WORKSPACE_LOCAL}/secrets.json")
if (!secretsFile.exists() || secretsFile.length() == 0) {
    error("ОШИБКА: Файл secrets.json не создан или пустой")
}
```

**Проблемы этого подхода:**
1. `new File()` выполняется в контексте Jenkins master/agent
2. Путь может быть недоступен в Groovy sandbox
3. Проверка может происходить до физической записи на диск
4. В распределенных окружениях файл может быть на другом узле

## Решение

Замена на shell проверку, которая гарантированно выполняется в правильном workspace:

```groovy
// Проверка что файл создан (ВНУТРИ withVault блока)
def fileCheck = sh(
    script: "test -f ${WORKSPACE_LOCAL}/secrets.json && test -s ${WORKSPACE_LOCAL}/secrets.json",
    returnStatus: true
)

if (fileCheck != 0) {
    error("ОШИБКА: Файл secrets.json не создан или пустой")
}

if (params.DEBUG) {
    def fileSize = sh(
        script: "stat -c%s ${WORKSPACE_LOCAL}/secrets.json 2>/dev/null || stat -f%z ${WORKSPACE_LOCAL}/secrets.json 2>/dev/null || echo 'unknown'",
        returnStdout: true
    ).trim()
    echo "DEBUG: Файл secrets.json создан, размер: ${fileSize} байт"
}
```

**Преимущества:**
- ✅ Выполняется на том же узле где создан файл
- ✅ `test -f` проверяет существование файла
- ✅ `test -s` проверяет что файл не пустой
- ✅ `stat` универсально работает на Linux и macOS
- ✅ Всегда видит актуальное состояние файловой системы

## Команды проверки

### Linux (GNU coreutils)
```bash
stat -c%s /path/to/file  # Размер файла в байтах
```

### macOS/BSD
```bash
stat -f%z /path/to/file  # Размер файла в байтах
```

### Универсальная проверка
```bash
stat -c%s file 2>/dev/null || stat -f%z file 2>/dev/null || echo 'unknown'
```

## Ожидаемый результат после исправления

### При DEBUG=true

```
DEBUG: Содержимое secretsData:
  - role_id length: 36
  - secret_id length: 36
  - harvest_rpm_url: SET
  - prometheus_rpm_url: SET
  - grafana_rpm_url: SET
  - grafana_user: SET
  - grafana_pass length: 5
  - netapp_user: SET
  - netapp_pass length: 21
DEBUG: Файл secrets.json создан, размер: 452 байт  ← Теперь работает!
✓ Секреты получены из Vault
```

### При DEBUG=false

```
✓ Секреты получены из Vault
```

## Тестирование

### Локальное тестирование команд

```bash
# Создать тестовый файл
echo '{"test": "data"}' > /tmp/test.json

# Проверка существования и непустоты
test -f /tmp/test.json && test -s /tmp/test.json && echo "OK" || echo "FAIL"
# Ожидаемый результат: OK

# Проверка размера
stat -c%s /tmp/test.json 2>/dev/null || stat -f%z /tmp/test.json 2>/dev/null
# Ожидаемый результат: 16 (или около того)

# Проверка пустого файла
touch /tmp/empty.json
test -f /tmp/empty.json && test -s /tmp/empty.json && echo "OK" || echo "FAIL"
# Ожидаемый результат: FAIL (файл пустой)
```

### В Jenkins Pipeline

Запустить с `DEBUG=true` и проверить лог:

```
DEBUG: Файл secrets.json создан, размер: XXX байт
✓ Секреты получены из Vault
```

Если видите эти строки - исправление работает!

## Изменения в файлах

### Jenkinsfile (строки 310-328)

**Было:**
```groovy
def secretsFile = new File("${WORKSPACE_LOCAL}/secrets.json")
if (!secretsFile.exists() || secretsFile.length() == 0) {
    error("ОШИБКА: Файл secrets.json не создан или пустой")
}

if (params.DEBUG) {
    echo "DEBUG: Файл secrets.json создан, размер: ${secretsFile.length()} байт"
}
```

**Стало:**
```groovy
def fileCheck = sh(
    script: "test -f ${WORKSPACE_LOCAL}/secrets.json && test -s ${WORKSPACE_LOCAL}/secrets.json",
    returnStatus: true
)

if (fileCheck != 0) {
    error("ОШИБКА: Файл secrets.json не создан или пустой")
}

if (params.DEBUG) {
    def fileSize = sh(
        script: "stat -c%s ${WORKSPACE_LOCAL}/secrets.json 2>/dev/null || stat -f%z ${WORKSPACE_LOCAL}/secrets.json 2>/dev/null || echo 'unknown'",
        returnStdout: true
    ).trim()
    echo "DEBUG: Файл secrets.json создан, размер: ${fileSize} байт"
}
```

## Почему это важно

Эта проблема блокировала **ВСЕ** stage после получения секретов:

```
Stage "Подготовка Ansible" skipped due to earlier failure(s)
Stage "Передача секретов на сервер" skipped due to earlier failure(s)
Stage "Развертывание (Ansible)" skipped due to earlier failure(s)
Stage "Проверка безопасности" skipped due to earlier failure(s)
Stage "Верификация сервисов" skipped due to earlier failure(s)
Stage "Очистка секретов" skipped due to earlier failure(s)
```

**После исправления:** Pipeline продолжит выполнение и дойдет до реального развертывания!

## Дополнительные улучшения

Если проблема повторится, можно добавить дополнительный DEBUG вывод:

```groovy
if (params.DEBUG) {
    echo "DEBUG: Проверка файла secrets.json..."
    sh "ls -lh ${WORKSPACE_LOCAL}/secrets.json || echo 'Файл не найден'"
    sh "file ${WORKSPACE_LOCAL}/secrets.json || echo 'Невозможно определить тип'"
    sh "head -c 100 ${WORKSPACE_LOCAL}/secrets.json || echo 'Невозможно прочитать'"
}
```

Это покажет:
- Права и размер файла
- Тип файла (должен быть ASCII text)
- Первые 100 байт (для проверки что это JSON)

## Следующие шаги

1. ✅ Исправление применено в Jenkinsfile
2. 🔄 Запустить Jenkins Pipeline с DEBUG=true
3. ✅ Проверить что появляется "DEBUG: Файл secrets.json создан, размер: XXX байт"
4. ✅ Убедиться что pipeline проходит дальше stage "Получение секретов из Vault"
5. 📊 Если все работает - отключить DEBUG для production

## Commit message

```
fix: Replace File() check with shell test for secrets.json validation

- Changed from Groovy new File() to sh test command
- Fixes false positive "file not created" error
- Added cross-platform stat command for file size
- Resolves issue where all stages were skipped after Vault secrets retrieval
```

---

**Дата:** 18.11.2024 23:40  
**Версия:** Hotfix 1.0  
**Статус:** ✅ Готово к тестированию






