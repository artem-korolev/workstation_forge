# T-FLEX CAD Student 17 via rootless Podman + WineHQ Staging

Установка **T-FLEX CAD Учебная Версия 17** в изолированное Wine-окружение через **rootless Podman**.

Цель: не ставить Wine в host-систему, особенно на Fedora Silverblue / Atomic Desktop, а держать T-FLEX в переносимом контейнере с отдельным Wine prefix.

---

## Архитектура

```text
Host Linux
├── rootless Podman
│   └── image: localhost/tflex-winehq:10.9
│       └── Ubuntu 24.04
│           └── WineHQ Staging 10.9
│               └── WINEPREFIX: /mnt/tflex/wineprefixes/tflex-cad-student-17
│                   └── T-FLEX CAD Учебная Версия 17
└── ~/.local/share/tflex-podman
    ├── input/
    ├── work/
    ├── logs/
    ├── home/
    ├── scripts/
    └── wineprefixes/
````

На host каталог:

```text
~/.local/share/tflex-podman
```

монтируется внутрь контейнера как:

```text
/mnt/tflex
```

Это **отдельный каталог** от Distrobox-версии:

```text
Distrobox: ~/.local/share/tflex-distrobox
Podman:    ~/.local/share/tflex-podman
```

---

## Файлы

Нужны два файла рядом:

```text
Containerfile
tflex-podman.sh
```

Скрипт сам билдит образ и запускает контейнер.

---

## Требования на host

Нужны:

```bash
podman
```

Для NVIDIA желательно:

```bash
nvidia-smi
```

И должен быть настроен NVIDIA Container Toolkit / CDI, чтобы работал параметр:

```bash
--device nvidia.com/gpu=all
```

Проверка:

```bash
podman --version
nvidia-smi
podman run --rm --device nvidia.com/gpu=all docker.io/nvidia/cuda:12.9.0-base-ubuntu24.04 nvidia-smi
```

Если последняя команда не работает, сначала нужно починить NVIDIA passthrough для Podman.

---

## Входные файлы

Скрипт принимает два архива:

```text
Prerequisites_T-FLEX_Linux.zip
TFCAD_ST_17x64_PACK.zip
```

Пример:

```text
~/Downloads/T-Flex CAD/
├── Prerequisites_T-FLEX_Linux.zip
└── TFCAD_ST_17x64_PACK.zip
```

---

# Быстрый старт

## 1. Сделать скрипт исполняемым

```bash
chmod +x tflex-podman.sh
```

## 2. Установить T-FLEX

```bash
./tflex-podman.sh install \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Скрипт:

```text
соберёт Podman image
скопирует архивы в ~/.local/share/tflex-podman/input
создаст чистый Wine prefix
установит Wine dependencies
установит T-FLEX CAD Student 17
создаст launcher
```

## 3. Запустить T-FLEX

```bash
tflex-cad-student-17-podman
```

Или напрямую:

```bash
./tflex-podman.sh run
```

---

# Основные команды

## Собрать образ

```bash
./tflex-podman.sh build
```

## Установить T-FLEX

```bash
./tflex-podman.sh install \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

## Запустить T-FLEX

```bash
./tflex-podman.sh run
```

или:

```bash
tflex-cad-student-17-podman
```

## Проверить GPU внутри контейнера

```bash
./tflex-podman.sh gpu-test
```

Хороший результат:

```text
OpenGL vendor string: NVIDIA Corporation
OpenGL renderer string: NVIDIA GeForce RTX 3090/PCIe/SSE2
```

Плохой результат:

```text
OpenGL renderer string: llvmpipe
```

`llvmpipe` означает software rendering через CPU. Для T-FLEX CAD это плохо: 3D viewport может быть синим, битым или очень медленным.

## Открыть shell внутри контейнера

```bash
./tflex-podman.sh shell
```

## Применить настройки к существующему prefix

```bash
./tflex-podman.sh reconfigure
```

Это не переустанавливает T-FLEX. Команда применяет DPI, virtual desktop, locale/codepage и пересоздаёт launcher.

## Удалить Podman-установку T-FLEX

```bash
./tflex-podman.sh clean
```

Удаляет:

```text
~/.local/share/tflex-podman
~/.local/bin/tflex-cad-student-17-podman
~/.local/share/applications/tflex-cad-student-17-podman.desktop
```

Образ `localhost/tflex-winehq:10.9` эта команда не удаляет.

Удалить образ вручную:

```bash
podman rmi localhost/tflex-winehq:10.9
```

---

# Сценарии использования

## 1. Полная чистая установка

```bash
TFLEX_RESET_PREFIX=1 \
./tflex-podman.sh install \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Что произойдёт:

