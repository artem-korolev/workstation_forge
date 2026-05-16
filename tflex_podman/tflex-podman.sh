#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# T-FLEX CAD Student 17 via rootless Podman + WineHQ Staging.
#
# Files:
#   ./Containerfile
#   ./tflex-podman.sh
#
# Usage:
#   ./tflex-podman.sh build
#   ./tflex-podman.sh install /path/to/Prerequisites_T-FLEX_Linux.zip /path/to/TFCAD_ST_17x64_PACK.zip
#   ./tflex-podman.sh run
#   ./tflex-podman.sh gpu-test
#   ./tflex-podman.sh shell
#   ./tflex-podman.sh reconfigure
#   ./tflex-podman.sh clean
#
# Important env:
#   TFLEX_IMAGE=localhost/tflex-winehq:10.9
#   TFLEX_ROOT=$HOME/.local/share/tflex-podman
#   TFLEX_PROJECTS_DIR=$HOME/projects/TFLEX
#   TFLEX_PROJECTS_MOUNT=/mnt/projects
#   TFLEX_PROJECTS_DRIVE=p
#   TFLEX_WINEPREFIX=/mnt/tflex/wineprefixes/tflex-cad-student-17
#   TFLEX_DPI=168
#   TFLEX_VIRTUAL_DESKTOP=3200x900
#   TFLEX_USE_NVIDIA=1        # 1 | 0 | auto
#   TFLEX_RESET_PREFIX=1      # for install
#   TFLEX_GRAPHICS_DRIVER=x11
#   TFLEX_LANG=ru_RU.UTF-8
#   TFLEX_LANGUAGE=ru_RU:ru
#   TFLEX_ICON_NAME=tflex-cad-student-17-podman

log() {
  printf '\033[1;34m[HOST]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage:
  tflex-podman.sh build
  tflex-podman.sh install /path/to/Prerequisites_T-FLEX_Linux.zip /path/to/TFCAD_ST_17x64_PACK.zip
  tflex-podman.sh run
  tflex-podman.sh gpu-test
  tflex-podman.sh shell
  tflex-podman.sh reconfigure
  tflex-podman.sh clean

Examples:
  ./tflex-podman.sh build

  TFLEX_DPI=168 TFLEX_VIRTUAL_DESKTOP=3200x900 ./tflex-podman.sh install \
    "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
    "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"

  ./tflex-podman.sh run
EOF
}

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

IMAGE="${TFLEX_IMAGE:-localhost/tflex-winehq:10.9}"
CONTAINERFILE="${TFLEX_CONTAINERFILE:-$SCRIPT_DIR/Containerfile}"
ROOT_DIR="${TFLEX_ROOT:-$HOME/.local/share/tflex-podman}"
PROJECTS_DIR="${TFLEX_PROJECTS_DIR:-$HOME/projects/TFLEX}"
PROJECTS_MOUNT="${TFLEX_PROJECTS_MOUNT:-/mnt/projects}"
PROJECTS_DRIVE="${TFLEX_PROJECTS_DRIVE:-p}"
WINEPREFIX="${TFLEX_WINEPREFIX:-/mnt/tflex/wineprefixes/tflex-cad-student-17}"
WINE_VERSION="${TFLEX_WINE_VERSION:-10.9~noble-1}"
DPI="${TFLEX_DPI:-168}"
VIRTUAL_DESKTOP="${TFLEX_VIRTUAL_DESKTOP:-3200x900}"
USE_NVIDIA="${TFLEX_USE_NVIDIA:-auto}"
RESET_PREFIX="${TFLEX_RESET_PREFIX:-1}"
GRAPHICS_DRIVER="${TFLEX_GRAPHICS_DRIVER:-x11}"
TFLEX_LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
TFLEX_LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"
ICON_NAME="${TFLEX_ICON_NAME:-tflex-cad-student-17-podman}"

