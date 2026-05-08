# T-FLEX CAD Student 17 via Distrobox + WineHQ Staging

Установка **T-FLEX CAD Учебная Версия 17** в изолированное Wine-окружение через **Distrobox**.

Цель: не ставить Wine в host-систему, особенно на Fedora Silverblue / Atomic Desktop, а держать T-FLEX в переносимом контейнерном окружении.

---

## Архитектура

```text
Host Linux
├── distrobox
│   └── Ubuntu 24.04 container: tflex-winehq
│       └── WineHQ Staging 10.9
│           └── WINEPREFIX: /mnt/tflex/wineprefixes/tflex-cad-student-17
│               └── T-FLEX CAD Учебная Версия 17
└── ~/.local/share/tflex-distrobox
    ├── input/
    ├── work/
    ├── logs/
    ├── home/
    └── wineprefixes/
````

По умолчанию скрипт делает **чистую установку**:

```text
удаляет старый Distrobox-контейнер
удаляет старый Wine prefix
создаёт новый контейнер
ставит WineHQ Staging 10.9
ставит T-FLEX заново
```

---

## Что делает скрипт

Скрипт:

1. Создаёт Ubuntu 24.04 Distrobox-контейнер.
2. Автоматически добавляет `--nvidia`, если на host есть NVIDIA и Distrobox поддерживает этот флаг.
3. Устанавливает WineHQ Staging `10.9~noble-1`.
4. Фиксирует Wine-пакеты через `apt-mark hold`.
5. Создаёт или переиспользует `WINEPREFIX`.
6. Настраивает Wine DPI и virtual desktop.
7. Настраивает Wine на X11/XWayland backend.
8. Ставит `dotnet48`, `vcrun2019`, `d3dcompiler_47`, `fontsmooth=rgb`.
9. Ставит official T-FLEX prerequisites.
10. Ставит `T-FLEX CAD Учебная Версия 17.msi`.
11. Создаёт launcher `~/.local/bin/tflex-cad-student-17`.
12. Создаёт desktop entry.

---

## Требования на host

Нужны:

```bash
distrobox
podman
```

Для NVIDIA желательно, чтобы на host работало:

```bash
nvidia-smi
```

Проверка:

```bash
distrobox --version
podman --version
nvidia-smi
```

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

## Быстрый старт

```bash
chmod +x install-tflex-student17-distrobox.sh

TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

После установки:

```bash
tflex-cad-student-17
```

---

# Сценарии использования

## 1. Полная чистая установка

Это режим по умолчанию.

```bash
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Что произойдёт:

```text
старый контейнер tflex-winehq будет удалён
старый Wine prefix будет удалён
T-FLEX будет установлен заново
launcher будет создан заново
```

Подходит для первой установки или когда нужно начать с нуля.

---

## 2. Пересоздать контейнер, но сохранить установленный Wine prefix

Этот сценарий нужен, если нужно изменить параметры Distrobox-контейнера, например добавить `--nvidia`, сменить image/home/volume, но не переустанавливать T-FLEX.

```bash
TFLEX_RECREATE_CONTAINER=1 \
TFLEX_RESET_PREFIX=0 \
TFLEX_INSTALL_TFLEX=0 \
TFLEX_USE_NVIDIA=1 \
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Что произойдёт:

```text
старый контейнер будет удалён
новый контейнер будет создан заново
WineHQ Staging 10.9 будет установлен заново
существующий Wine prefix будет сохранён
T-FLEX заново ставиться не будет
DPI / virtual desktop / graphics driver будут применены
launcher будет пересоздан
```

Wine prefix хранится на host:

```text
~/.local/share/tflex-distrobox/wineprefixes/tflex-cad-student-17
```

Поэтому удаление Distrobox-контейнера не удаляет установленный T-FLEX, если `TFLEX_RESET_PREFIX=0`.

---

## 3. Не пересоздавать контейнер, но переустановить Wine prefix

Полезно, если контейнер уже рабочий и NVIDIA проброшена, но T-FLEX надо поставить с нуля.

