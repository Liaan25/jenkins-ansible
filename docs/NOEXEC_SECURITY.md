# Флаг NOEXEC в sudoers - защита от эскалации привилегий

## Что такое NOEXEC?

`NOEXEC` - это флаг безопасности в sudoers, который **предотвращает выполнение дополнительных программ** из команд, запускаемых через sudo.

## Зачем нужен NOEXEC для systemctl status?

### Проблема: Эскалация через пейджер

Команда `systemctl status` использует пейджер (`less` или `more`) для отображения длинного вывода. 

**Уязвимость**: В пейджере `less` можно выполнить команды оболочки:

```bash
# Пользователь выполняет:
sudo systemctl status prometheus

# В less можно нажать:
!sh

# И получить root shell! 🚨
```

### Решение: Добавить NOEXEC

```bash
# БЕЗ NOEXEC (уязвимо):
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status prometheus

# С NOEXEC (безопасно):
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus
```

## Как работает NOEXEC?

`NOEXEC` устанавливает переменную окружения `LD_PRELOAD` или другие механизмы, которые:

1. ✅ Разрешают выполнение самой команды (`systemctl status`)
2. ❌ **Запрещают** запуск дочерних процессов (включая shell из `less`)
3. ✅ Пользователь видит вывод статуса
4. ❌ Но **не может** получить shell через `!sh` в пейджере

## Какие команды требуют NOEXEC?

### ✅ Требуют NOEXEC (используют пейджер):

```bash
# systemctl status - использует less
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus

# journalctl - использует less
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/journalctl --user -u prometheus

# man - использует less
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/man systemctl

# git log - использует less (если git разрешен)
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/git log
```

### ❌ НЕ требуют NOEXEC:

```bash
# systemctl start/stop/restart - не используют пейджер
monitoring_admin ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user start prometheus

# systemctl is-active - короткий вывод (active/inactive)
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user is-active prometheus

# systemctl is-enabled - короткий вывод (enabled/disabled)
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user is-enabled prometheus

# mkdir, chmod, chown - не используют пейджер
monitoring_ci ALL=(ALL:ALL) NOPASSWD: /usr/bin/mkdir -p /opt/monitoring
```

## Пример атаки БЕЗ NOEXEC

### Уязвимый sudoers:

```bash
monitoring_ro ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl --user status prometheus
```

### Атака:

```bash
# 1. Злоумышленник с доступом к monitoring_ro:
monitoring_ro@server$ sudo systemctl --user status prometheus

# 2. systemctl запускает less для отображения вывода
# 3. В less злоумышленник нажимает: !sh
# 4. Получает root shell:

# whoami
root

# id
uid=0(root) gid=0(root) groups=0(root)

# Теперь может делать всё что угодно! 🚨
```

## Пример защиты С NOEXEC

### Безопасный sudoers:

```bash
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus
```

### Попытка атаки:

```bash
# 1. Злоумышленник пытается то же самое:
monitoring_ro@server$ sudo systemctl --user status prometheus

# 2. systemctl запускает less
# 3. В less нажимает: !sh
# 4. Получает ошибку:

!sh
Cannot execute shell

# ИЛИ

sh: Permission denied

# Атака провалилась! ✅
```

## Почему это важно для ReadOnly пользователей?

Пользователь `monitoring_ro` имеет **только права на просмотр**:
- ✅ Может смотреть статус сервисов
- ✅ Может читать логи
- ❌ **НЕ МОЖЕТ** запускать/останавливать сервисы
- ❌ **НЕ МОЖЕТ** изменять файлы

**БЕЗ NOEXEC**: ReadOnly пользователь через `!sh` в `less` получает root и может всё!

**С NOEXEC**: ReadOnly пользователь остается ReadOnly даже при попытке эксплойта.

## Где применено в проекте

### monitoring_ci (ТУЗ - CI/CD)

```bash
monitoring_ci ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status grafana
monitoring_ci ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status harvest
monitoring_ci ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus
monitoring_ci ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status vault-agent-monitoring
```