ACTION="${1:-}"
[[ -n "$ACTION" ]] || { usage; exit 2; }

need_cmd podman

PROJECTS_DRIVE="${PROJECTS_DRIVE,,}"

if [[ ! "$PROJECTS_DRIVE" =~ ^[a-z]$ ]]; then
  die "TFLEX_PROJECTS_DRIVE must be a single letter, for example: p"
fi

mkdir -p \
  "$ROOT_DIR/input" \
  "$ROOT_DIR/work" \
  "$ROOT_DIR/wineprefixes" \
  "$ROOT_DIR/logs" \
  "$ROOT_DIR/home" \
  "$ROOT_DIR/scripts" \
  "$PROJECTS_DIR"

write_container_script() {
  cat > "$ROOT_DIR/scripts/tflex-container.sh" <<'INNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ACTION="${1:-run}"

LOG_FILE="/mnt/tflex/logs/podman-${ACTION}-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  printf '\033[1;34m[CONTAINER]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
  exit 1
}

export LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
export LC_ALL="${TFLEX_LANG:-ru_RU.UTF-8}"
export LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"

export WINEPREFIX="${TFLEX_WINEPREFIX:-/mnt/tflex/wineprefixes/tflex-cad-student-17}"
export WINEARCH="win64"

DPI="${TFLEX_DPI:-168}"
VIRTUAL_DESKTOP="${TFLEX_VIRTUAL_DESKTOP:-3200x900}"
RESET_PREFIX="${TFLEX_RESET_PREFIX:-0}"
GRAPHICS_DRIVER="${TFLEX_GRAPHICS_DRIVER:-x11}"
PROJECTS_MOUNT="${TFLEX_PROJECTS_MOUNT:-/mnt/projects}"
PROJECTS_DRIVE="${TFLEX_PROJECTS_DRIVE:-p}"

PROJECTS_DRIVE="${PROJECTS_DRIVE,,}"

PREREQ_ZIP="/mnt/tflex/input/Prerequisites_T-FLEX_Linux.zip"
STUDENT_ZIP="/mnt/tflex/input/TFCAD_ST_17x64_PACK.zip"

WORK_DIR="/mnt/tflex/work"
MANAGER_ROOT="$WORK_DIR/t-flex-manager"
STUDENT_EXTRACT_DIR="$WORK_DIR/student-pack"
INSTALLERS_DIR="$WORK_DIR/installers"
MSI_ASCII="$INSTALLERS_DIR/tflex-cad-student-17.msi"

gpu_diagnostics() {
  log "GPU diagnostics"
  nvidia-smi || warn "nvidia-smi is not available inside container"
  glxinfo -B | egrep "direct rendering|OpenGL vendor|OpenGL renderer|OpenGL version" || true
  vulkaninfo --summary 2>/dev/null | sed -n '1,120p' || true

  if glxinfo -B 2>/dev/null | grep -qi 'llvmpipe'; then
    warn "OpenGL renderer is llvmpipe. NVIDIA/OpenGL passthrough is not working correctly."
  fi
}