```text
образ будет собран/обновлён
архивы будут скопированы в ~/.local/share/tflex-podman/input
старый Wine prefix будет удалён
T-FLEX будет установлен заново
launcher будет создан заново
```

---

## 2. Установка с крупным интерфейсом

Для большого монитора, если интерфейс T-FLEX мелкий:

```bash
TFLEX_DPI=192 \
TFLEX_VIRTUAL_DESKTOP=2560x720 \
./tflex-podman.sh install \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

---

## 3. Сбалансированный режим для Samsung G9 / 5120×1440

```bash
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./tflex-podman.sh install \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Это хороший компромисс между размером интерфейса и рабочей областью.

---

## 4. Более естественный размер для GNOME scaling около 133%

```bash
TFLEX_DPI=144 \
TFLEX_VIRTUAL_DESKTOP=3840x1080 \
./tflex-podman.sh install \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

`3840x1080` примерно соответствует логическому размеру 5120×1440 при scaling около 133%.

---

## 5. Изменить DPI / virtual desktop без переустановки T-FLEX

```bash
TFLEX_DPI=192 \
TFLEX_VIRTUAL_DESKTOP=2560x720 \
./tflex-podman.sh reconfigure
```

После этого:

```bash
./tflex-podman.sh run
```

---

## 6. Запустить без virtual desktop

```bash
TFLEX_VIRTUAL_DESKTOP="" \
./tflex-podman.sh reconfigure
```

Потом:

```bash
./tflex-podman.sh run
```

Если окна T-FLEX ведут себя странно или интерфейс слишком мелкий, лучше вернуть virtual desktop:

```bash
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./tflex-podman.sh reconfigure
```

---

## 7. Запуск без NVIDIA passthrough

Только для диагностики или систем без NVIDIA:

```bash
TFLEX_USE_NVIDIA=0 \
./tflex-podman.sh run
```

Для CAD это не рекомендуется.

---

## 8. Принудительно включить NVIDIA passthrough

```bash
TFLEX_USE_NVIDIA=1 \
./tflex-podman.sh run
```

По умолчанию:

```bash
TFLEX_USE_NVIDIA=auto
```

Если `nvidia-smi` есть на host, скрипт добавит:

```bash
--device nvidia.com/gpu=all
```

---

## 9. Использовать тот же prefix, что и Distrobox-версия

По умолчанию Podman-версия использует:

```text
~/.local/share/tflex-podman
```

Distrobox-версия использует:

```text
~/.local/share/tflex-distrobox
```

Чтобы Podman использовал Distrobox workspace:

```bash
TFLEX_ROOT="$HOME/.local/share/tflex-distrobox" \
TFLEX_RESET_PREFIX=0 \
./tflex-podman.sh run
```

Не рекомендуется для первого теста. Лучше держать Distrobox и Podman-версии отдельно, пока Podman-вариант не будет полностью проверен.

---

# Основные переменные

| Переменная              |                          Значение по умолчанию | Назначение                                 |
| ----------------------- | ---------------------------------------------: | ------------------------------------------ |
| `TFLEX_IMAGE`           |                  `localhost/tflex-winehq:10.9` | Имя Podman image                           |
| `TFLEX_CONTAINERFILE`   |                              `./Containerfile` | Путь к Containerfile                       |
| `TFLEX_ROOT`            |                  `~/.local/share/tflex-podman` | Рабочий каталог на host                    |
| `TFLEX_WINEPREFIX`      | `/mnt/tflex/wineprefixes/tflex-cad-student-17` | Wine prefix внутри контейнера              |
| `TFLEX_WINE_VERSION`    |                                 `10.9~noble-1` | Версия WineHQ Staging                      |
| `TFLEX_DPI`             |                                          `168` | DPI внутри Wine                            |
| `TFLEX_VIRTUAL_DESKTOP` |                                     `3200x900` | Размер виртуального Wine desktop           |
| `TFLEX_USE_NVIDIA`      |                                         `auto` | Использовать `--device nvidia.com/gpu=all` |
| `TFLEX_RESET_PREFIX`    |                              `1` для `install` | Удалять старый Wine prefix при установке   |
| `TFLEX_GRAPHICS_DRIVER` |                                          `x11` | Wine graphics backend                      |
| `TFLEX_LANG`            |                                  `ru_RU.UTF-8` | Linux locale внутри контейнера             |
| `TFLEX_LANGUAGE`        |                                     `ru_RU:ru` | Linux language priority                    |

---

# Что монтируется в контейнер

Скрипт запускает контейнер примерно с такими важными опциями:

```bash
--userns=keep-id
--security-opt label=disable
--device nvidia.com/gpu=all
-v "$HOME/.local/share/tflex-podman:/mnt/tflex:rw"
-v /tmp/.X11-unix:/tmp/.X11-unix:ro
-v "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR:rw"
```

Также передаются переменные окружения:

```text
DISPLAY
WAYLAND_DISPLAY
XDG_RUNTIME_DIR
DBUS_SESSION_BUS_ADDRESS
LANG
LC_ALL
LANGUAGE
WINEPREFIX
__GLX_VENDOR_LIBRARY_NAME=nvidia
__NV_PRIME_RENDER_OFFLOAD=1
```

Wine настроен на:

```text
TFLEX_GRAPHICS_DRIVER=x11
```

Это означает X11/XWayland backend внутри текущей GNOME Wayland-сессии. Это **не требует** входа в отдельную X11-сессию.

---

# Где лежат данные

## Host

```text
~/.local/share/tflex-podman/
├── input/
├── work/
├── logs/
├── home/
├── scripts/
└── wineprefixes/
    └── tflex-cad-student-17/