```bash
TFLEX_RECREATE_CONTAINER=0 \
TFLEX_RESET_PREFIX=1 \
TFLEX_INSTALL_TFLEX=1 \
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Что произойдёт:

```text
контейнер будет сохранён
Wine prefix будет удалён и создан заново
T-FLEX будет установлен заново
```

---

## 4. Сохранить контейнер и prefix, только применить настройки

Диагностический режим. Полезен после ручных изменений или если нужно обновить launcher, DPI, virtual desktop.

```bash
TFLEX_RECREATE_CONTAINER=0 \
TFLEX_RESET_PREFIX=0 \
TFLEX_INSTALL_TFLEX=0 \
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Что произойдёт:

```text
контейнер будет сохранён
Wine prefix будет сохранён
T-FLEX заново ставиться не будет
DPI / virtual desktop / graphics driver будут применены
launcher будет пересоздан
```

---

## 5. Крупный интерфейс для большого монитора

Если интерфейс T-FLEX слишком мелкий:

```bash
TFLEX_DPI=192 \
TFLEX_VIRTUAL_DESKTOP=2560x720 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Это делает интерфейс крупнее.

---

## 6. Более естественный размер для 5120×1440 с GNOME scaling около 133%

```bash
TFLEX_DPI=144 \
TFLEX_VIRTUAL_DESKTOP=3840x1080 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

`3840x1080` примерно соответствует логическому размеру экрана 5120×1440 при 133% scaling.

---

## 7. Сбалансированный режим для Samsung G9 / 32:9

```bash
TFLEX_DPI=168 \
TFLEX_VIRTUAL_DESKTOP=3200x900 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Это хороший компромисс между размером UI и рабочей областью.

---

## 8. Отключить Wine virtual desktop

```bash
TFLEX_VIRTUAL_DESKTOP="" \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Так T-FLEX будет запускаться обычным окном Wine. Если интерфейс слишком мелкий или окна ведут себя странно, лучше вернуть virtual desktop.

---

## 9. Установка без NVIDIA passthrough

Только для диагностики или систем без NVIDIA.

```bash
TFLEX_USE_NVIDIA=0 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Для CAD это не рекомендуется: без GPU passthrough 3D viewport может работать через `llvmpipe`, то есть software rendering.

---

## 10. Принудительно использовать NVIDIA passthrough

```bash
TFLEX_USE_NVIDIA=1 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Это полезно, если auto-detection не сработал, но `distrobox create --help` показывает поддержку `--nvidia`.

---

## 11. Использовать другую версию WineHQ Staging

По умолчанию используется:

```text
10.9~noble-1
```

Пример:

```bash
TFLEX_WINE_VERSION="10.10~noble-1" \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

Для T-FLEX CAD 17 Student рекомендуется оставлять:

```bash
TFLEX_WINE_VERSION="10.9~noble-1"
```

---

# Основные переменные

| Переменная                 |                          Значение по умолчанию | Назначение                                    |
| -------------------------- | ---------------------------------------------: | --------------------------------------------- |
| `TFLEX_CONTAINER_NAME`     |                                 `tflex-winehq` | Имя Distrobox-контейнера                      |
| `TFLEX_IMAGE`              |               `docker.io/library/ubuntu:24.04` | OCI-образ контейнера                          |
| `TFLEX_ROOT`               |               `~/.local/share/tflex-distrobox` | Рабочий каталог на host                       |
| `TFLEX_DBOX_HOME`          |                             `$TFLEX_ROOT/home` | Home-каталог контейнера                       |
| `TFLEX_WINEPREFIX`         | `/mnt/tflex/wineprefixes/tflex-cad-student-17` | Wine prefix внутри контейнера                 |
| `TFLEX_WINE_VERSION`       |                                 `10.9~noble-1` | Версия WineHQ Staging                         |
| `TFLEX_DPI`                |                                          `168` | DPI внутри Wine                               |
| `TFLEX_VIRTUAL_DESKTOP`    |                                     `3200x900` | Размер виртуального Wine desktop              |
| `TFLEX_RECREATE_CONTAINER` |                                            `1` | Пересоздавать контейнер                       |
| `TFLEX_RESET_PREFIX`       |                                            `1` | Удалять старый Wine prefix                    |
| `TFLEX_INSTALL_TFLEX`      |                                            `1` | Запускать установку T-FLEX                    |
| `TFLEX_USE_NVIDIA`         |                                         `auto` | Использовать `--nvidia`, если доступно        |
| `TFLEX_GRAPHICS_DRIVER`    |                                          `x11` | Wine graphics backend                         |
| `TFLEX_INSTALL_LAUNCHER`   |                                            `1` | Создавать host launcher                       |
| `TFLEX_SKIP_WINETRICKS`    |                                            `0` | Пропустить winetricks, только для диагностики |
| `TFLEX_SKIP_GPU_CHECK`     |                                            `0` | Пропустить GPU diagnostics                    |

---

# Диагностика GPU

Проверить GPU внутри контейнера:

```bash
distrobox enter tflex-winehq -- bash -lc '
nvidia-smi || true
glxinfo -B | egrep "direct rendering|OpenGL vendor|OpenGL renderer|OpenGL version" || true
vulkaninfo --summary 2>/dev/null | sed -n "1,120p" || true
'
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

