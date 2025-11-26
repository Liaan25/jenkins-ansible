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
