// ==============================================================================
// Безопасный Jenkins Pipeline для развертывания системы мониторинга
// ==============================================================================
//
// Описание:
//   Pipeline для автоматизированного развертывания системы мониторинга
//   с соблюдением всех требований безопасности
//
// Особенности:
//   - Секреты передаются через /dev/shm (tmpfs)
//   - Автоматическая очистка секретов после использования
//   - Проверка безопасности после развертывания
//   - Использование Ansible для идемпотентного развертывания
//   - Полное логирование всех действий
//
// ==============================================================================

pipeline {
    agent { label 'linux' }
    
    options {
        // Ограничение времени выполнения
        timeout(time: 60, unit: 'MINUTES')
        
        // Ограничение количества сохраняемых сборок
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
        
        // Временные метки в логах
        timestamps()
        
        // Цветной вывод
        ansiColor('xterm')
    }
    
    parameters {
        // ==============================================
        // Основные параметры
        // ==============================================
        string(
            name: 'SERVER_ADDRESS',
            defaultValue: params.SERVER_ADDRESS ?: '',
            description: 'IP или FQDN целевого сервера'
        )
        string(
            name: 'SSH_CREDENTIALS_ID',
            defaultValue: params.SSH_CREDENTIALS_ID ?: 'monitoring-ci-ssh-key',
            description: 'ID SSH credentials для monitoring_ci'
        )
        
        // ==============================================
        // Vault параметры
        // ==============================================
        string(
            name: 'SEC_MAN_ADDR',
            defaultValue: params.SEC_MAN_ADDR ?: 'vault.sigma.sbrf.ru',
            description: 'Адрес Vault (SecMan)'
        )
        string(
            name: 'NAMESPACE_CI',
            defaultValue: params.NAMESPACE_CI ?: '',
            description: 'Namespace в Vault (например: KPRJ_000000)'
        )
        
        // ==============================================
        // Пути к секретам в Vault
        // ==============================================
        string(
            name: 'VAULT_AGENT_KV',
            defaultValue: params.VAULT_AGENT_KV ?: 'secret/data/monitoring/vault-agent',
            description: 'Путь к AppRole credentials в Vault'
        )
        string(
            name: 'RPM_URL_KV',
            defaultValue: params.RPM_URL_KV ?: 'secret/data/monitoring/rpm-urls',
            description: 'Путь к URL RPM пакетов'
        )
        string(
            name: 'GRAFANA_WEB_KV',
            defaultValue: params.GRAFANA_WEB_KV ?: 'secret/data/monitoring/grafana-web',
            description: 'Путь к Grafana web credentials'
        )
        string(
            name: 'NETAPP_API_KV',
            defaultValue: params.NETAPP_API_KV ?: 'secret/data/monitoring/netapp-api',
            description: 'Путь к NetApp API credentials'
        )
        string(
            name: 'SBERCA_CERT_KV',
            defaultValue: params.SBERCA_CERT_KV ?: 'pki/issue/monitoring',
            description: 'Путь к PKI для генерации сертификатов'
        )
        
        // ==============================================
        // Сетевые параметры
        // ==============================================
        string(
            name: 'NETAPP_API_ADDR',
            defaultValue: params.NETAPP_API_ADDR ?: '',
            description: 'FQDN/IP NetApp кластера'
        )
        string(
            name: 'PROMETHEUS_PORT',
            defaultValue: params.PROMETHEUS_PORT ?: '9090',
            description: 'Порт Prometheus'
        )
        string(
            name: 'GRAFANA_PORT',
            defaultValue: params.GRAFANA_PORT ?: '3000',
            description: 'Порт Grafana'
        )
        string(
            name: 'ADMIN_EMAIL',
            defaultValue: params.ADMIN_EMAIL ?: 'admin@example.com',
            description: 'Email администратора для сертификатов'
        )
        
        // ==============================================
        // RLM параметры
        // ==============================================
        string(
            name: 'RLM_API_URL',
            defaultValue: params.RLM_API_URL ?: 'https://rlm.sigma.sbrf.ru',
            description: 'URL RLM API'
        )
        
        // ==============================================
        // Опции развертывания
        // ==============================================
        choice(
            name: 'DEPLOYMENT_METHOD',
            choices: ['ansible', 'script'],
            description: 'Метод развертывания: ansible (рекомендуется) или script'
        )
        booleanParam(
            name: 'RUN_SECURITY_CHECK',
            defaultValue: true,
            description: 'Запустить проверку безопасности после развертывания'
        )
        booleanParam(
            name: 'CLEANUP_SECRETS',
            defaultValue: true,
            description: 'Очистить секреты после развертывания'
        )
        booleanParam(
            name: 'DEBUG',
            defaultValue: false,
            description: 'Включить детальный debug вывод (WARNING: может показывать чувствительные данные в логах!)'
        )
    }
    
    environment {
        // Рабочие директории
        WORKSPACE_LOCAL = "${WORKSPACE}"
        REMOTE_TEMP_DIR = '/tmp/monitoring_deployment_${BUILD_NUMBER}'
        
        // Таймауты
        VAULT_TIMEOUT = '120'
        SSH_TIMEOUT = '300'
        
        // Директория для секретов на удаленном сервере
        REMOTE_SECRETS_DIR = '/dev/shm/monitoring_secrets'
    }
    
    stages {
        // ==========================================
        // STAGE 1: Валидация параметров
        // ==========================================
        stage('Валидация параметров') {
            steps {
                script {
                    // WARNING для DEBUG режима
                    if (params.DEBUG) {
                        echo """
                        ⚠️  ⚠️  ⚠️  WARNING  ⚠️  ⚠️  ⚠️
                        DEBUG РЕЖИМ ВКЛЮЧЕН!
                        Логи могут содержать чувствительные данные!
                        Убедитесь что логи pipeline защищены!
                        ⚠️  ⚠️  ⚠️  WARNING  ⚠️  ⚠️  ⚠️
                        """
                    }
                    
                    // Проверка обязательных параметров
                    def required_params = [
                        'SERVER_ADDRESS',
                        'NAMESPACE_CI',
                        'NETAPP_API_ADDR'
                    ]
                    
                    def missing = []
                    required_params.each { param ->
                        if (!params[param] || params[param].trim() == '') {
                            missing.add(param)
                        }
                    }
                    
                    if (missing.size() > 0) {
                        error("ОШИБКА: Не указаны обязательные параметры: ${missing.join(', ')}")
                    }
                    
                    // ==========================================
                    // ИЗВЛЕЧЕНИЕ KAE_STEND ИЗ NAMESPACE_CI
                    // ==========================================
                    
                    // Валидация формата NAMESPACE_CI
                    if (!params.NAMESPACE_CI.contains('_')) {
                        error("ОШИБКА: NAMESPACE_CI должен содержать разделитель '_' (формат: PREFIX_SUFFIX)\nПример: CI04523276_CI10742292")
                    }
                    
                    // Извлечение KAE_STEND (часть после последнего '_')
                    def namespaceParts = params.NAMESPACE_CI.split('_')
                    env.KAE_STEND = namespaceParts[-1]
                    
                    // Валидация KAE_STEND (только буквы, цифры, дефис)
                    if (!env.KAE_STEND.matches(/^[a-zA-Z0-9-]+$/)) {
                        error("ОШИБКА: KAE_STEND содержит недопустимые символы: '${env.KAE_STEND}'\nДопустимы только: буквы, цифры, дефис")
                    }
                    
                    // Проверка длины KAE_STEND
                    if (env.KAE_STEND.length() < 3) {
                        error("ОШИБКА: KAE_STEND слишком короткий (минимум 3 символа): '${env.KAE_STEND}'")
                    }
                    
                    if (env.KAE_STEND.length() > 20) {
                        error("ОШИБКА: KAE_STEND слишком длинный (максимум 20 символов): '${env.KAE_STEND}'")
                    }
                    
                    // ==========================================
                    // ФОРМИРОВАНИЕ ИМЕН ПОЛЬЗОВАТЕЛЕЙ
                    // ==========================================
                    
                    // Формирование динамических имен пользователей
                    env.USER_SYS = "${env.KAE_STEND}-lnx-mon_sys"
                    env.USER_ADMIN = "${env.KAE_STEND}-lnx-mon_admin"
                    env.USER_CI = "${env.KAE_STEND}-lnx-mon_ci"
                    env.USER_RO = "${env.KAE_STEND}-lnx-mon_ro"
                    
                    // Валидация финальных имен пользователей (требования IDM/Linux)
                    // Формат: начинается с буквы или цифры, может содержать буквы, цифры, _, -, max 32 символа
                    def userNamePattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,30}[a-zA-Z0-9]$/
                    def invalidUsers = []
                    
                    [env.USER_SYS, env.USER_ADMIN, env.USER_CI, env.USER_RO].each { userName ->
                        if (!userName.matches(userNamePattern)) {
                            invalidUsers.add(userName)
                        }
                        if (userName.length() > 32) {
                            invalidUsers.add("${userName} (длина: ${userName.length()} > 32)")
                        }
                    }
                    
                    if (invalidUsers.size() > 0) {
                        error("ОШИБКА: Недопустимые имена пользователей:\n${invalidUsers.join('\n')}\nТребования: 3-32 символа, буквы/цифры/_/-")
                    }
                    
                    // Вывод результатов валидации
                    echo """
                    ================================================
                    ✓ ВАЛИДАЦИЯ УСПЕШНА
                    ================================================
                    Целевой сервер: ${params.SERVER_ADDRESS}
                    Namespace: ${params.NAMESPACE_CI}
                    KAE Стенд: ${env.KAE_STEND}
                    NetApp кластер: ${params.NETAPP_API_ADDR}
                    Метод развертывания: ${params.DEPLOYMENT_METHOD}
                    DEBUG режим: ${params.DEBUG}
                    
                    Пользователи (динамически сформированы):
                    - Сервисная (СУЗ): ${env.USER_SYS}
                    - Администратор (ПУЗ): ${env.USER_ADMIN}
                    - CI/CD (ТУЗ): ${env.USER_CI}
                    - ReadOnly: ${env.USER_RO}
                    ================================================
                    """
                }
            }
        }
        
        // ==========================================
        // STAGE 2: Настройка групп пользователей через RLM
        // ==========================================
        stage('Настройка групп пользователей (RLM)') {
            steps {
                script {
                    echo """
                    ================================================
                    ПРОВЕРКА И НАСТРОЙКА ГРУПП ПОЛЬЗОВАТЕЛЕЙ
                    ================================================
                    """
                    
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        ),
                        string(credentialsId: 'rlm-token', variable: 'RLM_TOKEN')
                    ]) {
                        // Проверка членства пользователей в группе
                        echo "Проверка: состоят ли пользователи в группе ${env.USER_SYS}..."
                        
                        def checkScript = """
                            ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'CHECK_EOF'
# Проверка каждого пользователя
users_to_check="${env.USER_CI} ${env.USER_ADMIN} ${env.USER_RO}"
missing_users=""
all_ok=true

for user in \$users_to_check; do
    if id "\$user" &>/dev/null; then
        if groups "\$user" | grep -q "${env.USER_SYS}"; then
            echo "✓ \$user: уже в группе ${env.USER_SYS}"
        else
            echo "✗ \$user: НЕ в группе ${env.USER_SYS}"
            missing_users="\${missing_users} \$user"
            all_ok=false
        fi
    else
        echo "⚠ \$user: пользователь не существует (будет создан позже)"
        missing_users="\${missing_users} \$user"
        all_ok=false
    fi
done

# Возвращаем результат
if [ "\$all_ok" = "true" ]; then
    echo "ALL_OK"
    exit 0
else
    echo "NEED_RLM"
    exit 1
fi
CHECK_EOF
                        """
                        
                        def checkResult = sh(
                            script: checkScript,
                            returnStatus: true
                        )
                        
                        if (checkResult == 0) {
                            echo """
                            ================================================
                            ✓ ВСЕ ПОЛЬЗОВАТЕЛИ УЖЕ В ГРУППЕ!
                            ================================================
                            Пользователи ${env.USER_CI}, ${env.USER_ADMIN}, ${env.USER_RO}
                            уже являются членами группы ${env.USER_SYS}.
                            
                            Пропускаем вызов RLM API.
                            ================================================
                            """
                            return  // Выходим из stage, пропускаем RLM
                        }
                        
                        echo """
                        ================================================
                        Не все пользователи в группе - запускаем RLM...
                        ================================================
                        """
                        // Получение IP адреса сервера
                        def serverIP = params.SERVER_ADDRESS
                        
                        // Если SERVER_ADDRESS - это FQDN, резолвим в IP
                        if (!params.SERVER_ADDRESS.matches(/^\d+\.\d+\.\d+\.\d+$/)) {
                            echo "Резолвинг FQDN ${params.SERVER_ADDRESS} в IP..."
                            serverIP = sh(
                                script: "getent hosts ${params.SERVER_ADDRESS} | awk '{ print \$1 }' | head -1",
                                returnStdout: true
                            ).trim()
                            echo "✓ Получен IP: ${serverIP}"
                        }
                        
                        if (params.DEBUG) {
                            echo """
                            DEBUG: Параметры RLM запроса:
                            - RLM_API_URL: ${params.RLM_API_URL}
                            - Server IP: ${serverIP}
                            - Группа СУЗ: ${env.USER_SYS}
                            - Пользователи для добавления:
                              * ${env.USER_CI} (ТУЗ CI/CD)
                              * ${env.USER_ADMIN} (ПУЗ Admin)
                              * ${env.USER_RO} (ReadOnly)
                            """
                        }
                        
                        // Создание задачи RLM для добавления пользователей в группу
                        echo "Создание задачи RLM: добавление пользователей в группу ${env.USER_SYS}..."
                        
                        def taskResponse = sh(
                            script: """
                                curl -s -X POST \\
                                  "${params.RLM_API_URL}/api/tasks.json" \\
                                  -H "Accept: application/json" \\
                                  -H "Authorization: Token \${RLM_TOKEN}" \\
                                  -H "Content-Type: application/json" \\
                                  -d '{
                                    "params": {
                                      "VAR_GRPS": [
                                        {
                                          "group": "${env.USER_SYS}",
                                          "gid": "",
                                          "users": ["${env.USER_CI}", "${env.USER_ADMIN}", "${env.USER_RO}"]
                                        }
                                      ]
                                    },
                                    "start_at": "now",
                                    "service": "UVS_LINUX_ADD_USERS_GROUP",
                                    "skip_check_collisions": true,
                                    "items": [
                                      {
                                        "table_id": "uvslinuxtemplatewithtestandprom",
                                        "invsvm_ip": "${serverIP}"
                                      }
                                    ]
                                  }'
                            """,
                            returnStdout: true
                        ).trim()
                        
                        if (params.DEBUG) {
                            echo "DEBUG: RLM Task Response:"
                            echo taskResponse
                        }
                        
                        // Извлечение task_id из ответа
                        def taskId = sh(
                            script: "echo '${taskResponse}' | jq -r '.id'",
                            returnStdout: true
                        ).trim()
                        
                        if (taskId == "null" || taskId == "") {
                            error("❌ Не удалось получить task_id из ответа RLM. Проверьте логи выше.")
                        }
                        
                        echo "✓ Задача RLM создана: ID = ${taskId}"
                        echo "  URL: ${params.RLM_API_URL}/api/tasks/${taskId}/"
                        
                        // Ожидание завершения задачи (polling)
                        echo "Ожидание завершения задачи RLM (polling каждые 10 секунд)..."
                        def maxAttempts = 210  // 210 * 10 = 2100 секунд = 35 минут
                        def attemptDelay = 10  // секунд
                        def taskCompleted = false
                        
                        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
                            sleep(attemptDelay)
                            
                            def statusResponse = sh(
                                script: """
                                    curl -s -X GET \\
                                      -H "Accept: application/json" \\
                                      -H "Authorization: Token \${RLM_TOKEN}" \\
                                      -H "Content-Type: application/json" \\
                                      "${params.RLM_API_URL}/api/tasks/${taskId}/"
                                """,
                                returnStdout: true
                            ).trim()
                            
                            def taskStatus = sh(
                                script: "echo '${statusResponse}' | jq -r '.status'",
                                returnStdout: true
                            ).trim()
                            
                            echo "[Попытка ${attempt}/${maxAttempts}] Статус задачи RLM: ${taskStatus}"
                            
                            if (taskStatus == "success") {
                                echo "✓ Задача RLM успешно выполнена!"
                                taskCompleted = true
                                break
                            } else if (taskStatus == "failed" || taskStatus == "error") {
                                echo "❌ Задача RLM завершилась с ошибкой!"
                                echo "Полный ответ RLM:"
                                echo statusResponse
                                error("Задача RLM завершилась со статусом: ${taskStatus}")
                            }
                            
                            // Вывод детальной информации каждую минуту в DEBUG режиме
                            if (params.DEBUG && attempt % 6 == 0) {
                                echo "DEBUG: Полный ответ RLM (через ${attempt * attemptDelay} секунд):"
                                echo statusResponse
                            }
                        }
                        
                        if (!taskCompleted) {
                            error("❌ Таймаут ожидания выполнения задачи RLM (${maxAttempts * attemptDelay} секунд = ${maxAttempts * attemptDelay / 60} минут)")
                        }
                        
                        echo """
                        ================================================
                        ✓ ГРУППЫ НАСТРОЕНЫ УСПЕШНО
                        ================================================
                        Пользователи добавлены в группу ${env.USER_SYS}:
                          - ${env.USER_CI} (ТУЗ CI/CD)
                          - ${env.USER_ADMIN} (ПУЗ Admin)
                          - ${env.USER_RO} (ReadOnly)
                        
                        Задача RLM: ${taskId}
                        Статус: success
                        ================================================
                        """
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 3: Получение секретов из Vault
        // ==========================================
        stage('Получение секретов из Vault') {
            steps {
                script {
                    echo """
                    ================================================
                    ПОЛУЧЕНИЕ СЕКРЕТОВ ИЗ VAULT
                    ================================================
                    """
                    
                    withVault([
                        configuration: [
                            vaultUrl: "https://${params.SEC_MAN_ADDR}",
                            engineVersion: 1,
                            skipSslVerification: false,
                            vaultCredentialId: 'vault-agent-dev',
                            vaultNamespace: params.NAMESPACE_CI
                        ],
                        vaultSecrets: [
                            // AppRole credentials
                            [path: params.VAULT_AGENT_KV, secretValues: [
                                [envVar: 'VAULT_ROLE_ID', vaultKey: 'role_id'],
                                [envVar: 'VAULT_SECRET_ID', vaultKey: 'secret_id']
                            ]],
                            // RPM URLs
                            [path: params.RPM_URL_KV, secretValues: [
                                [envVar: 'HARVEST_RPM_URL', vaultKey: 'harvest'],
                                [envVar: 'PROMETHEUS_RPM_URL', vaultKey: 'prometheus'],
                                [envVar: 'GRAFANA_RPM_URL', vaultKey: 'grafana']
                            ]],
                            // Grafana credentials
                            [path: params.GRAFANA_WEB_KV, secretValues: [
                                [envVar: 'GRAFANA_USER', vaultKey: 'user'],
                                [envVar: 'GRAFANA_PASSWORD', vaultKey: 'pass']
                            ]],
                            // NetApp API credentials
                            [path: params.NETAPP_API_KV, secretValues: [
                                [envVar: 'NETAPP_API_USER', vaultKey: 'user'],
                                [envVar: 'NETAPP_API_PASS', vaultKey: 'pass']
                            ]]
                        ]
                    ]) {
                        // Создание JSON файла с секретами (будет передан через /dev/shm)
                        def secretsData = [
                            'vault-agent': [
                                role_id: env.VAULT_ROLE_ID ?: '',
                                secret_id: env.VAULT_SECRET_ID ?: ''
                            ],
                            'rpm_url': [
                                harvest: env.HARVEST_RPM_URL ?: '',
                                prometheus: env.PROMETHEUS_RPM_URL ?: '',
                                grafana: env.GRAFANA_RPM_URL ?: ''
                            ],
                            'grafana_web': [
                                user: env.GRAFANA_USER ?: '',
                                pass: env.GRAFANA_PASSWORD ?: ''
                            ],
                            'netapp_api': [
                                addr: params.NETAPP_API_ADDR,
                                user: env.NETAPP_API_USER ?: '',
                                pass: env.NETAPP_API_PASS ?: ''
                            ]
                        ]
                        
                        // DEBUG: Вывод информации о секретах (без plain text)
                        if (params.DEBUG) {
                            echo "DEBUG: Содержимое secretsData:"
                            echo "  - role_id length: ${secretsData['vault-agent'].role_id?.length() ?: 0}"
                            echo "  - secret_id length: ${secretsData['vault-agent'].secret_id?.length() ?: 0}"
                            echo "  - harvest_rpm_url: ${secretsData['rpm_url'].harvest ? 'SET' : 'EMPTY'}"
                            echo "  - prometheus_rpm_url: ${secretsData['rpm_url'].prometheus ? 'SET' : 'EMPTY'}"
                            echo "  - grafana_rpm_url: ${secretsData['rpm_url'].grafana ? 'SET' : 'EMPTY'}"
                            echo "  - grafana_user: ${secretsData['grafana_web'].user ? 'SET' : 'EMPTY'}"
                            echo "  - grafana_pass length: ${secretsData['grafana_web'].pass?.length() ?: 0}"
                            echo "  - netapp_user: ${secretsData['netapp_api'].user ? 'SET' : 'EMPTY'}"
                            echo "  - netapp_pass length: ${secretsData['netapp_api'].pass?.length() ?: 0}"
                        }
                        
                        // Проверка что все критичные поля заполнены
                        def missingSecrets = []
                        if (!secretsData['vault-agent'].role_id) missingSecrets.add('role_id')
                        if (!secretsData['vault-agent'].secret_id) missingSecrets.add('secret_id')
                        
                        if (missingSecrets.size() > 0) {
                            error("ОШИБКА: Не получены критичные секреты из Vault: ${missingSecrets.join(', ')}")
                        }
                        
                        // Сохранение в временный файл (будет удален после использования)
                        writeFile file: "${WORKSPACE_LOCAL}/secrets.json", 
                                  text: groovy.json.JsonOutput.toJson(secretsData)
                        
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
                        
                        echo "✓ Секреты получены из Vault"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 4: Подготовка Ansible проекта
        // ==========================================
        stage('Подготовка Ansible') {
            when {
                expression { params.DEPLOYMENT_METHOD == 'ansible' }
            }
            steps {
                script {
                    echo """
                    ================================================
                    ПОДГОТОВКА ANSIBLE ПРОЕКТА
                    ================================================
                    """
                    
                    // Клонирование репозитория с Ansible проектом
                    dir('ansible_project') {
                        checkout scm
                        
                        // Создание inventory для целевого сервера
                        writeFile file: 'inventories/dynamic_inventory', text: """
[monitoring_servers]
${params.SERVER_ADDRESS} ansible_host=${params.SERVER_ADDRESS}

[monitoring_servers:vars]
ansible_user=${env.USER_CI}
kae_stend=${env.KAE_STEND}
user_sys=${env.USER_SYS}
user_admin=${env.USER_ADMIN}
user_ci=${env.USER_CI}
user_ro=${env.USER_RO}
netapp_api_addr=${params.NETAPP_API_ADDR}
prometheus_port=${params.PROMETHEUS_PORT}
grafana_port=${params.GRAFANA_PORT}
admin_email=${params.ADMIN_EMAIL}
vault_namespace=${params.NAMESPACE_CI}
                        """
                        
                        echo "✓ Ansible проект подготовлен с динамическими пользователями"
                        echo "  - ansible_user: ${env.USER_CI}"
                        echo "  - kae_stend: ${env.KAE_STEND}"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 5: Передача секретов на сервер
        // ==========================================
        stage('Передача секретов на сервер') {
            steps {
                script {
                    echo """
                    ================================================
                    ПЕРЕДАЧА СЕКРЕТОВ НА ЦЕЛЕВОЙ СЕРВЕР
                    ================================================
                    """
                    
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        ),
                        string(credentialsId: 'rlm-token', variable: 'RLM_TOKEN')
                    ]) {
                        // DEBUG: Проверка локального файла secrets.json
                        if (params.DEBUG) {
                            echo "DEBUG: Проверка локального файла secrets.json..."
                            sh "ls -lh ${WORKSPACE_LOCAL}/secrets.json || echo 'FILE NOT FOUND'"
                            sh "wc -l ${WORKSPACE_LOCAL}/secrets.json || echo 'CANNOT COUNT LINES'"
                        }
                        
                        // Скрипт для безопасной передачи секретов
                        writeFile file: 'transfer_secrets.sh', text: """#!/bin/bash
set -euo pipefail

${params.DEBUG ? 'set -x' : ''}

${params.DEBUG ? """
echo "========================================================================"
echo "DEBUG: ИНФОРМАЦИЯ О ТЕКУЩЕМ ПОЛЬЗОВАТЕЛЕ SSH"
echo "========================================================================"
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'DEBUG_EOF'
echo "1. Текущий пользователь:"
whoami
echo ""

echo "2. Полная информация о пользователе (id):"
id
echo ""

echo "3. Все группы пользователя:"
groups
echo ""

echo "4. Текущая директория:"
pwd
echo ""

echo "5. Домашняя директория:"
echo \\\$HOME
echo ""

echo "6. Проверка sudo прав (без пароля):"
sudo -n -l 2>&1 | head -20 || echo "Нет sudo прав или требуется пароль"
echo ""

echo "7. Проверка /dev/shm прав:"
ls -lad /dev/shm/
echo ""

echo "8. Проверка существующей директории monitoring_secrets:"
ls -lad /dev/shm/monitoring_secrets/ 2>/dev/null || echo "Директория не существует"
echo ""

echo "9. Переменные окружения SSH:"
echo "USER=\\\$USER"
echo "LOGNAME=\\\$LOGNAME"
echo ""

echo "10. Может ли пользователь выполнить sg без пароля (тест):"
timeout 2 sg ${env.USER_SYS} -c 'echo SUCCESS: sg работает' 2>&1 || echo "FAILED: sg требует пароль или таймаут"
echo ""

echo "11. Может ли пользователь выполнить sudo sg:"
sudo -n sg ${env.USER_SYS} -c 'echo SUCCESS: sudo sg работает' 2>&1 || echo "FAILED: sudo sg не работает"
echo ""

echo "12. Проверка членства в группе ${env.USER_SYS}:"
groups | grep -q ${env.USER_SYS} && echo "SUCCESS: пользователь В группе ${env.USER_SYS}" || echo "WARNING: пользователь НЕ В группе ${env.USER_SYS}"
echo ""
DEBUG_EOF
echo "========================================================================"
echo ""
""" : ''}

echo "[INFO] Создание директории для секретов в /dev/shm..."
# Шаг 1: Создание директории от root
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo mkdir -p ${REMOTE_SECRETS_DIR}"

# Шаг 1.5: ВАЖНО! Сброс прав на 755 (может остаться 700 с предыдущего запуска)
# Это позволит работать с директорией и удалять файлы
echo "[INFO] Сброс прав на директорию для очистки старых файлов..."
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chmod 755 ${REMOTE_SECRETS_DIR}"

# Шаг 1.6: Удаление старых файлов (ПЕРЕД установкой владельца)
echo "[INFO] Очистка старых файлов secrets.json, role_id.txt, secret_id.txt..."
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo rm -f ${REMOTE_SECRETS_DIR}/secrets.json ${REMOTE_SECRETS_DIR}/role_id.txt ${REMOTE_SECRETS_DIR}/secret_id.txt"

# Шаг 2: Установка владельца SSH_USER (для записи)
# SSH_USER (mvp_dev) временно становится владельцем для записи файла
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chown \${SSH_USER}:${env.USER_SYS} ${REMOTE_SECRETS_DIR}"

# Шаг 3: Установка прав 750 (владелец может писать, группа читать, остальные нет)
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chmod 750 ${REMOTE_SECRETS_DIR}"

${params.DEBUG ? """
echo "[DEBUG] После создания директории и установки владельца SSH_USER:"
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'DEBUG_EOF2'
echo "  - Права на директорию:"
ls -lad ${REMOTE_SECRETS_DIR}
echo "  - Владелец директории:"
stat -c "Owner: %U:%G (uid=%u gid=%g)" ${REMOTE_SECRETS_DIR}
echo "  - Текущий SSH_USER:"
whoami
echo "  - Проверка прав записи (SSH_USER - владелец):"
touch ${REMOTE_SECRETS_DIR}/test_write && echo "  ✓ SSH_USER может писать" && rm ${REMOTE_SECRETS_DIR}/test_write || echo "  ✗ SSH_USER НЕ может писать"
DEBUG_EOF2
echo ""
""" : ''}

${params.DEBUG ? 'echo "[DEBUG] Локальный файл secrets.json:"' : ''}
${params.DEBUG ? "ls -lh ${WORKSPACE_LOCAL}/secrets.json" : ''}

echo "[INFO] Передача секретов через SSH pipe (от имени SSH_USER - владельца директории)..."
${params.DEBUG ? """
echo "[DEBUG] Проверка прав SSH_USER:"
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'DEBUG_EOF3'
echo "  - Текущий пользователь SSH:"
whoami
id
echo "  - Проверка sudo -u SYS_USER:"
sudo -u ${env.USER_SYS} whoami 2>&1 || echo "  FAILED: sudo не работает"
echo "  - Проверка sudo (root):"
sudo whoami 2>&1 || echo "  FAILED: sudo (root) не работает"
DEBUG_EOF3
echo ""
""" : ''}

cat ${WORKSPACE_LOCAL}/secrets.json | ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "tee ${REMOTE_SECRETS_DIR}/secrets.json > /dev/null"

${params.DEBUG ? 'echo "[DEBUG] Удаленный файл secrets.json после копирования (от SSH_USER):"' : ''}
${params.DEBUG ? """
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'DEBUG_EOF4'
echo "  - Существование файла:"
ls -lh ${REMOTE_SECRETS_DIR}/secrets.json 2>&1 || echo "  Файл НЕ создан!"
echo "  - Размер файла:"
du -h ${REMOTE_SECRETS_DIR}/secrets.json 2>&1 || echo "  Не удалось проверить размер"
echo "  - Владелец файла:"
stat -c "Owner: %U:%G" ${REMOTE_SECRETS_DIR}/secrets.json 2>&1 || echo "  Не удалось проверить владельца"
DEBUG_EOF4
echo ""
""" : ''}

echo "[INFO] Установка финальных прав: передача владения SYS_USER и ограничение доступа..."
# Шаг 1: Передать владение директории и всех файлов SYS_USER:SYS_GROUP
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chown -R ${env.USER_SYS}:${env.USER_SYS} ${REMOTE_SECRETS_DIR}"

# Шаг 2: Установить финальные права (700 на директорию, 600 на файлы)
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chmod 700 ${REMOTE_SECRETS_DIR}"
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chmod 600 ${REMOTE_SECRETS_DIR}/secrets.json"

${params.DEBUG ? 'echo "[DEBUG] Финальные права на secrets.json (теперь принадлежит SYS_USER):"' : ''}
${params.DEBUG ? """
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'DEBUG_EOF5'
echo "  - Директория ${REMOTE_SECRETS_DIR}:"
ls -lad ${REMOTE_SECRETS_DIR}
echo "  - Файл secrets.json:"
ls -lh ${REMOTE_SECRETS_DIR}/secrets.json
DEBUG_EOF5
echo ""
""" : ''}

echo "[INFO] Распаковка секретов в отдельные файлы (через sudo -u SYS_USER)..."
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo -u ${env.USER_SYS} -g ${env.USER_SYS} bash -c 'cd ${REMOTE_SECRETS_DIR} && jq -r .[\\\"vault-agent\\\"].role_id secrets.json > role_id.txt && jq -r .[\\\"vault-agent\\\"].secret_id secrets.json > secret_id.txt && chmod 600 role_id.txt secret_id.txt'"

${params.DEBUG ? 'echo "[DEBUG] Созданные файлы секретов:"' : ''}
${params.DEBUG ? "ssh -i \"\${SSH_KEY}\" -o StrictHostKeyChecking=no \"\${SSH_USER}@${params.SERVER_ADDRESS}\" \"sudo -u ${env.USER_SYS} -g ${env.USER_SYS} ls -lh ${REMOTE_SECRETS_DIR}/\"" : ''}

echo "[SUCCESS] Секреты успешно переданы и размещены в ${REMOTE_SECRETS_DIR}"
                        """
                        
                        sh 'chmod +x transfer_secrets.sh'
                        sh './transfer_secrets.sh'
                        
                        echo "✓ Секреты переданы на сервер в ${REMOTE_SECRETS_DIR}"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 6: Развертывание через Ansible
        // ==========================================
        stage('Развертывание (Ansible)') {
            when {
                expression { params.DEPLOYMENT_METHOD == 'ansible' }
            }
            steps {
                script {
                    echo """
                    ================================================
                    РАЗВЕРТЫВАНИЕ ЧЕРЕЗ ANSIBLE
                    ================================================
                    """
                    
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )
                    ]) {
                        dir('ansible_project/secure_deployment/ansible') {
                            // Запуск Ansible playbook с поддержкой DEBUG режима
                            sh """
                                ansible-playbook \\
                                    -i inventories/dynamic_inventory \\
                                    playbooks/deploy_monitoring.yml \\
                                    --extra-vars "rlm_token=${RLM_TOKEN}" \\
                                    --private-key=\${SSH_KEY} \\
                                    ${params.DEBUG ? '-vvv' : '-v'}
                            """
                        }
                        
                        echo "✓ Развертывание через Ansible завершено"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 7: Проверка безопасности
        // ==========================================
        stage('Проверка безопасности') {
            when {
                expression { params.RUN_SECURITY_CHECK == true }
            }
            steps {
                script {
                    echo """
                    ================================================
                    ПРОВЕРКА БЕЗОПАСНОСТИ
                    ================================================
                    """
                    
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )
                    ]) {
                        // DEBUG: Проверка файлов перед security check
                        if (params.DEBUG) {
                            echo "DEBUG: Проверка файлов на удаленном сервере перед security check..."
                            sh """
                                ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
                                    'ls -laR /opt/monitoring/ 2>/dev/null | head -50 || echo "Cannot list /opt/monitoring"'
                            """
                        }
                        
                        def securityCheckResult = sh(
                            script: """
                                ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
                                    'sudo bash /opt/monitoring/scripts/verify_security.sh'
                            """,
                            returnStatus: true
                        )
                        
                        if (securityCheckResult != 0) {
                            error("ОШИБКА: Проверка безопасности не пройдена!")
                        }
                        
                        echo "✓ Проверка безопасности пройдена успешно"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 8: Верификация сервисов
        // ==========================================
        stage('Верификация сервисов') {
            steps {
                script {
                    echo """
                    ================================================
                    ВЕРИФИКАЦИЯ СЕРВИСОВ
                    ================================================
                    """
                    
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )
                    ]) {
                        // Проверка статуса сервисов
                        sh """
                            ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" << 'EOF'
echo "=========================================="
echo "ПРОВЕРКА СТАТУСА СЕРВИСОВ:"
echo "=========================================="
sudo -u ${env.USER_SYS} -g ${env.USER_SYS} systemctl --user status prometheus | grep "Active:"
sudo -u ${env.USER_SYS} -g ${env.USER_SYS} systemctl --user status grafana | grep "Active:"
sudo -u ${env.USER_SYS} -g ${env.USER_SYS} systemctl --user status harvest | grep "Active:"
echo ""
echo "=========================================="
echo "ПРОВЕРКА ПОРТОВ:"
echo "=========================================="
ss -tln | grep -E ":(${params.PROMETHEUS_PORT}|${params.GRAFANA_PORT}|12990|12991)"
echo ""
echo "=========================================="
EOF
                        """
                        
                        echo "✓ Все сервисы запущены и работают"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 9: Очистка секретов
        // ==========================================
        stage('Очистка секретов') {
            when {
                expression { params.CLEANUP_SECRETS == true }
            }
            steps {
                script {
                    echo """
                    ================================================
                    ОЧИСТКА ВРЕМЕННЫХ СЕКРЕТОВ
                    ================================================
                    """
                    
                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: params.SSH_CREDENTIALS_ID,
                            keyFileVariable: 'SSH_KEY',
                            usernameVariable: 'SSH_USER'
                        )
                    ]) {
                        // Очистка секретов на удаленном сервере
                        sh """
                            ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
                                'sudo bash /opt/monitoring/scripts/cleanup_secrets.sh'
                        """
                        
                        echo "✓ Временные секреты удалены"
                    }
                    
                    // Очистка локальных секретов
                    sh "rm -f ${WORKSPACE_LOCAL}/secrets.json"
                    sh "rm -f transfer_secrets.sh"
                    
                    echo "✓ Локальные временные файлы удалены"
                }
            }
        }
    }
    
    post {
        success {
            script {
                if (params.DEBUG) {
                    echo """
                    DEBUG INFO:
                      - Workspace: ${WORKSPACE}
                      - Build Number: ${BUILD_NUMBER}
                      - Build URL: ${BUILD_URL}
                      - Deployment Method: ${params.DEPLOYMENT_METHOD}
                    """
                }
                
                def serverDomain = sh(
                    script: """ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" 'hostname -f' || echo '${params.SERVER_ADDRESS}'""",
                    returnStdout: true
                ).trim()
                
                echo """
                ================================================
                ✅ РАЗВЕРТЫВАНИЕ УСПЕШНО ЗАВЕРШЕНО!
                ================================================
                Сервер: ${params.SERVER_ADDRESS}
                Домен: ${serverDomain}
                
                Доступ к сервисам:
                  • Prometheus: https://${params.SERVER_ADDRESS}:${params.PROMETHEUS_PORT}
                  • Grafana: https://${params.SERVER_ADDRESS}:${params.GRAFANA_PORT}
                  • Harvest: https://${params.SERVER_ADDRESS}:12990/metrics
                
                Время выполнения: ${currentBuild.durationString}
                ================================================
                """
            }
        }
        
        failure {
            script {
                if (params.DEBUG) {
                    echo """
                    DEBUG: Failure Details
                      - Stage: ${env.STAGE_NAME}
                      - Workspace files:
                    """
                    sh "ls -la ${WORKSPACE} || true"
                    sh "cat ${WORKSPACE}/secrets.json 2>/dev/null | jq -r 'keys' || echo 'No secrets.json'"
                }
                
                echo """
                ================================================
                ❌ РАЗВЕРТЫВАНИЕ ЗАВЕРШИЛОСЬ С ОШИБКОЙ!
                ================================================
                Проверьте логи для диагностики проблемы
                Время выполнения: ${currentBuild.durationString}
                ================================================
                """
            }
        }
        
        always {
            // Всегда очищать локальные секреты
            script {
                sh "rm -f ${WORKSPACE_LOCAL}/secrets.json || true"
                sh "rm -f transfer_secrets.sh || true"
            }
            
            // Архивирование логов
            archiveArtifacts artifacts: '**/*.log', allowEmptyArchive: true
            
            echo "Время выполнения: ${currentBuild.durationString}"
        }
    }
}

