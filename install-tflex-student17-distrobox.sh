#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# T-FLEX CAD Student 17 installer
# Host Linux -> Distrobox Ubuntu 24.04 -> WineHQ Staging 10.9 -> isolated WINEPREFIX
#
# Usage:
#   ./install-tflex-student17-distrobox.sh /path/to/Prerequisites_T-FLEX_Linux.zip /path/to/TFCAD_ST_17x64_PACK.zip
#
# Main scenarios:
#
#   Full clean reinstall:
#     TFLEX_RECREATE_CONTAINER=1 TFLEX_RESET_PREFIX=1 TFLEX_INSTALL_TFLEX=1 ./install...
#
#   Recreate container but keep already installed Wine prefix:
#     TFLEX_RECREATE_CONTAINER=1 TFLEX_RESET_PREFIX=0 TFLEX_INSTALL_TFLEX=0 ./install...
#
#   Reuse container but reinstall T-FLEX prefix:
#     TFLEX_RECREATE_CONTAINER=0 TFLEX_RESET_PREFIX=1 TFLEX_INSTALL_TFLEX=1 ./install...
#
# Optional environment variables:
#   TFLEX_CONTAINER_NAME=tflex-winehq
#   TFLEX_IMAGE=docker.io/library/ubuntu:24.04
#   TFLEX_ROOT=$HOME/.local/share/tflex-distrobox
#   TFLEX_DBOX_HOME=$TFLEX_ROOT/home
#   TFLEX_WINEPREFIX=/mnt/tflex/wineprefixes/tflex-cad-student-17
#   TFLEX_WINE_VERSION=10.9~noble-1
#   TFLEX_DPI=168
#   TFLEX_VIRTUAL_DESKTOP=3200x900
#   TFLEX_RECREATE_CONTAINER=1
#   TFLEX_RESET_PREFIX=1
#   TFLEX_INSTALL_TFLEX=1
#   TFLEX_USE_NVIDIA=auto          # auto | 1 | 0
#   TFLEX_INSTALL_LAUNCHER=1
#   TFLEX_GRAPHICS_DRIVER=x11      # x11 = XWayland inside GNOME Wayland
#   TFLEX_SKIP_WINETRICKS=0
#   TFLEX_SKIP_GPU_CHECK=0
#   TFLEX_LANG=ru_RU.UTF-8
#   TFLEX_LANGUAGE=ru_RU:ru

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
  install-tflex-student17-distrobox.sh /path/to/Prerequisites_T-FLEX_Linux.zip /path/to/TFCAD_ST_17x64_PACK.zip

Examples:

  Full clean install:
    TFLEX_DPI=168 TFLEX_VIRTUAL_DESKTOP=3200x900 ./install-tflex-student17-distrobox.sh \
      "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
      "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"

  Recreate container, keep existing installed Wine prefix:
    TFLEX_RECREATE_CONTAINER=1 \
    TFLEX_RESET_PREFIX=0 \
    TFLEX_INSTALL_TFLEX=0 \
    TFLEX_USE_NVIDIA=1 \
    ./install-tflex-student17-distrobox.sh \
      "$HOME/Downloads/T-Flex CAD/Prerequisites_T-FLEX_Linux.zip" \
      "$HOME/Downloads/T-Flex CAD/TFCAD_ST_17x64_PACK.zip"
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ $# -eq 2 ]] || { usage; exit 2; }

need_cmd distrobox
need_cmd realpath
need_cmd cp
need_cmd mkdir
need_cmd chmod
need_cmd grep
need_cmd awk

PREREQ_ZIP_SRC="$(realpath -e "$1")"
STUDENT_ZIP_SRC="$(realpath -e "$2")"

[[ -f "$PREREQ_ZIP_SRC" ]] || die "Prerequisites zip not found: $PREREQ_ZIP_SRC"
[[ -f "$STUDENT_ZIP_SRC" ]] || die "Student package zip not found: $STUDENT_ZIP_SRC"