```

## Container

```text
/mnt/tflex/
├── input/
├── work/
├── logs/
├── home/
├── scripts/
└── wineprefixes/
    └── tflex-cad-student-17/
```

---

# Логи

Логи лежат здесь:

```bash
~/.local/share/tflex-podman/logs/
```

Посмотреть последний лог:

```bash
ls -lt ~/.local/share/tflex-podman/logs/ | head
```

Открыть последний лог:

```bash
less "$(ls -t ~/.local/share/tflex-podman/logs/podman-*.log | head -1)"
```

---

# Ручной запуск T-FLEX внутри shell

```bash
./tflex-podman.sh shell
```

Внутри контейнера:

```bash
export WINEPREFIX=/mnt/tflex/wineprefixes/tflex-cad-student-17
cd "$WINEPREFIX/drive_c/Program Files/T-FLEX CAD Учебная Версия 17/Program"
wine TFlexCad.exe
```

---

# Диагностика русской локали

Внутри контейнера:

```bash
locale
```

Ожидаемо:

```text
LANG=ru_RU.UTF-8
LC_ALL=ru_RU.UTF-8
LANGUAGE=ru_RU:ru
```

Проверить Wine codepage:

```bash
wine reg query "HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage" /v ACP
wine reg query "HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage" /v OEMCP
```

Ожидаемо:

```text
ACP    REG_SZ    1251
OEMCP  REG_SZ    866
```

---

# Удаление

Удалить workspace и launcher:

```bash
./tflex-podman.sh clean
```

Удалить образ:

```bash
podman rmi localhost/tflex-winehq:10.9
```

Удалить неиспользуемые образы/слои Podman:

```bash
podman system prune -a
```

Осторожно с volumes:

```bash
podman system prune -a --volumes
```

Эта команда может удалить данные других контейнеров, если они хранятся в Podman volumes.

---

# Примечания

Скрипт не устанавливает HASP/Guardant runtime на host. Для учебной версии сначала это не требуется.

Podman-версия не зависит от Distrobox и использует отдельный workspace:

```text
~/.local/share/tflex-podman
```

Если Distrobox-версия уже работает, её можно оставить как fallback:

```text
~/.local/share/tflex-distrobox
```

После того как Podman-версия будет проверена, Distrobox-версию можно удалить.

---
`TFLEX_DPI=192 TFLEX_VIRTUAL_DESKTOP=2560x720 ./tflex-podman.sh reconfigure`