configure_projects_mount() {
  log "Configuring projects mount: ${PROJECTS_DRIVE^^}: -> $PROJECTS_MOUNT"

  mkdir -p "$PROJECTS_MOUNT"
  mkdir -p "$WINEPREFIX/dosdevices"

  rm -f "$WINEPREFIX/dosdevices/${PROJECTS_DRIVE}:"
  ln -s "$PROJECTS_MOUNT" "$WINEPREFIX/dosdevices/${PROJECTS_DRIVE}:"

  wine reg add "HKCU\\Software\\Wine\\Drives\\${PROJECTS_DRIVE}:" /v Label /t REG_SZ /d projects /f || true
  wine reg add "HKCU\\Software\\Wine\\Drives\\${PROJECTS_DRIVE}:" /v Type /t REG_SZ /d network /f || true

  mkdir -p "$WINEPREFIX/drive_c"
  rm -f "$WINEPREFIX/drive_c/projects"
  ln -s "$PROJECTS_MOUNT" "$WINEPREFIX/drive_c/projects"

  for wine_user_dir in "$WINEPREFIX"/drive_c/users/*; do
    [[ -d "$wine_user_dir" ]] || continue

    mkdir -p "$wine_user_dir/Documents" "$wine_user_dir/Desktop"

    rm -f "$wine_user_dir/Documents/projects"
    rm -f "$wine_user_dir/Desktop/projects"

    ln -s "$PROJECTS_MOUNT" "$wine_user_dir/Documents/projects"
    ln -s "$PROJECTS_MOUNT" "$wine_user_dir/Desktop/projects"
  done
}

configure_wine_prefix() {
  export LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
  export LC_ALL="${TFLEX_LANG:-ru_RU.UTF-8}"
  export LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"

  if [[ "$RESET_PREFIX" == "1" ]]; then
    log "Resetting Wine prefix: $WINEPREFIX"
    wineserver -k >/dev/null 2>&1 || true
    rm -rf "$WINEPREFIX"
  fi

  mkdir -p "$(dirname "$WINEPREFIX")"

  if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
    log "Creating Wine prefix: $WINEPREFIX"
    WINEDLLOVERRIDES="mscoree=" wineboot -u
    wineserver -w || true
  else
    log "Reusing Wine prefix: $WINEPREFIX"
    wineboot -u || true
    wineserver -w || true
  fi

  log "Setting Wine graphics driver: $GRAPHICS_DRIVER"
  wine reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /t REG_SZ /d "$GRAPHICS_DRIVER" /f || true

  log "Configuring Russian locale/codepage registry"
  wine reg add "HKCU\\Control Panel\\International" /v LocaleName /t REG_SZ /d ru-RU /f || true
  wine reg add "HKCU\\Control Panel\\International" /v sLanguage /t REG_SZ /d RUS /f || true
  wine reg add "HKCU\\Control Panel\\International" /v sCountry /t REG_SZ /d Russia /f || true
  wine reg add "HKCU\\Control Panel\\International" /v iCountry /t REG_SZ /d 7 /f || true
  wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage" /v ACP /t REG_SZ /d 1251 /f || true
  wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage" /v OEMCP /t REG_SZ /d 866 /f || true
  wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language" /v Default /t REG_SZ /d 0419 /f || true
  wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language" /v InstallLanguage /t REG_SZ /d 0419 /f || true

  log "Configuring Wine DPI: $DPI"
  wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$DPI" /f
  wine reg add "HKCU\\Control Panel\\Desktop" /v Win8DpiScaling /t REG_DWORD /d 1 /f

  if [[ -n "$VIRTUAL_DESKTOP" ]]; then
    log "Configuring Wine virtual desktop: $VIRTUAL_DESKTOP"
    wine reg add "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /t REG_SZ /d "$VIRTUAL_DESKTOP" /f
  else
    log "Disabling Wine virtual desktop"
    wine reg delete "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /f || true
  fi

  configure_projects_mount
}

extract_archives() {
  [[ -f "$PREREQ_ZIP" ]] || die "Missing prerequisites zip: $PREREQ_ZIP"
  [[ -f "$STUDENT_ZIP" ]] || die "Missing student zip: $STUDENT_ZIP"

  log "Extracting T-FLEX prerequisites"
  rm -rf "$MANAGER_ROOT"
  mkdir -p "$MANAGER_ROOT"
  unzip -oq "$PREREQ_ZIP" -d "$MANAGER_ROOT"

  MANAGER_DIR="$MANAGER_ROOT"
  if [[ ! -f "$MANAGER_DIR/t-flex-install-rus.sh" ]]; then
    FOUND_MANAGER_SCRIPT="$(find "$MANAGER_ROOT" -type f -name 't-flex-install-rus.sh' -print -quit || true)"
    [[ -n "$FOUND_MANAGER_SCRIPT" ]] || die "t-flex-install-rus.sh not found in prerequisites archive"
    MANAGER_DIR="$(dirname "$FOUND_MANAGER_SCRIPT")"
  fi

  COMPONENTS_DIR="$MANAGER_DIR/Components"
  [[ -d "$COMPONENTS_DIR" ]] || die "Components directory not found: $COMPONENTS_DIR"

  log "T-FLEX manager dir: $MANAGER_DIR"

  log "Extracting T-FLEX CAD Student archive"
  rm -rf "$STUDENT_EXTRACT_DIR" "$INSTALLERS_DIR"
  mkdir -p "$STUDENT_EXTRACT_DIR" "$INSTALLERS_DIR"
  unzip -oq "$STUDENT_ZIP" -d "$STUDENT_EXTRACT_DIR"

  mapfile -d '' MSI_FILES < <(find "$STUDENT_EXTRACT_DIR" -type f -iname '*.msi' -print0)
  [[ "${#MSI_FILES[@]}" -gt 0 ]] || die "No .msi file found inside student archive"

  STUDENT_MSI=""
  for f in "${MSI_FILES[@]}"; do
    base="$(basename "$f")"
    case "$base" in
      *Учебная*|*Student*|*student*|*ST*|*st*)
        STUDENT_MSI="$f"
        break
        ;;
    esac
  done

  if [[ -z "$STUDENT_MSI" ]]; then
    STUDENT_MSI="${MSI_FILES[0]}"
    warn "Could not identify student MSI by name. Using first MSI: $STUDENT_MSI"
  fi

  log "Found student MSI: $STUDENT_MSI"
  cp -f "$STUDENT_MSI" "$MSI_ASCII"
  log "Copied MSI to ASCII-safe path: $MSI_ASCII"
}

install_winetricks_deps() {
  log "Preparing local winetricks cache from T-FLEX prerequisites"

  if [[ -d "$MANAGER_DIR/winetricks" ]]; then
    mkdir -p "$HOME/.cache"
    rm -rf "$HOME/.cache/winetricks"
    cp -a "$MANAGER_DIR/winetricks" "$HOME/.cache/winetricks"
  fi

  log "Installing winetricks dependencies"
  winetricks -q dotnet48
  winetricks -q vcrun2019
  winetricks -q d3dcompiler_47
  winetricks -q fontsmooth=rgb

  log "Verifying .NET Framework 4.x registry"
  wine reg query "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release || true
  wine reg query "HKLM\\Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release || true

  log "Applying mscoree native override"
  wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v mscoree /t REG_SZ /d native /f || true
}

run_exe_wait() {
  local exe="$1"
  [[ -f "$exe" ]] || die "Installer not found: $exe"
  log "Running EXE installer: $exe"
  wine start /wait /unix "$exe"
}

run_msi_wait() {
  local msi="$1"
  [[ -f "$msi" ]] || die "MSI not found: $msi"
  local win_msi
  win_msi="$(winepath -w "$msi")"
  log "Running MSI installer: $msi"
  wine msiexec /i "$win_msi"
}

install_tflex() {
  extract_archives
  configure_wine_prefix
  install_winetricks_deps

  log "Installing official T-FLEX components"
  run_exe_wait "$COMPONENTS_DIR/vc_redist.x86.exe"
  run_exe_wait "$COMPONENTS_DIR/vc_redist.x64.exe"
  run_exe_wait "$COMPONENTS_DIR/AccessDatabaseEngine.exe"
  run_msi_wait "$COMPONENTS_DIR/Setup_TSC2.msi"

  if [[ -f "$COMPONENTS_DIR/fake_hasp.reg" ]]; then
    log "Importing fake_hasp.reg"
    wine regedit "$COMPONENTS_DIR/fake_hasp.reg"
  fi

  log "Installing T-FLEX CAD Student 17"
  run_msi_wait "$MSI_ASCII"

  log "Running T-FLEX post-install file/registry steps"
  mkdir -p \
    "$WINEPREFIX/drive_c/Program Files/Common Files" \
    "$WINEPREFIX/drive_c/Program Files (x86)/Common Files" \
    "$WINEPREFIX/drive_c/windows/system32"

  rm -rf "$WINEPREFIX/drive_c/Program Files/Common Files/System"
  rm -rf "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/System"

  if [[ -d "$COMPONENTS_DIR/Program Files/Common Files/System" ]]; then
    cp -a "$COMPONENTS_DIR/Program Files/Common Files/System" \
      "$WINEPREFIX/drive_c/Program Files/Common Files/"
  fi

  if [[ -d "$COMPONENTS_DIR/Program Files (x86)/Common Files/System" ]]; then
    cp -a "$COMPONENTS_DIR/Program Files (x86)/Common Files/System" \
      "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/"
  fi

  if compgen -G "$COMPONENTS_DIR/Windows/System32/*.dll" >/dev/null; then
    cp -a "$COMPONENTS_DIR"/Windows/System32/*.dll \
      "$WINEPREFIX/drive_c/windows/system32/"
  fi

  if [[ -f "$COMPONENTS_DIR/ado-32.reg" ]]; then
    wine regedit "$COMPONENTS_DIR/ado-32.reg"
  fi

  if [[ -f "$COMPONENTS_DIR/ado-64.reg" ]]; then
    if command -v wine64 >/dev/null 2>&1; then
      wine64 regedit "$COMPONENTS_DIR/ado-64.reg" || wine regedit "$COMPONENTS_DIR/ado-64.reg"
    else
      wine regedit "$COMPONENTS_DIR/ado-64.reg"
    fi
  fi

  if [[ -f "$COMPONENTS_DIR/ado-32.reg" ]]; then
    wine regedit "$COMPONENTS_DIR/ado-32.reg"
  fi

  log "Applying T-FLEX CAD 17 registry tweak"
  wine reg add "HKEY_CURRENT_USER\\Software\\Top Systems\\T-FLEX CAD 3D 17\\Rus\\Profiles\\[Current]\\Options" \
    /v "USED_COMMON_3D_IMPORT_MULTIPROCESS" \
    /t REG_DWORD \
    /d 0 \
    /f || true

  find_tflex_exe
  wineserver -k || true
}

find_tflex_exe() {
  TFLEX_EXE="$(find "$WINEPREFIX/drive_c/Program Files" "$WINEPREFIX/drive_c/Program Files (x86)" \
    -type f -iname 'TFlexCad.exe' \
    -path '*T-FLEX*17*Program*' \
    -print -quit 2>/dev/null || true)"

  if [[ -z "$TFLEX_EXE" ]]; then
    die "TFlexCad.exe not found in WINEPREFIX: $WINEPREFIX"
  fi

  log "Found T-FLEX executable: $TFLEX_EXE"
}

run_tflex() {
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
  export __NV_PRIME_RENDER_OFFLOAD=1
  export LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
  export LC_ALL="${TFLEX_LANG:-ru_RU.UTF-8}"
  export LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"

  configure_projects_mount
  find_tflex_exe
  cd "$(dirname "$TFLEX_EXE")"
  exec wine "$TFLEX_EXE" "$@"
}

case "$ACTION" in
  install)
    log "Action: install"
    wine --version
    gpu_diagnostics
    install_tflex
    gpu_diagnostics
    log "Install finished. Log: $LOG_FILE"
    ;;

  run)
    log "Action: run"
    run_tflex "${@:2}"
    ;;

  reconfigure)
    log "Action: reconfigure existing prefix"
    RESET_PREFIX=0
    configure_wine_prefix
    gpu_diagnostics
    wineserver -k || true
    log "Reconfigure finished. Log: $LOG_FILE"
    ;;

  gpu-test)
    log "Action: gpu-test"
    gpu_diagnostics
    ;;

  shell)
    log "Action: shell"
    configure_projects_mount || true
    exec bash
    ;;

  *)
    die "Unknown container action: $ACTION"
    ;;
esac
INNER_EOF

  chmod +x "$ROOT_DIR/scripts/tflex-container.sh"
}

xauth_args() {
  XAUTH_ARGS=()

  if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
    XAUTH_ARGS+=("-e" "XAUTHORITY=/mnt/tflex/.Xauthority")
    XAUTH_ARGS+=("-v" "$XAUTHORITY:/mnt/tflex/.Xauthority:ro")
  elif [[ -f "$HOME/.Xauthority" ]]; then
    XAUTH_ARGS+=("-e" "XAUTHORITY=/mnt/tflex/.Xauthority")
    XAUTH_ARGS+=("-v" "$HOME/.Xauthority:/mnt/tflex/.Xauthority:ro")
  fi
}

podman_run() {
  local container_action="$1"
  shift || true

  write_container_script
  xauth_args

  local args=(
    --rm
    -it
    --userns=keep-id
    --user "$(id -u):$(id -g)"
    --group-add keep-groups
    --security-opt label=disable
    --ipc=host
    -e HOME=/mnt/tflex/home
    -e USER="$USER"
    -e LOGNAME="$USER"
    -e DISPLAY="${DISPLAY:-}"
    -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
    -e XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
    -e DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}"
    -e PULSE_SERVER="${PULSE_SERVER:-}"
    -e LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
    -e LC_ALL="${TFLEX_LANG:-ru_RU.UTF-8}"
    -e LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"
    -e TFLEX_LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
    -e TFLEX_LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"
    -e TFLEX_WINEPREFIX="$WINEPREFIX"
    -e TFLEX_DPI="$DPI"
    -e TFLEX_VIRTUAL_DESKTOP="$VIRTUAL_DESKTOP"
    -e TFLEX_RESET_PREFIX="$RESET_PREFIX"
    -e TFLEX_GRAPHICS_DRIVER="$GRAPHICS_DRIVER"
    -e TFLEX_PROJECTS_MOUNT="$PROJECTS_MOUNT"
    -e TFLEX_PROJECTS_DRIVE="$PROJECTS_DRIVE"
    -e __GLX_VENDOR_LIBRARY_NAME=nvidia
    -e __NV_PRIME_RENDER_OFFLOAD=1
    -e NO_AT_BRIDGE=1
    -w /mnt/tflex/home
    -v "$ROOT_DIR:/mnt/tflex:rw"
    -v "$PROJECTS_DIR:$PROJECTS_MOUNT:rw"
  )

  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" ]]; then
    args+=("-v" "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR:rw")
  fi

  if [[ -d /tmp/.X11-unix ]]; then
    args+=("-v" "/tmp/.X11-unix:/tmp/.X11-unix:ro")
  fi

  args+=("${XAUTH_ARGS[@]}")


  case "$USE_NVIDIA" in
    1)
      args+=(--device nvidia.com/gpu=all)
      ;;
    auto)
      if command -v nvidia-smi >/dev/null 2>&1; then
        args+=(--device nvidia.com/gpu=all)
      fi
      ;;
    0)
      ;;
    *)
      die "Invalid TFLEX_USE_NVIDIA=$USE_NVIDIA. Use 1, 0, or auto."
      ;;
  esac

  podman run "${args[@]}" "$IMAGE" /mnt/tflex/scripts/tflex-container.sh "$container_action" "$@"
}

build_image() {
  [[ -f "$CONTAINERFILE" ]] || die "Containerfile not found: $CONTAINERFILE"

  log "Building image: $IMAGE"
  podman build \
    --build-arg "WINE_VERSION=$WINE_VERSION" \
    -t "$IMAGE" \
    -f "$CONTAINERFILE" \
    "$SCRIPT_DIR"
}

copy_inputs() {
  local prereq_zip="$1"
  local student_zip="$2"

  prereq_zip="$(realpath -e "$prereq_zip")"
  student_zip="$(realpath -e "$student_zip")"

  [[ -f "$prereq_zip" ]] || die "Prerequisites zip not found: $prereq_zip"
  [[ -f "$student_zip" ]] || die "Student zip not found: $student_zip"

  mkdir -p "$ROOT_DIR/input"

  log "Copying input archives"
  cp -f "$prereq_zip" "$ROOT_DIR/input/Prerequisites_T-FLEX_Linux.zip"
  cp -f "$student_zip" "$ROOT_DIR/input/TFCAD_ST_17x64_PACK.zip"
}

find_tflex_icon() {
  find "$ROOT_DIR/work" "$ROOT_DIR/input" \
    -type f \( \
      -iname '95F8_TFlexCad.0.png' -o \
      -iname '6EB2_TFlexCad.0.png' -o \
      -iname '371D_Product.0.png' -o \
      -iname '*TFlexCad*.png' -o \
      -iname '*T-FLEX*.png' -o \
      -iname '*Product*.png' \
    \) 2>/dev/null | head -n 1
}

install_desktop_icon() {
  local icon_src
  icon_src="$(find_tflex_icon || true)"

  if [[ -z "$icon_src" || ! -f "$icon_src" ]]; then
    warn "T-FLEX icon was not found; desktop entry will be created without a custom icon"
    return 1
  fi

  local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
  local icon_target="$icon_dir/${ICON_NAME}.png"

  mkdir -p "$icon_dir"
  cp -f "$icon_src" "$icon_target"

  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

  log "Installed desktop icon: $icon_target"
  return 0
}

create_host_launcher() {
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

  local launcher="$HOME/.local/bin/tflex-cad-student-17-podman"
  local icon_line=""

  if install_desktop_icon; then
    icon_line="Icon=$ICON_NAME"
  fi

  cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec "$SCRIPT_PATH" run "\$@"
EOF

  chmod +x "$launcher"

  local desktop_file="$HOME/.local/share/applications/tflex-cad-student-17-podman.desktop"

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=T-FLEX CAD Student 17 Podman
Comment=T-FLEX CAD Учебная Версия 17 via rootless Podman/WineHQ
Exec=$launcher
${icon_line}
Terminal=false
Categories=Graphics;Engineering;Education;
StartupNotify=true
EOF

  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

  log "Host launcher created: $launcher"
  log "Desktop entry created: $desktop_file"
}

clean_all() {
  log "Removing T-FLEX Podman workspace and launcher"
  log "Projects directory is preserved: $PROJECTS_DIR"

  rm -rf "$ROOT_DIR"
  rm -f "$HOME/.local/bin/tflex-cad-student-17-podman"
  rm -f "$HOME/.local/share/applications/tflex-cad-student-17-podman.desktop"
  rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/${ICON_NAME}.png"

  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
}

case "$ACTION" in
  build)
    build_image
    ;;

  install)
    [[ $# -eq 3 ]] || die "Usage: $0 install /path/to/Prerequisites_T-FLEX_Linux.zip /path/to/TFCAD_ST_17x64_PACK.zip"
    build_image
    copy_inputs "$2" "$3"
    RESET_PREFIX="${TFLEX_RESET_PREFIX:-1}"
    podman_run install
    create_host_launcher
    ;;

  run)
    RESET_PREFIX=0
    podman_run run "${@:2}"
    ;;

  reconfigure)
    RESET_PREFIX=0
    build_image
    podman_run reconfigure
    create_host_launcher
    ;;

  gpu-test)
    build_image
    RESET_PREFIX=0
    podman_run gpu-test
    ;;

  shell)
    build_image
    RESET_PREFIX=0
    podman_run shell
    ;;

  clean)
    clean_all
    ;;

  *)
    usage
    exit 2
    ;;
esac