CONTAINER_NAME="${TFLEX_CONTAINER_NAME:-tflex-winehq}"
IMAGE="${TFLEX_IMAGE:-docker.io/library/ubuntu:24.04}"
ROOT_DIR="${TFLEX_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/tflex-distrobox}"
DBOX_HOME="${TFLEX_DBOX_HOME:-$ROOT_DIR/home}"
WINEPREFIX_IN_CONTAINER="${TFLEX_WINEPREFIX:-/mnt/tflex/wineprefixes/tflex-cad-student-17}"
WINE_VERSION="${TFLEX_WINE_VERSION:-10.9~noble-1}"
DPI="${TFLEX_DPI:-168}"
VIRTUAL_DESKTOP="${TFLEX_VIRTUAL_DESKTOP:-3200x900}"
RECREATE_CONTAINER="${TFLEX_RECREATE_CONTAINER:-1}"
RESET_PREFIX="${TFLEX_RESET_PREFIX:-1}"
INSTALL_TFLEX="${TFLEX_INSTALL_TFLEX:-1}"
USE_NVIDIA="${TFLEX_USE_NVIDIA:-auto}"
INSTALL_LAUNCHER="${TFLEX_INSTALL_LAUNCHER:-1}"
GRAPHICS_DRIVER="${TFLEX_GRAPHICS_DRIVER:-x11}"
SKIP_WINETRICKS="${TFLEX_SKIP_WINETRICKS:-0}"
SKIP_GPU_CHECK="${TFLEX_SKIP_GPU_CHECK:-0}"
TFLEX_LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
TFLEX_LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"

case "$RECREATE_CONTAINER" in
  0|1) ;;
  *) die "TFLEX_RECREATE_CONTAINER must be 0 or 1" ;;
esac

case "$RESET_PREFIX" in
  0|1) ;;
  *) die "TFLEX_RESET_PREFIX must be 0 or 1" ;;
esac

case "$INSTALL_TFLEX" in
  0|1) ;;
  *) die "TFLEX_INSTALL_TFLEX must be 0 or 1" ;;
esac

case "$INSTALL_LAUNCHER" in
  0|1) ;;
  *) die "TFLEX_INSTALL_LAUNCHER must be 0 or 1" ;;
esac

case "$USE_NVIDIA" in
  auto|0|1) ;;
  *) die "TFLEX_USE_NVIDIA must be auto, 0, or 1" ;;
esac

mkdir -p "$ROOT_DIR"

if [[ "$RECREATE_CONTAINER" == "1" ]]; then
  log "Stopping/removing old container if present: $CONTAINER_NAME"

  if command -v timeout >/dev/null 2>&1; then
    timeout 20s distrobox stop "$CONTAINER_NAME" || true
    timeout 20s distrobox rm -f "$CONTAINER_NAME" || true
  else
    distrobox stop "$CONTAINER_NAME" || true
    distrobox rm -f "$CONTAINER_NAME" || true
  fi

  if command -v podman >/dev/null 2>&1; then
    log "Ensuring old Podman container is removed: $CONTAINER_NAME"
    podman stop --time 5 "$CONTAINER_NAME" || true
    podman rm --force "$CONTAINER_NAME" || true
  fi
fi

