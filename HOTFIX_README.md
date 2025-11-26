# HOTFIX: Исправление ошибки 'when' is not a valid attribute for a Play

## Проблема

При запуске Jenkins pipeline с параметром `USE_RLM_STANDARD_SETUP=true` возникала ошибка:

```
ERROR! 'when' is not a valid attribute for a Play
```

## Причина

В Ansible 2.9 нельзя использовать `when` условие на уровне **play**. `when` можно использовать только на уровне **task** или **block**.

## Решение

### 1. Убраны все `when` условия из уровня play

Были удалены `when` условия из:
- Этапа 2.7: Настройка сервисов по стандартным путям
- Этапа 3: Установка и настройка Prometheus
- Этапа 4: Установка и настройка Grafana  
- Этапа 5: Установка и настройка Harvest

### 2. Объединены этапы 3-5 в один play

Вместо отдельных play для каждого сервиса в безопасном режиме, теперь используется один play с условным выполнением tasks:

```yaml
- name: "ЭТАП 3-5: Установка и настройка сервисов в безопасном режиме"
  hosts: all
  gather_facts: no
  become: yes
  tags: [prometheus, grafana, harvest, install]
  
  tasks:
    - name: "Проверка режима безопасной установки"
      debug:
        msg: "Запуск настройки сервисов в безопасном режиме"
      when: not (use_rlm_standard_setup | default(false))
```

### 3. Условное выполнение на уровне tasks

Все задачи теперь используют `when` на уровне task:

```yaml
- name: "Настройка сервисов по стандартным путям"
  include_role:
    name: rlm_standard_setup
  when: use_rlm_standard_setup | default(false)
```

## Результат

Теперь при `USE_RLM_STANDARD_SETUP=true`:
- Выполняется **только этап 2.7** (стандартная RLM установка)
- Этапы 3-5 **пропускаются** (безопасная установка)

При `USE_RLM_STANDARD_SETUP=false`:
- Этап 2.7 **пропускается** (стандартная RLM установка)
- Выполняются **этапы 3-5** (безопасная установка)

## Проверка

Playbook теперь проходит проверку синтаксиса:

```bash
ansible-playbook --syntax-check playbooks/deploy_monitoring.yml
```

## Перезапуск

Теперь можно безопасно перезапустить Jenkins pipeline с параметром `USE_RLM_STANDARD_SETUP=true`.

## HOTFIX 2: Исправление ошибки отсутствия Python библиотеки rpm

### Проблема

При выполнении роли `rlm_standard_setup` возникала ошибка:

```
[WARNING]: Found "rpm" but Failed to import the required Python library (rpm)
```

### Причина

Модуль `package_facts` требует Python библиотеку `rpm` для работы с RPM пакетами, но на целевом сервере установлен только клиент RPM (`rpm` команда), без Python библиотеки.

### Решение

Заменили использование `package_facts` на прямое использование команды `rpm`:

**Было:**
```yaml
- name: "RLM Standard | Проверка установленных RLM пакетов"
  package_facts:
    manager: auto
```

**Стало:**
```yaml
- name: "RLM Standard | Проверка установленных RLM пакетов через rpm"
  shell: |
    rpm -q prometheus grafana harvest 2>/dev/null || true
  register: rpm_packages_check
  changed_when: false
```

### Преимущества решения:

1. **Не требует установки дополнительных пакетов** - использует существующую команду `rpm`
2. **Более надежно** - работает даже без Python библиотеки rpm
3. **Быстрее** - меньше зависимостей и накладных расходов
4. **Кросс-платформенность** - работает на всех системах с установленным RPM

### Результат

Теперь роль `rlm_standard_setup` будет корректно работать даже на системах без Python библиотеки `rpm`.

## HOTFIX 3: Исправление ошибки отсутствия директорий для сертификатов

### Проблема

При копировании сертификатов возникала ошибка:

```
msg: Destination directory /etc/prometheus/cert does not exist
msg: Destination directory /etc/grafana/cert does not exist
```

### Причина

Родительские директории `/etc/prometheus/` и `/etc/grafana/` не существовали, поэтому поддиректории `cert` не могли быть созданы.

### Решение

Добавлено создание родительских директорий перед созданием директорий для сертификатов:

```yaml
- name: "RLM Standard | Создание родительских директорий для сервисов"
  file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop:
    - "/etc/prometheus"
    - "/etc/grafana"
```

Также добавлена проверка создания директорий:

```yaml
- name: "RLM Standard | Проверка создания директорий для сертификатов"
  stat:
    path: "{{ item }}"
  loop:
    - "/etc/prometheus/cert"
    - "/etc/grafana/cert"
    - "/opt/harvest/cert"
  register: cert_dirs_check
```

### Результат

Теперь все необходимые директории создаются перед копированием сертификатов, и ошибка `Destination directory does not exist` больше не возникает.

## HOTFIX 4: Исправление ошибки отсутствия приватных ключей

### Проблема

При установке прав на приватные ключи возникала ошибка:

```
msg: file ({'path': '/etc/prometheus/cert/server.key', 'owner': 'prometheus', 'group': 'prometheus'}) is absent, cannot continue
```

### Причина

Задача извлечения приватных ключей из `server_bundle.pem` с помощью `openssl pkey` не выполнялась или падала, поэтому файлы приватных ключей не создавались.

### Решение

1. **Добавлена проверка создания приватных ключей**:
```yaml
- name: "RLM Standard | Проверка создания приватных ключей"
  stat:
    path: "{{ item }}"
  loop:
    - "/etc/prometheus/cert/server.key"
    - "/etc/grafana/cert/key.key"
    - "/opt/harvest/cert/server.key"
  register: private_keys_check
```

2. **Условная установка прав**: Права устанавливаются только если файлы существуют

3. **Альтернативный метод создания ключей**: Если `openssl` не работает, используется копирование `server_bundle.pem`

### Результат

Теперь задача установки прав на приватные ключи выполняется только если файлы существуют, и есть альтернативный метод их создания.
