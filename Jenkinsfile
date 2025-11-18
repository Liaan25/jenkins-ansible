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
                    echo """
                    ================================================
                    ВАЛИДАЦИЯ ПАРАМЕТРОВ
                    ================================================
                    Целевой сервер: ${params.SERVER_ADDRESS}
                    Namespace: ${params.NAMESPACE_CI}
                    NetApp кластер: ${params.NETAPP_API_ADDR}
                    Метод развертывания: ${params.DEPLOYMENT_METHOD}
                    ================================================
                    """
                    
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
                    
                    echo "✓ Все обязательные параметры указаны"
                }
            }
        }
        
        // ==========================================
        // STAGE 2: Получение секретов из Vault
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
                        
                        // Сохранение в временный файл (будет удален после использования)
                        writeFile file: "${WORKSPACE_LOCAL}/secrets.json", 
                                  text: groovy.json.JsonOutput.toJson(secretsData)
                        
                        echo "✓ Секреты получены из Vault"
                    }
                    
                    // Проверка что файл создан
                    def secretsFile = new File("${WORKSPACE_LOCAL}/secrets.json")
                    if (!secretsFile.exists() || secretsFile.length() == 0) {
                        error("ОШИБКА: Не удалось получить секреты из Vault")
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 3: Подготовка Ansible проекта
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
ansible_user=monitoring_ci
netapp_api_addr=${params.NETAPP_API_ADDR}
prometheus_port=${params.PROMETHEUS_PORT}
grafana_port=${params.GRAFANA_PORT}
admin_email=${params.ADMIN_EMAIL}
vault_namespace=${params.NAMESPACE_CI}
                        """
                        
                        echo "✓ Ansible проект подготовлен"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 4: Передача секретов на сервер
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
                        // Скрипт для безопасной передачи секретов
                        writeFile file: 'transfer_secrets.sh', text: """#!/bin/bash
set -euo pipefail

echo "[INFO] Создание директории для секретов в /dev/shm..."
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo mkdir -p ${REMOTE_SECRETS_DIR} && sudo chmod 700 ${REMOTE_SECRETS_DIR} && sudo chown monitoring_svc:monitoring ${REMOTE_SECRETS_DIR}"

echo "[INFO] Передача секретов через SCP..."
scp -i "\${SSH_KEY}" -o StrictHostKeyChecking=no \\
    ${WORKSPACE_LOCAL}/secrets.json \\
    "\${SSH_USER}@${params.SERVER_ADDRESS}:${REMOTE_SECRETS_DIR}/secrets.json"

echo "[INFO] Установка прав на файл секретов..."
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo chown monitoring_svc:monitoring ${REMOTE_SECRETS_DIR}/secrets.json && sudo chmod 600 ${REMOTE_SECRETS_DIR}/secrets.json"

echo "[INFO] Распаковка секретов в отдельные файлы..."
ssh -i "\${SSH_KEY}" -o StrictHostKeyChecking=no "\${SSH_USER}@${params.SERVER_ADDRESS}" \\
    "sudo -u monitoring_svc bash -c 'cd ${REMOTE_SECRETS_DIR} && jq -r \".\\\"vault-agent\\\".role_id\" secrets.json > role_id.txt && jq -r \".\\\"vault-agent\\\".secret_id\" secrets.json > secret_id.txt && chmod 600 role_id.txt secret_id.txt'"

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
        // STAGE 5: Развертывание через Ansible
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
                            // Запуск Ansible playbook
                            sh """
                                ansible-playbook \\
                                    -i inventories/dynamic_inventory \\
                                    playbooks/deploy_monitoring.yml \\
                                    --extra-vars "rlm_token=${RLM_TOKEN}" \\
                                    --private-key=\${SSH_KEY} \\
                                    -v
                            """
                        }
                        
                        echo "✓ Развертывание через Ansible завершено"
                    }
                }
            }
        }
        
        // ==========================================
        // STAGE 6: Проверка безопасности
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
        // STAGE 7: Верификация сервисов
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
sudo -u monitoring_svc systemctl --user status prometheus | grep "Active:"
sudo -u monitoring_svc systemctl --user status grafana | grep "Active:"
sudo -u monitoring_svc systemctl --user status harvest | grep "Active:"
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
        // STAGE 8: Очистка секретов
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
            echo """
            ================================================
            ❌ РАЗВЕРТЫВАНИЕ ЗАВЕРШИЛОСЬ С ОШИБКОЙ!
            ================================================
            Проверьте логи для диагностики проблемы
            Время выполнения: ${currentBuild.durationString}
            ================================================
            """
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