if [[ "$RESET_PREFIX" == "1" ]]; then
  log "Removing old Wine prefix and work dirs under: $ROOT_DIR"

  if [[ "$WINEPREFIX_IN_CONTAINER" == /mnt/tflex/* ]]; then
    PREFIX_RELATIVE="${WINEPREFIX_IN_CONTAINER#/mnt/tflex/}"
    rm -rf "$ROOT_DIR/$PREFIX_RELATIVE"
  else
    warn "TFLEX_WINEPREFIX is not under /mnt/tflex; host-side prefix cleanup skipped for: $WINEPREFIX_IN_CONTAINER"
  fi

  rm -rf "$ROOT_DIR/work" "$ROOT_DIR/logs"
else
  log "Preserve mode: existing Wine prefix will not be removed"
fi

mkdir -p \
  "$ROOT_DIR/input" \
  "$ROOT_DIR/work" \
  "$ROOT_DIR/wineprefixes" \
  "$ROOT_DIR/logs" \
  "$DBOX_HOME"

log "Copying input archives into workspace"
cp -f "$PREREQ_ZIP_SRC" "$ROOT_DIR/input/Prerequisites_T-FLEX_Linux.zip"
cp -f "$STUDENT_ZIP_SRC" "$ROOT_DIR/input/TFCAD_ST_17x64_PACK.zip"

NVIDIA_ARGS=()
if [[ "$USE_NVIDIA" == "1" ]]; then
  NVIDIA_ARGS=(--nvidia)
elif [[ "$USE_NVIDIA" == "auto" ]]; then
  if command -v nvidia-smi >/dev/null 2>&1 && distrobox create --help 2>/dev/null | grep -q -- '--nvidia'; then
    NVIDIA_ARGS=(--nvidia)
    log "NVIDIA detected on host; Distrobox will be created with --nvidia"
  else
    warn "NVIDIA auto-detection did not enable --nvidia"
  fi
elif [[ "$USE_NVIDIA" == "0" ]]; then
  log "NVIDIA passthrough disabled by TFLEX_USE_NVIDIA=0"
fi

INNER_SCRIPT="$ROOT_DIR/install-inside-container.sh"

cat > "$INNER_SCRIPT" <<'INNER_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE="/mnt/tflex/logs/install-$(date +%Y%m%d-%H%M%S).log"
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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found inside container: $1"
}

SUDO=()
if [[ "${EUID}" -ne 0 ]]; then
  need_cmd sudo
  SUDO=(sudo)
fi

export DEBIAN_FRONTEND=noninteractive

WINE_VERSION="${TFLEX_WINE_VERSION:-10.9~noble-1}"
WINEPREFIX="${TFLEX_WINEPREFIX:-/mnt/tflex/wineprefixes/tflex-cad-student-17}"
WINEARCH="win64"
DPI="${TFLEX_DPI:-168}"
VIRTUAL_DESKTOP="${TFLEX_VIRTUAL_DESKTOP:-3200x900}"
RESET_PREFIX="${TFLEX_RESET_PREFIX:-1}"
INSTALL_TFLEX="${TFLEX_INSTALL_TFLEX:-1}"
GRAPHICS_DRIVER="${TFLEX_GRAPHICS_DRIVER:-x11}"
SKIP_WINETRICKS="${TFLEX_SKIP_WINETRICKS:-0}"
SKIP_GPU_CHECK="${TFLEX_SKIP_GPU_CHECK:-0}"
TFLEX_LANG="${TFLEX_LANG:-ru_RU.UTF-8}"
TFLEX_LANGUAGE="${TFLEX_LANGUAGE:-ru_RU:ru}"

PREREQ_ZIP="/mnt/tflex/input/Prerequisites_T-FLEX_Linux.zip"
STUDENT_ZIP="/mnt/tflex/input/TFCAD_ST_17x64_PACK.zip"
WORK_DIR="/mnt/tflex/work"
MANAGER_ROOT="$WORK_DIR/t-flex-manager"
STUDENT_EXTRACT_DIR="$WORK_DIR/student-pack"
INSTALLERS_DIR="$WORK_DIR/installers"
MSI_ASCII="$INSTALLERS_DIR/tflex-cad-student-17.msi"

[[ -f "$PREREQ_ZIP" ]] || die "Missing prerequisites zip: $PREREQ_ZIP"
[[ -f "$STUDENT_ZIP" ]] || die "Missing student package zip: $STUDENT_ZIP"

log "Checking container OS"
. /etc/os-release

if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
  die "This installer expects Ubuntu 24.04 inside Distrobox. Current: ${PRETTY_NAME:-unknown}"
fi

log "Installing base packages"
"${SUDO[@]}" dpkg --add-architecture i386 || true
"${SUDO[@]}" apt-get update

"${SUDO[@]}" apt-get install -y \
  ca-certificates \
  wget \
  gnupg \
  unzip \
  p7zip-full \
  cabextract \
  winbind \
  zenity \
  fontconfig \
  fonts-dejavu-core \
  fonts-liberation \
  xdg-utils \
  mesa-utils \
  vulkan-tools \
  locales \
  language-pack-ru

log "Configuring Russian UTF-8 locale"
"${SUDO[@]}" locale-gen ru_RU.UTF-8 || true
"${SUDO[@]}" update-locale LANG=ru_RU.UTF-8 LANGUAGE=ru_RU:ru || true

export LANG="$TFLEX_LANG"
export LC_ALL="$TFLEX_LANG"
export LANGUAGE="$TFLEX_LANGUAGE"

log "Effective locale:"
locale || true

log "Configuring WineHQ repository"
"${SUDO[@]}" mkdir -pm755 /etc/apt/keyrings

if [[ ! -s /etc/apt/keyrings/winehq-archive.key ]]; then
  "${SUDO[@]}" wget -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key
fi

if [[ ! -s /etc/apt/sources.list.d/winehq-noble.sources ]]; then
  "${SUDO[@]}" wget -O /etc/apt/sources.list.d/winehq-noble.sources \
    https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
fi

"${SUDO[@]}" apt-get update

log "Checking WineHQ Staging version availability: $WINE_VERSION"
WINEHQ_STAGING_VERSIONS="$(apt-cache madison winehq-staging || true)"
if ! grep -Fq "$WINE_VERSION" <<< "$WINEHQ_STAGING_VERSIONS"; then
  warn "Available winehq-staging versions:"
  printf '%s\n' "$WINEHQ_STAGING_VERSIONS"
  die "WineHQ Staging version '$WINE_VERSION' is not available."
fi

log "Installing WineHQ Staging $WINE_VERSION"
"${SUDO[@]}" apt-get install -y --allow-downgrades --install-recommends \
  "winehq-staging=${WINE_VERSION}" \
  "wine-staging=${WINE_VERSION}" \
  "wine-staging-amd64=${WINE_VERSION}" \
  "wine-staging-i386=${WINE_VERSION}" \
  winetricks

log "Holding Wine packages at tested version"
"${SUDO[@]}" apt-mark hold \
  winehq-staging \
  wine-staging \
  wine-staging-amd64 \
  wine-staging-i386 || true

need_cmd wine
need_cmd winetricks
need_cmd unzip

log "Wine version:"
wine --version

gpu_diagnostics() {
  log "GPU diagnostics"

  nvidia-smi || warn "nvidia-smi is not available inside container"

  glxinfo -B | egrep "direct rendering|OpenGL vendor|OpenGL renderer|OpenGL version" || true
  vulkaninfo --summary 2>/dev/null | sed -n '1,120p' || true

  if glxinfo -B 2>/dev/null | grep -qi 'llvmpipe'; then
    warn "OpenGL renderer is llvmpipe. NVIDIA/OpenGL passthrough is not working correctly."
    warn "T-FLEX may start, but 3D viewport will likely be broken or very slow."
  fi
}

if [[ "$SKIP_GPU_CHECK" != "1" ]]; then
  gpu_diagnostics
fi

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

export WINEPREFIX
export WINEARCH
export LANG="$TFLEX_LANG"
export LC_ALL="$TFLEX_LANG"
export LANGUAGE="$TFLEX_LANGUAGE"

if [[ "$RESET_PREFIX" == "1" ]]; then
  log "Resetting Wine prefix: $WINEPREFIX"
  wineserver -k >/dev/null 2>&1 || true
  rm -rf "$WINEPREFIX"
fi

mkdir -p "$(dirname "$WINEPREFIX")"

if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
  log "Creating new Wine prefix with locale LANG=$LANG LC_ALL=$LC_ALL LANGUAGE=$LANGUAGE: $WINEPREFIX"
  WINEDLLOVERRIDES="mscoree=" wineboot -u
  wineserver -w || true
else
  log "Reusing existing Wine prefix: $WINEPREFIX"
  wineboot -u || true
  wineserver -w || true
fi

log "Setting Wine graphics driver: $GRAPHICS_DRIVER"
wine reg add "HKCU\\Software\\Wine\\Drivers" /v Graphics /t REG_SZ /d "$GRAPHICS_DRIVER" /f || true

log "Configuring Wine Russian locale/codepage registry"
wine reg add "HKCU\\Control Panel\\International" /v LocaleName /t REG_SZ /d ru-RU /f || true
wine reg add "HKCU\\Control Panel\\International" /v sLanguage /t REG_SZ /d RUS /f || true
wine reg add "HKCU\\Control Panel\\International" /v sCountry /t REG_SZ /d Russia /f || true
wine reg add "HKCU\\Control Panel\\International" /v iCountry /t REG_SZ /d 7 /f || true
wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage" /v ACP /t REG_SZ /d 1251 /f || true
wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\CodePage" /v OEMCP /t REG_SZ /d 866 /f || true
wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language" /v Default /t REG_SZ /d 0419 /f || true
wine reg add "HKLM\\System\\CurrentControlSet\\Control\\Nls\\Language" /v InstallLanguage /t REG_SZ /d 0419 /f || true

log "Configuring DPI: $DPI"
wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$DPI" /f
wine reg add "HKCU\\Control Panel\\Desktop" /v Win8DpiScaling /t REG_DWORD /d 1 /f

if [[ -n "$VIRTUAL_DESKTOP" ]]; then
  log "Configuring Wine virtual desktop: $VIRTUAL_DESKTOP"
  wine reg add "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /t REG_SZ /d "$VIRTUAL_DESKTOP" /f
else
  log "Virtual desktop disabled by empty TFLEX_VIRTUAL_DESKTOP"
  wine reg delete "HKCU\\Software\\Wine\\Explorer\\Desktops" /v Default /f || true
fi

create_runner() {
  local runner="/mnt/tflex/run-tflex-student17-inside.sh"

  cat > "$runner" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

export WINEPREFIX="$WINEPREFIX"
export WINEARCH="win64"

export LANG="$TFLEX_LANG"
export LC_ALL="$TFLEX_LANG"
export LANGUAGE="$TFLEX_LANGUAGE"

# Useful on NVIDIA hosts. Harmless if unsupported.
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __NV_PRIME_RENDER_OFFLOAD=1

TFLEX_EXE="\$(find "\$WINEPREFIX/drive_c/Program Files" "\$WINEPREFIX/drive_c/Program Files (x86)" \\
  -type f -iname 'TFlexCad.exe' \\
  -path '*T-FLEX*17*Program*' \\
  -print -quit 2>/dev/null || true)"

if [[ -z "\$TFLEX_EXE" ]]; then
  echo "TFlexCad.exe not found in WINEPREFIX: \$WINEPREFIX" >&2
  exit 1
fi

cd "\$(dirname "\$TFLEX_EXE")"
exec wine "\$TFLEX_EXE" "\$@"
EOF

  chmod +x "$runner"
  log "Runner inside container: $runner"
}

if [[ "$INSTALL_TFLEX" != "1" ]]; then
  log "TFLEX_INSTALL_TFLEX=$INSTALL_TFLEX: skipping T-FLEX reinstall and preserving existing Wine prefix"

  create_runner

  if [[ "$SKIP_GPU_CHECK" != "1" ]]; then
    gpu_diagnostics
  fi

  wineserver -k || true

  log "Done. Existing prefix was preserved."
  log "Container log: $LOG_FILE"
  exit 0
fi

if [[ "$SKIP_WINETRICKS" != "1" ]]; then
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
else
  warn "Skipping winetricks by TFLEX_SKIP_WINETRICKS=1"
fi

log "Verifying .NET Framework 4.x registry"
wine reg query "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release || warn ".NET x64 Release key not found"
wine reg query "HKLM\\Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release || warn ".NET x86 Release key not found"

log "Applying mscoree native override"
wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides" /v mscoree /t REG_SZ /d native /f || true

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
else
  warn "Missing Components/Program Files/Common Files/System"
fi

if [[ -d "$COMPONENTS_DIR/Program Files (x86)/Common Files/System" ]]; then
  cp -a "$COMPONENTS_DIR/Program Files (x86)/Common Files/System" \
    "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/"
else
  warn "Missing Components/Program Files (x86)/Common Files/System"
fi

if compgen -G "$COMPONENTS_DIR/Windows/System32/*.dll" >/dev/null; then
  cp -a "$COMPONENTS_DIR"/Windows/System32/*.dll \
    "$WINEPREFIX/drive_c/windows/system32/"
else
  warn "No DLL files found in Components/Windows/System32"
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

log "Finding installed TFlexCad.exe"
TFLEX_EXE="$(find "$WINEPREFIX/drive_c/Program Files" "$WINEPREFIX/drive_c/Program Files (x86)" \
  -type f -iname 'TFlexCad.exe' \
  -path '*T-FLEX*17*Program*' \
  -print -quit 2>/dev/null || true)"

if [[ -z "$TFLEX_EXE" ]]; then
  warn "TFlexCad.exe was not found. Installation may have failed or used an unexpected path."
else
  log "Found T-FLEX executable: $TFLEX_EXE"
fi

create_runner

log "Final GPU diagnostics"
if [[ "$SKIP_GPU_CHECK" != "1" ]]; then
  gpu_diagnostics
fi

log "Stopping wineserver"
wineserver -k || true

log "Done."
log "Container log: $LOG_FILE"
INNER_EOF

chmod +x "$INNER_SCRIPT"

container_exists() {
  distrobox list --no-color 2>/dev/null \
    | awk -F'|' 'NR>1 {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' \
    | grep -Fxq "$CONTAINER_NAME"
}

if ! container_exists; then
  CREATE_YES=()
  if distrobox create --help 2>/dev/null | grep -q -- '--yes'; then
    CREATE_YES=(--yes)
  fi

  log "Creating Distrobox container: $CONTAINER_NAME"
  distrobox create \
    "${CREATE_YES[@]}" \
    --name "$CONTAINER_NAME" \
    --image "$IMAGE" \
    --home "$DBOX_HOME" \
    --volume "$ROOT_DIR:/mnt/tflex:rw" \
    "${NVIDIA_ARGS[@]}"
else
  log "Container already exists: $CONTAINER_NAME"
fi

log "Running setup inside container"
distrobox enter "$CONTAINER_NAME" -- env \
  TFLEX_WINE_VERSION="$WINE_VERSION" \
  TFLEX_WINEPREFIX="$WINEPREFIX_IN_CONTAINER" \
  TFLEX_DPI="$DPI" \
  TFLEX_VIRTUAL_DESKTOP="$VIRTUAL_DESKTOP" \
  TFLEX_RESET_PREFIX="$RESET_PREFIX" \
  TFLEX_INSTALL_TFLEX="$INSTALL_TFLEX" \
  TFLEX_GRAPHICS_DRIVER="$GRAPHICS_DRIVER" \
  TFLEX_SKIP_WINETRICKS="$SKIP_WINETRICKS" \
  TFLEX_SKIP_GPU_CHECK="$SKIP_GPU_CHECK" \
  TFLEX_LANG="$TFLEX_LANG" \
  TFLEX_LANGUAGE="$TFLEX_LANGUAGE" \
  LANG="$TFLEX_LANG" \
  LC_ALL="$TFLEX_LANG" \
  LANGUAGE="$TFLEX_LANGUAGE" \
  bash /mnt/tflex/install-inside-container.sh

if [[ "$INSTALL_LAUNCHER" == "1" ]]; then
  log "Creating host launcher"

  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

  HOST_LAUNCHER="$HOME/.local/bin/tflex-cad-student-17"

  cat > "$HOST_LAUNCHER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
exec distrobox enter "$CONTAINER_NAME" -- /mnt/tflex/run-tflex-student17-inside.sh "\$@"
EOF

  chmod +x "$HOST_LAUNCHER"

  DESKTOP_FILE="$HOME/.local/share/applications/tflex-cad-student-17.desktop"

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=T-FLEX CAD Student 17
Comment=T-FLEX CAD Учебная Версия 17 via Distrobox/WineHQ
Exec=$HOST_LAUNCHER
Terminal=false
Categories=Graphics;Engineering;Education;
StartupNotify=true
EOF

  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

  log "Host launcher created: $HOST_LAUNCHER"
  log "Desktop entry created: $DESKTOP_FILE"
fi

log "Installation/setup finished."
log "Run T-FLEX with:"
printf '  %s\n' "$HOME/.local/bin/tflex-cad-student-17"