---

# Запуск T-FLEX вручную

```bash
distrobox enter tflex-winehq -- bash -lc '
export WINEPREFIX=/mnt/tflex/wineprefixes/tflex-cad-student-17
cd "$WINEPREFIX/drive_c/Program Files/T-FLEX CAD Учебная Версия 17/Program"
wine TFlexCad.exe
'
```

---

# Где лежит установленный T-FLEX

На host:

```text
~/.local/share/tflex-distrobox/wineprefixes/tflex-cad-student-17
```

Внутри контейнера:

```text
/mnt/tflex/wineprefixes/tflex-cad-student-17
```

T-FLEX executable обычно находится здесь:

```text
/mnt/tflex/wineprefixes/tflex-cad-student-17/drive_c/Program Files/T-FLEX CAD Учебная Версия 17/Program/TFlexCad.exe
```

---

# Логи

Логи установки лежат здесь:

```text
~/.local/share/tflex-distrobox/logs/
```

Посмотреть последний лог:

```bash
ls -lt ~/.local/share/tflex-distrobox/logs/ | head
```

Открыть последний лог:

```bash
less "$(ls -t ~/.local/share/tflex-distrobox/logs/install-*.log | head -1)"
```

---

# Удаление только T-FLEX Distrobox-установки

```bash
distrobox stop tflex-winehq || true
distrobox rm -f tflex-winehq || true

rm -rf ~/.local/share/tflex-distrobox
rm -f ~/.local/bin/tflex-cad-student-17
rm -f ~/.local/share/applications/tflex-cad-student-17.desktop

update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

---

# Полная очистка всех Distrobox-контейнеров

Осторожно: это удалит все Distrobox-контейнеры, не только T-FLEX.

```bash
distrobox stop --all || true
distrobox rm --all --force || true
```

Если `--all` не поддерживается:

```bash
distrobox list --no-color \
  | awk -F'|' 'NR>1 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2!="") print $2}' \
  | while read -r box; do
      echo "Removing distrobox: $box"
      distrobox stop "$box" || true
      distrobox rm -f "$box" || true
    done
```

---

# Примечания

Скрипт не устанавливает HASP/Guardant runtime на host. Для учебной версии сначала это не требуется.

Wine работает через X11/XWayland backend внутри текущей Wayland-сессии. Это **не требует** входа в отдельную X11-сессию GNOME.

Для Fedora Silverblue / Atomic Desktop этот способ предпочтительнее, чем установка Wine через `rpm-ostree`, потому что host-система остаётся чистой, а всё Wine-окружение живёт в Distrobox.

Если в контейнере `glxinfo -B` показывает `llvmpipe`, нужно пересоздать контейнер с NVIDIA passthrough:

```bash
TFLEX_RECREATE_CONTAINER=1 \
TFLEX_RESET_PREFIX=0 \
TFLEX_INSTALL_TFLEX=0 \
TFLEX_USE_NVIDIA=1 \
./install-tflex-student17-distrobox.sh \
  "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
  "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
```