### monitoring_admin (ПУЗ - Администратор)

```bash
monitoring_admin ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status grafana
monitoring_admin ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status harvest
monitoring_admin ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus
monitoring_admin ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status vault-agent-monitoring
```

### monitoring_ro (ReadOnly - Аудит)

```bash
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status grafana
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status harvest
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status prometheus
monitoring_ro ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl --user status vault-agent-monitoring
```

## Проверка работы NOEXEC

### Тест 1: Без NOEXEC (уязвимо)

```bash
# Временно создать тестовое правило БЕЗ NOEXEC:
echo "testuser ALL=(ALL:ALL) NOPASSWD: /usr/bin/systemctl status sshd" | sudo tee /etc/sudoers.d/test

# Попытка получить shell:
testuser@server$ sudo systemctl status sshd
# В less нажать: !sh
# Результат: получен root shell 🚨

# Удалить тестовое правило:
sudo rm /etc/sudoers.d/test
```

### Тест 2: С NOEXEC (безопасно)

```bash
# Создать тестовое правило С NOEXEC:
echo "testuser ALL=(ALL:ALL) NOPASSWD: NOEXEC: /usr/bin/systemctl status sshd" | sudo tee /etc/sudoers.d/test

# Попытка получить shell:
testuser@server$ sudo systemctl status sshd
# В less нажать: !sh
# Результат: Permission denied ✅

# Удалить тестовое правило:
sudo rm /etc/sudoers.d/test
```

## Ограничения NOEXEC

### Не защищает от всего

NOEXEC **не защищает** от:
- Уязвимостей в самой команде (например, buffer overflow в `systemctl`)
- Записи в файлы через редиректы (если разрешено)
- Чтения конфиденциальных данных (если команда имеет доступ)

### Только предотвращает запуск дочерних процессов

NOEXEC **защищает** только от:
- ✅ Запуска shell через пейджер (`!sh` в `less`)
- ✅ Запуска других программ через интерактивные утилиты
- ✅ Эскалации привилегий через дочерние процессы

## Best Practices

### ✅ Используйте NOEXEC для:
- `systemctl status`
- `journalctl`
- `less`
- `more`
- `man`
- `git log`
- Любых команд с интерактивным выводом

### ❌ НЕ используйте NOEXEC для:
- `systemctl start/stop/restart` (короткий вывод)
- `systemctl is-active/is-enabled` (короткий вывод)
- `mkdir`, `chmod`, `chown` (не используют пейджер)
- `cp`, `mv` (не используют пейджер)

### 🔍 Проверяйте:
```bash
# Всегда проверяйте синтаксис после изменений:
sudo visudo -c -f /etc/sudoers.d/monitoring_ci

# Тестируйте права:
sudo -u monitoring_ro sudo systemctl --user status prometheus
# Попробуйте !sh в less - должно быть запрещено
```

## Документация

- [sudoers man page](https://www.sudo.ws/docs/man/sudoers.man/) - официальная документация
- [NOEXEC flag](https://www.sudo.ws/docs/man/sudoers.man/#noexec) - описание флага

## Резюме

| Команда | NOEXEC? | Причина |
|---------|---------|---------|
| `systemctl status` | ✅ **ДА** | Использует `less`, можно запустить `!sh` |
| `systemctl start` | ❌ Нет | Короткий вывод, не использует пейджер |
| `systemctl is-active` | ❌ Нет | Короткий вывод (active/inactive) |
| `journalctl` | ✅ **ДА** | Использует `less`, можно запустить `!sh` |
| `mkdir` | ❌ Нет | Не использует пейджер |
| `chmod` | ❌ Нет | Не использует пейджер |

---

**Вывод**: `NOEXEC` - критичный флаг безопасности для команд просмотра статуса, который предотвращает эскалацию привилегий через интерактивные пейджеры! 🔒

**Дата**: 19.11.2024  
**Версия**: 1.0  
**Статус**: ✅ Применено во всех sudoers файлах проекта





