# 🚀 Быстрое исправление проблемы с бинарными файлами

## Проблема

Сервисы не запускаются с ошибкой **203/EXEC**, потому что бинарные файлы отсутствуют в `/opt/monitoring/bin/`:

```bash
sudo ls -lah /opt/monitoring/bin/
# total 0 - директория пустая!
```

## Причина

RLM устанавливает RPM пакеты в системные каталоги, а не в `/opt/monitoring/bin/`:

- **Grafana**: `/usr/sbin/grafana-server`
- **Prometheus**: `/usr/bin/prometheus`  
- **Harvest**: `/opt/harvest/bin/harvest`

Systemd units ссылаются на несуществующие файлы в `/opt/monitoring/bin/`.

## Решение

### Вариант 1: Быстрое исправление вручную

```bash
# От пользователя CI10742292-lnx-mon_ci
sudo -u CI10742292-lnx-mon_ci bash

# Создать символические ссылки
mkdir -p /opt/monitoring/bin/
ln -sf /usr/sbin/grafana-server /opt/monitoring/bin/grafana-server
ln -sf /usr/bin/prometheus /opt/monitoring/bin/prometheus
ln -sf /opt/harvest/bin/harvest /opt/monitoring/bin/harvest

# Установить правильные права
chown CI10742292-lnx-mon_ci:CI10742292-lnx-mon_sys /opt/monitoring/bin/*
chmod 750 /opt/monitoring/bin/*

# Проверить
ls -la /opt/monitoring/bin/
```

### Вариант 2: Использование готового скрипта

```bash
# Запустить скрипт быстрого исправления
sudo /opt/monitoring/scripts/quick_fix_binaries.sh
```

### Вариант 3: Полное исправление через Ansible

```bash
# Перезапустить Ansible playbook с обновленной задачей
cd /path/to/secure_deployment/ansible
ansible-playbook -i inventories/production playbooks/deploy_monitoring.yml --tags setup
```

## Проверка исправления

```bash
# Проверить ссылки
sudo ls -la /opt/monitoring/bin/

# Запустить сервисы
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user start grafana'
sudo -u CI10742292-lnx-mon_sys bash -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user status grafana'

# Проверить все сервисы
for service in grafana prometheus harvest; do
  echo "=== $service ==="
  sudo -u CI10742292-lnx-mon_sys bash -c "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user status $service" | grep -E "(Active|Main PID)"
done
```

## Постоянное решение

В Ansible playbook добавлена задача для автоматического создания символических ссылок:

```yaml
- name: "Common | Создание символических ссылок на бинарные файлы"
  file:
    src: "{{ item.src }}"
    dest: "{{ monitoring_dirs.bin }}/{{ item.dest }}"
    state: link
    owner: "{{ monitoring_ci_user }}"
    group: "{{ monitoring_group }}"
    force: yes
  loop:
    - { src: "/usr/sbin/grafana-server", dest: "grafana-server" }
    - { src: "/usr/bin/prometheus", dest: "prometheus" }
    - { src: "/opt/harvest/bin/harvest", dest: "harvest" }
```

Эта задача будет выполняться при каждом развертывании, гарантируя наличие символических ссылок.

## Структура после исправления

```
/opt/monitoring/bin/
├── grafana-server -> /usr/sbin/grafana-server
├── prometheus -> /usr/bin/prometheus  
└── harvest -> /opt/harvest/bin/harvest
```

## Примечания

- Символические ссылки создаются с правильными правами доступа
- Владелец: `CI10742292-lnx-mon_ci` (ТУЗ для деплоя)
- Группа: `CI10742292-lnx-mon_sys` (группа сервиса)
- Права: `750` (владелец: rwx, группа: r-x, другие: ---)

Это решение соответствует корпоративным правилам безопасности и принципу наименьших привилегий.
