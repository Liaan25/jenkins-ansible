# 🔐 Процесс генерации Sudoers для IDM

> **Двухэтапный процесс развертывания с предварительной генерацией sudoers файлов**

---

## 📋 Содержание

1. [Проблема](#проблема)
2. [Решение: Двухэтапный процесс](#решение-двухэтапный-процесс)
3. [Архитектура](#архитектура)
4. [Этап 1: Подготовка (PREPARE)](#этап-1-подготовка-prepare)
5. [Этап 2: Развертывание (DEPLOY)](#этап-2-развертывание-deploy)
6. [Использование в Jenkins](#использование-в-jenkins)
7. [Локальное использование](#локальное-использование)
8. [Troubleshooting](#troubleshooting)

---

## 🎯 Проблема

IDM требует **заранее знать** полное содержимое sudoers файлов, включая **SHA256 хеши скриптов-оберток**. Но:

1. Скрипты-обертки генерируются динамически
2. SHA256 хеши вычисляются после генерации
3. Sudoers файлы формируются с подстановкой хешей
4. IDM требует согласования **до** развертывания

Это создает **"курица и яйцо"** проблему:
- Для sudoers нужны хеши → но хеши генерируются pipeline
- Для pipeline нужны sudo права → но права дает IDM после согласования sudoers

---

## 💡 Решение: Двухэтапный процесс

### Этап 1: PREPARE (Подготовка)
**Цель:** Сгенерировать sudoers файлы для копирования в IDM

**Действия:**
1. Генерация скриптов-оберток
2. Вычисление SHA256 хешей
3. Генерация sudoers с подставленными хешами
4. Сохранение в директорию для админа
5. Создание инструкции

**Результат:**
- ✅ Готовые sudoers файлы
- ✅ Скрипты с вычисленными хешами
- ✅ Инструкция для IDM
- ⚠️ Pipeline завершается (sudo прав еще нет)

---

### Этап 2: DEPLOY (Развертывание)
**Цель:** Полное развертывание системы мониторинга

**Предусловия:**
- ✅ Скрипты развернуты на сервере
- ✅ SHA256 хеши проверены
- ✅ Sudoers согласованы в IDM
- ✅ Права активированы на сервере

**Действия:**
1. Развертывание через Ansible
2. Настройка Vault Agent
3. Установка компонентов из tar.gz
4. Настройка User Systemd Units
5. Запуск сервисов

**Результат:**
- ✅ Система мониторинга развернута
- ✅ Все сервисы запущены
- ✅ Безопасность соблюдена

---

## 🏗️ Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                     ЭТАП 1: PREPARE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Jenkins Pipeline (STAGE_MODE=prepare)                          │
│      ↓                                                           │
│  1. Генерация скриптов-оберток                                  │
│      ├── manage_firewall.sh                                     │
│      ├── manage_vault_certs.sh                                  │
│      └── call_rlm_api.sh                                        │
│      ↓                                                           │
│  2. Вычисление SHA256                                           │
│      ├── hash1: abc123...                                       │
│      ├── hash2: def456...                                       │
│      └── hash3: ghi789...                                       │
│      ↓                                                           │
│  3. Генерация sudoers с хешами                                  │
│      ├── CI10742292-lnx-mon_ci      (для ТУЗ)                  │
│      ├── CI10742292-lnx-mon_admin   (для ПУЗ)                  │
│      └── CI10742292-lnx-mon_ro      (для RO)                   │
│      ↓                                                           │
│  4. Сохранение артефактов                                       │
│      └── $HOME/monitoring_sudoers_generated/CI10742292/         │
│           ├── sudoers/                                          │
│           │   ├── CI10742292-lnx-mon_ci                        │
│           │   ├── CI10742292-lnx-mon_admin                     │
│           │   └── CI10742292-lnx-mon_ro                        │
│           ├── scripts/                                          │
│           │   └── (все скрипты-обертки)                        │
│           ├── INSTRUCTIONS.md                                   │
│           └── README.txt                                        │
│      ↓                                                           │
│  5. Pipeline завершается (sudo прав нет)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

                            ⬇️

┌─────────────────────────────────────────────────────────────────┐
│                 РУЧНЫЕ ДЕЙСТВИЯ АДМИНИСТРАТОРА                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Скопировать скрипты на сервер                               │
│     scp scripts/*.sh server:/opt/monitoring/scripts/wrappers/   │
│                                                                 │
│  2. Проверить SHA256 хеши                                       │
│     sha256sum /opt/monitoring/scripts/wrappers/*.sh             │
│                                                                 │
│  3. Создать заявки в IDM (3 штуки)                              │
│     - Для CI_USER                                               │
│     - Для ADMIN_USER                                            │
│     - Для RO_USER                                               │
│                                                                 │
│  4. Скопировать содержимое sudoers в заявки                     │
│                                                                 │
│  5. Дождаться согласования (1-3 дня)                            │
│                                                                 │
│  6. Проверить права на сервере                                  │
│     sudo -l -U CI10742292-lnx-mon_ci                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

                            ⬇️

┌─────────────────────────────────────────────────────────────────┐
│                     ЭТАП 2: DEPLOY                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Jenkins Pipeline (STAGE_MODE=deploy)                           │
│      ↓                                                           │
│  1. Проверка sudo прав (через test команды)                     │
│      ↓                                                           │
│  2. Ansible deployment                                          │
│      ├── Скачивание tar.gz (Prometheus, Grafana, Harvest)      │
│      ├── Распаковка в /opt/monitoring/bin/                     │
│      ├── Настройка Vault Agent                                  │
│      ├── Генерация конфигов с секретами                        │
│      └── Deployment User Systemd Units                          │
│      ↓                                                           │
│  3. Запуск сервисов                                             │
│      ├── systemctl --user enable prometheus                     │
│      ├── systemctl --user start prometheus                      │
│      ├── ... (аналогично для grafana, harvest)                  │
│      ↓                                                           │
│  4. Проверка состояния                                          │
│      ├── systemctl --user status prometheus                     │
│      └── Проверка портов (9090, 3000, и т.д.)                  │
│                                                                 │
│  ✅ Развертывание завершено!                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 Этап 1: Подготовка (PREPARE)

### Запуск через Jenkins

```groovy
// В Jenkinsfile
parameters {
    choice(
        name: 'STAGE_MODE',
        choices: ['prepare', 'deploy'],
        description: 'Режим выполнения: prepare (генерация sudoers) или deploy (развертывание)'
    )
    // ... другие параметры
}
```

**Запуск:**
1. Открыть Jenkins Job
2. Нажать "Build with Parameters"
3. Выбрать **STAGE_MODE = prepare**
4. Указать остальные параметры (NAMESPACE_CI, SERVER_ADDRESS, etc.)
5. Запустить

**Результат:**
- Pipeline выполнит только stage "Генерация sudoers для IDM"
- Создаст артефакты в `$WORKSPACE/generated_sudoers_for_idm/`
- Выведет инструкцию в консоль
- Завершится с сообщением: "Sudoers сгенерированы. Скопируйте в IDM."

---

### Запуск локально (без Jenkins)

```bash
# Перейти в директорию sudoers
cd secure_deployment/sudoers

# Запустить генератор
./generate_sudoers_with_hashes.sh CI04523276_CI10742292

# Или указать свою директорию
./generate_sudoers_with_hashes.sh CI04523276_CI10742292 /tmp/my_sudoers
```

**Результат:**
```
$HOME/monitoring_sudoers_generated/CI10742292/
├── sudoers/
│   ├── CI10742292-lnx-mon_ci
│   ├── CI10742292-lnx-mon_admin
│   └── CI10742292-lnx-mon_ro
├── scripts/
│   ├── manage_firewall.sh
│   ├── manage_vault_certs.sh
│   └── call_rlm_api.sh
├── INSTRUCTIONS.md
└── README.txt
```

---

### Что делать со сгенерированными файлами

#### 1. Прочитать инструкцию

```bash
cat $HOME/monitoring_sudoers_generated/CI10742292/INSTRUCTIONS.md
```

#### 2. Развернуть скрипты на сервере

```bash
# Через SCP
cd $HOME/monitoring_sudoers_generated/CI10742292
scp scripts/*.sh user@server:/tmp/

# На сервере
ssh user@server
sudo mkdir -p /opt/monitoring/scripts/wrappers
sudo cp /tmp/*.sh /opt/monitoring/scripts/wrappers/
sudo chown CI10742292-lnx-mon_ci:CI10742292-lnx-mon_sys /opt/monitoring/scripts/wrappers/*.sh
sudo chmod 750 /opt/monitoring/scripts/wrappers/*.sh
```

#### 3. Проверить SHA256

```bash
# На сервере
sha256sum /opt/monitoring/scripts/wrappers/*.sh

# Сравнить с хешами в INSTRUCTIONS.md
```

#### 4. Создать заявки в IDM

**Для каждого пользователя (3 заявки):**

1. Открыть https://idm.sberbank.ru/
2. Создать заявку "Права sudo для Linux"
3. Указать пользователя: `CI10742292-lnx-mon_ci` (или admin/ro)
4. Указать целевые серверы (FQDN)
5. **Содержимое sudoers** → скопировать из `sudoers/CI10742292-lnx-mon_ci`
6. **Обоснование:**
   ```
   Предоставление прав для развертывания системы мониторинга.
   Используются скрипт-обертки с SHA256 хешами для безопасности.
   Соответствует требованиям кибербезопасности.
   ```
7. Отправить на согласование

#### 5. Ожидание согласования

- Администраторы ОС
- Кибербезопасность
- IDM администраторы

**Время:** обычно 1-3 рабочих дня

#### 6. Проверка прав

```bash
# После согласования заявок
sudo -l -U CI10742292-lnx-mon_ci
sudo -l -U CI10742292-lnx-mon_admin
sudo -l -U CI10742292-lnx-mon_ro
```

---

## 🚀 Этап 2: Развертывание (DEPLOY)

### Предусловия

Перед запуском **ОБЯЗАТЕЛЬНО** проверить:

- [ ] Скрипты развернуты в `/opt/monitoring/scripts/wrappers/`
- [ ] SHA256 хеши проверены и совпадают
- [ ] Все 3 заявки в IDM согласованы
- [ ] Права активированы на сервере (`sudo -l -U ...`)

### Запуск через Jenkins

1. Открыть Jenkins Job
2. Нажать "Build with Parameters"
3. Выбрать **STAGE_MODE = deploy**
4. Указать те же параметры, что и в PREPARE
5. Запустить

**Pipeline выполнит:**
1. Проверку sudo прав
2. Установку компонентов
3. Настройку Vault Agent
4. Развертывание User Systemd Units
5. Запуск сервисов
6. Проверку состояния

---

## 🔧 Использование в Jenkins

### Параметры Pipeline

```groovy
parameters {
    choice(
        name: 'STAGE_MODE',
        choices: ['prepare', 'deploy'],
        description: '''
        prepare - Генерация sudoers для IDM (первый запуск)
        deploy  - Полное развертывание (после согласования в IDM)
        '''
    )
    string(
        name: 'NAMESPACE_CI',
        defaultValue: 'CI04523276_CI10742292',
        description: 'Namespace для Vault и извлечения KAE_STEND'
    )
    string(
        name: 'SERVER_ADDRESS',
        defaultValue: '',
        description: 'FQDN или IP целевого сервера'
    )
    // ... другие параметры
}
```

### Stage: Генерация sudoers

```groovy
stage('Генерация sudoers для IDM') {
    when {
        expression { params.STAGE_MODE == 'prepare' }
    }
    steps {
        script {
            echo """
            ╔════════════════════════════════════════════════════════════╗
            ║  РЕЖИМ: PREPARE - Генерация sudoers для IDM               ║
            ╚════════════════════════════════════════════════════════════╝
            """
            
            // Создать директорию
            sh "mkdir -p ${env.WORKSPACE}/generated_sudoers_for_idm"
            
            // Запустить генератор
            sh """
                cd secure_deployment/sudoers
                ./generate_sudoers_with_hashes.sh ${params.NAMESPACE_CI} ${env.WORKSPACE}/generated_sudoers_for_idm
            """
            
            // Архивировать артефакты
            archiveArtifacts artifacts: 'generated_sudoers_for_idm/**/*', fingerprint: true
            
            // Вывести инструкцию
            def instructions = readFile("${env.WORKSPACE}/generated_sudoers_for_idm/${env.KAE_STEND}/INSTRUCTIONS.md")
            echo instructions
            
            // Завершить pipeline
            error("""
            ═══════════════════════════════════════════════════════════
            ✓ SUDOERS УСПЕШНО СГЕНЕРИРОВАНЫ!
            ═══════════════════════════════════════════════════════════
            
            СЛЕДУЮЩИЕ ШАГИ:
            
            1. Скачать артефакты из Jenkins
            2. Прочитать INSTRUCTIONS.md
            3. Развернуть скрипты на сервере
            4. Создать заявки в IDM (3 штуки)
            5. Дождаться согласования
            6. Запустить повторно с STAGE_MODE=deploy
            
            Артефакты: ${env.BUILD_URL}artifact/
            ═══════════════════════════════════════════════════════════
            """)
        }
    }
}
```

### Stage: Проверка прав (для DEPLOY)

```groovy
stage('Проверка sudo прав') {
    when {
        expression { params.STAGE_MODE == 'deploy' }
    }
    steps {
        script {
            echo "Проверка наличия sudo прав на сервере..."
            
            // Тест firewall wrapper
            def firewallTest = sh(
                script: """
                    ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \
                    'sudo /opt/monitoring/scripts/wrappers/manage_firewall.sh check prometheus || echo "FAIL"'
                """,
                returnStdout: true
            ).trim()
            
            if (firewallTest.contains("FAIL")) {
                error("Sudo права не предоставлены! Проверьте IDM заявки.")
            }
            
            echo "✓ Sudo права подтверждены"
        }
    }
}
```

---

## 🖥️ Локальное использование

### Генерация sudoers

```bash
#!/bin/bash

# Установка переменных
NAMESPACE_CI="CI04523276_CI10742292"
OUTPUT_DIR="$HOME/monitoring_sudoers_generated"

# Генерация
cd secure_deployment/sudoers
./generate_sudoers_with_hashes.sh "$NAMESPACE_CI" "$OUTPUT_DIR"

# Проверка результата
ls -la "$OUTPUT_DIR/CI10742292/sudoers/"
```

### Проверка SHA256 локально

```bash
# Вычислить хеш
sha256sum secure_deployment/scripts/wrappers/manage_firewall.sh

# Найти в sudoers
grep "sha256:" $HOME/monitoring_sudoers_generated/CI10742292/sudoers/CI10742292-lnx-mon_ci
```

---

## 🔍 Troubleshooting

### Проблема: SHA256 не совпадает

**Симптом:**
```
sudo: command not permitted: /opt/monitoring/scripts/wrappers/manage_firewall.sh
```

**Причина:** Скрипт изменился после генерации sudoers.

**Решение:**
1. Пересоздать скрипты из артефактов
2. Или пересгенерировать sudoers и обновить заявки в IDM

```bash
# Проверить хеш на сервере
sha256sum /opt/monitoring/scripts/wrappers/manage_firewall.sh

# Сравнить с sudoers
sudo cat /etc/sudoers.d/CI10742292-lnx-mon_ci | grep sha256
```

---

### Проблема: Заявка в IDM отклонена

**Возможные причины:**
1. Недостаточное обоснование
2. Слишком широкие права (например, `bash -c *`)
3. Отсутствие SHA256 хешей
4. Переменные в критических командах

**Решение:**
1. Изучить замечания в IDM
2. Обновить templates sudoers
3. Пересгенерировать с `generate_sudoers_with_hashes.sh`
4. Создать новую заявку

---

### Проблема: Pipeline падает в DEPLOY режиме

**Симптом:**
```
Permission denied
```

**Причина:** Sudo права еще не активированы.

**Решение:**
1. Проверить статус заявок в IDM
2. Подождать 10-15 минут после согласования (синхронизация)
3. Проверить права вручную: `sudo -l -U CI10742292-lnx-mon_ci`

---

### Проблема: Не могу найти сгенерированные файлы

**Где искать:**

Через Jenkins:
```
${BUILD_URL}artifact/generated_sudoers_for_idm/
```

Локально:
```bash
# По умолчанию
$HOME/monitoring_sudoers_generated/

# Последний сгенерированный путь
cat $HOME/monitoring_sudoers_generated/.last_generated_path
```

---

## 📚 Дополнительные ресурсы

- [CORPORATE_SECURITY_RULES.md](CORPORATE_SECURITY_RULES.md) - Корпоративные требования
- [IDM_ACCOUNTS_GUIDE.md](IDM_ACCOUNTS_GUIDE.md) - Работа с IDM
- [SUDOERS_GUIDE.md](SUDOERS_GUIDE.md) - Детальная документация по sudoers

---

## ✅ Чеклист

### Этап PREPARE

- [ ] Запущен Jenkins Pipeline с `STAGE_MODE=prepare`
- [ ] Скрипты сгенерированы
- [ ] SHA256 хеши вычислены
- [ ] Sudoers файлы созданы
- [ ] Артефакты скачаны
- [ ] Инструкция прочитана

### Этап развертывания скриптов

- [ ] Скрипты скопированы на сервер
- [ ] Права установлены (750)
- [ ] Владелец установлен (CI_USER:SYS_GROUP)
- [ ] SHA256 хеши проверены

### Этап IDM

- [ ] Создана заявка для CI_USER
- [ ] Создана заявка для ADMIN_USER
- [ ] Создана заявка для RO_USER
- [ ] Все заявки согласованы
- [ ] Права активированы (`sudo -l -U ...`)

### Этап DEPLOY

- [ ] Запущен Jenkins Pipeline с `STAGE_MODE=deploy`
- [ ] Проверка sudo прав прошла
- [ ] Компоненты установлены
- [ ] Сервисы запущены
- [ ] Мониторинг работает

---

**Версия документа:** 1.0  
**Дата создания:** November 19, 2024



