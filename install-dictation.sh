#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dictation"
BASE="$HOME/.local/share/dictation"
CONFIG_DIR="$HOME/.config/dictation"
CONFIG_FILE="$CONFIG_DIR/config.env"
BIN="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

VENV="$BASE/venv"
DAEMON_SERVICE_NAME="dictation-daemon.service"
TRAY_SERVICE_NAME="dictation-tray.service"

DICTATE_MODEL="${DICTATE_MODEL:-medium}"
DICTATE_DEVICE="${DICTATE_DEVICE:-cuda}"
DICTATE_COMPUTE_TYPE="${DICTATE_COMPUTE_TYPE:-float16}"
DICTATE_LANGUAGE="${DICTATE_LANGUAGE:-auto}"
DICTATE_INSERT_MODE="${DICTATE_INSERT_MODE:-clipboard}"
DICTATE_PASTE_DELAY_MS="${DICTATE_PASTE_DELAY_MS:-80}"
DICTATE_RESULT_NOTIFY="${DICTATE_RESULT_NOTIFY:-0}"
DICTATE_BINDING="${DICTATE_BINDING:-<Super>s}"
INSTALL_TRAY="${INSTALL_TRAY:-1}"
INSTALL_ACTIVE_PASTE="${INSTALL_ACTIVE_PASTE:-1}"

# Core commands used by the dictation pipeline.
REQUIRED_CMDS=(python3 systemctl pw-record wl-copy wl-paste notify-send)

# Host packages needed for the tray indicator on Fedora/GNOME.
# AppIndicator support in GNOME still requires the GNOME extension enabled by the user.
TRAY_PACKAGES=(python3-gobject gtk3 libayatana-appindicator-gtk3)
ACTIVE_PASTE_PACKAGES=(ydotool)

log() {
  printf '\n\033[1;32m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

is_silverblue_like() {
  [[ -f /run/ostree-booted ]] || grep -qiE 'silverblue|kinoite|ostree' /etc/os-release 2>/dev/null
}

dedupe_lines() {
  awk '!seen[$0]++'
}

install_fedora_packages() {
  local packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0

  mapfile -t packages < <(printf '%s\n' "${packages[@]}" | dedupe_lines)

  if is_silverblue_like; then
    command -v rpm-ostree >/dev/null 2>&1 || die "This looks like an ostree system, but rpm-ostree was not found"
    log "Installing host packages with rpm-ostree: ${packages[*]}"
    sudo rpm-ostree install "${packages[@]}"
    warn "rpm-ostree package install requires reboot before newly layered packages are available."
    warn "Reboot, then run this installer again."
    exit 0
  else
    command -v dnf >/dev/null 2>&1 || die "dnf not found. This installer currently targets Fedora systems."
    log "Installing host packages with dnf: ${packages[*]}"
    sudo dnf install -y "${packages[@]}"
  fi
}

install_host_packages_if_missing() {
  local missing=()

  for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      case "$cmd" in
        pw-record) missing+=(pipewire-utils) ;;
        wl-copy|wl-paste) missing+=(wl-clipboard) ;;
        notify-send) missing+=(libnotify) ;;
        python3) missing+=(python3) ;;
        systemctl) missing+=(systemd) ;;
        ydotool) missing+=(ydotool) ;;
      esac
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    warn "Missing host packages: ${missing[*]}"
    install_fedora_packages "${missing[@]}"
  fi

  log "Required host commands are available"
}

install_active_paste_packages_if_missing() {
  [[ "$INSTALL_ACTIVE_PASTE" == "1" ]] || return 0

  if command -v ydotool >/dev/null 2>&1; then
    log "ydotool is available"
    return 0
  fi

  warn "Active-window paste requires ydotool. Installing: ${ACTIVE_PASTE_PACKAGES[*]}"
  install_fedora_packages "${ACTIVE_PASTE_PACKAGES[@]}"
}

configure_ydotool_service() {
  [[ "$INSTALL_ACTIVE_PASTE" == "1" ]] || return 0

  if ! command -v ydotool >/dev/null 2>&1; then
    warn "ydotool is not installed; active-window paste will be unavailable"
    return 0
  fi

  log "ydotool is available"

  # Intentionally do NOT start/enable ydotool.service here.
  # ydotoold is a privileged virtual input daemon; starting it should be an
  # explicit manual admin action, not something this installer does by itself.
  if systemctl list-unit-files ydotool.service >/dev/null 2>&1; then
    warn "Active-window paste requires ydotool daemon, but this installer will not start it automatically."
    warn "To enable auto-paste manually, run:"
    warn "  sudo systemctl enable --now ydotool.service"
  else
    warn "ydotool.service was not found. Active paste may not work until ydotoold is running."
  fi

  if getent group input >/dev/null 2>&1; then
    if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
      warn "If ydotool cannot access its socket, you may need to add your user to input manually:"
      warn "  sudo usermod -aG input $USER"
      warn "Then log out/in or reboot."
    fi
  fi
}
python_import_ok() {
  python3 - "$@" <<'PY' >/dev/null 2>&1
import sys
mods = sys.argv[1:]
for m in mods:
    __import__(m)
PY
}

tray_import_ok() {
  python3 - <<'PY' >/dev/null 2>&1
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3
except (ValueError, ImportError):
    gi.require_version("AppIndicator3", "0.1")
    from gi.repository import AppIndicator3
PY
}

install_tray_packages_if_missing() {
  [[ "$INSTALL_TRAY" == "1" ]] || return 0

  if tray_import_ok; then
    log "Tray dependencies are available"
    return 0
  fi

  warn "Tray dependencies are missing. Need PyGObject/GTK/AppIndicator packages."
  install_fedora_packages "${TRAY_PACKAGES[@]}"
}

write_config_file() {
  log "Writing config: $CONFIG_FILE"

  mkdir -p "$CONFIG_DIR"

  if [[ -f "$CONFIG_FILE" ]]; then
    # Preserve existing config unless env vars were explicitly passed to installer.
    # This makes reruns safe while still allowing: DICTATE_MODEL=small ./install-dictation.sh
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" || true
    DICTATE_MODEL="${DICTATE_MODEL:-medium}"
    DICTATE_DEVICE="${DICTATE_DEVICE:-cuda}"
    DICTATE_COMPUTE_TYPE="${DICTATE_COMPUTE_TYPE:-float16}"
    DICTATE_LANGUAGE="${DICTATE_LANGUAGE:-auto}"
    DICTATE_INSERT_MODE="${DICTATE_INSERT_MODE:-clipboard}"
    DICTATE_PASTE_DELAY_MS="${DICTATE_PASTE_DELAY_MS:-80}"
    DICTATE_RESULT_NOTIFY="${DICTATE_RESULT_NOTIFY:-0}"
  fi

  cat > "$CONFIG_FILE" <<EOF
# Local GNOME dictation config.
# Model/device/compute changes require restarting dictation-daemon.service.
# Language and insert mode are read by client/daemon per request.
DICTATE_MODEL=$DICTATE_MODEL
DICTATE_DEVICE=$DICTATE_DEVICE
DICTATE_COMPUTE_TYPE=$DICTATE_COMPUTE_TYPE
DICTATE_LANGUAGE=$DICTATE_LANGUAGE
DICTATE_INSERT_MODE=$DICTATE_INSERT_MODE
DICTATE_PASTE_DELAY_MS=$DICTATE_PASTE_DELAY_MS
DICTATE_RESULT_NOTIFY=$DICTATE_RESULT_NOTIFY
EOF
}

write_daemon_py() {
  log "Writing daemon Python service"

  mkdir -p "$BASE"

  cat > "$BASE/dictation_daemon.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import socket
import traceback
from pathlib import Path

from faster_whisper import WhisperModel

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "dictation", "dictation.sock")
CONFIG_FILE = os.path.expanduser("~/.config/dictation/config.env")

MODEL_NAME = os.environ.get("DICTATE_MODEL", "medium")
DEVICE = os.environ.get("DICTATE_DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("DICTATE_COMPUTE_TYPE", "float16")

Path(os.path.dirname(SOCKET_PATH)).mkdir(parents=True, exist_ok=True)

try:
    os.unlink(SOCKET_PATH)
except FileNotFoundError:
    pass

print(f"Loading model: {MODEL_NAME}, device={DEVICE}, compute_type={COMPUTE_TYPE}", flush=True)

model = WhisperModel(
    MODEL_NAME,
    device=DEVICE,
    compute_type=COMPUTE_TYPE,
)

print("Model loaded", flush=True)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET_PATH)
server.listen(8)

print(f"Listening on {SOCKET_PATH}", flush=True)


def read_config_value(key: str, default: str) -> str:
    value = os.environ.get(key, default)

    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == key:
                    value = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f"Could not read config {CONFIG_FILE}: {e}", flush=True)

    return value


def recv_all(conn):
    chunks = []
    while True:
        chunk = conn.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks)


def transcribe(audio_path: str) -> str:
    print(f"Transcribing: {audio_path}", flush=True)

    lang = read_config_value("DICTATE_LANGUAGE", "auto").strip().lower()
    language = None if lang in ("", "auto", "detect") else lang

    segments, info = model.transcribe(
        audio_path,
        language=language,
        beam_size=5,
        vad_filter=True,
        condition_on_previous_text=False,
    )

    detected = getattr(info, "language", None)
    probability = getattr(info, "language_probability", None)
    print(f"Language: {detected}, probability={probability}", flush=True)

    text = " ".join(segment.text.strip() for segment in segments).strip()
    print(f"Result: [{text}]", flush=True)
    return text


while True:
    conn, _ = server.accept()

    with conn:
        try:
            raw = recv_all(conn)
            request = json.loads(raw.decode("utf-8"))
            audio_path = request["audio_path"]

            text = transcribe(audio_path)

            response = {
                "ok": True,
                "text": text,
            }

        except Exception as e:
            response = {
                "ok": False,
                "error": str(e),
                "traceback": traceback.format_exc(),
            }

        conn.sendall(json.dumps(response, ensure_ascii=False).encode("utf-8"))
PY

  chmod +x "$BASE/dictation_daemon.py"
}

write_daemon_runner() {
  log "Writing daemon runner"

  mkdir -p "$BIN"

  cat > "$BIN/dictation-daemon-run" <<'SHRUN'
#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/.local/share/dictation"
VENV="$BASE/venv"
CONFIG_FILE="$HOME/.config/dictation/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi

# Collect all possible NVIDIA Python wheel library paths.
# Fedora/Python can use lib or lib64 depending on build, so do not assume one.
mapfile -t NVIDIA_LIB_DIRS < <(
  "$VENV/bin/python" - <<'PY'
import glob
import os
import site
import sysconfig

roots = set()

for p in site.getsitepackages():
    roots.add(p)

purelib = sysconfig.get_paths().get("purelib")
platlib = sysconfig.get_paths().get("platlib")

if purelib:
    roots.add(purelib)
if platlib:
    roots.add(platlib)

for root in list(roots):
    for d in glob.glob(os.path.join(root, "nvidia", "*", "lib")):
        print(d)
PY
)

LD_PARTS=()
for d in "${NVIDIA_LIB_DIRS[@]}"; do
  [[ -d "$d" ]] && LD_PARTS+=("$d")
done

if [[ "${#LD_PARTS[@]}" -gt 0 ]]; then
  LD_JOINED="$(IFS=:; echo "${LD_PARTS[*]}")"
  export LD_LIBRARY_PATH="$LD_JOINED:${LD_LIBRARY_PATH:-}"
fi

export DICTATE_MODEL="${DICTATE_MODEL:-medium}"
export DICTATE_DEVICE="${DICTATE_DEVICE:-cuda}"
export DICTATE_COMPUTE_TYPE="${DICTATE_COMPUTE_TYPE:-float16}"
export DICTATE_LANGUAGE="${DICTATE_LANGUAGE:-auto}"

printf 'LD_LIBRARY_PATH=%s\n' "${LD_LIBRARY_PATH:-}"
printf 'DICTATE_MODEL=%s\n' "$DICTATE_MODEL"
printf 'DICTATE_DEVICE=%s\n' "$DICTATE_DEVICE"
printf 'DICTATE_COMPUTE_TYPE=%s\n' "$DICTATE_COMPUTE_TYPE"
printf 'DICTATE_LANGUAGE=%s\n' "$DICTATE_LANGUAGE"

exec "$VENV/bin/python" "$BASE/dictation_daemon.py"
SHRUN

  chmod +x "$BIN/dictation-daemon-run"
}

write_paste_script() {
  log "Writing active-window paste helper"

  mkdir -p "$BIN"

  cat > "$BIN/dictation-paste-active" <<'SHPASTE'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="$HOME/.config/dictation/config.env"
DICTATE_PASTE_DELAY_MS=80
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE" || true
fi

sleep_ms() {
  local ms="${1:-0}"
  if [[ "$ms" =~ ^[0-9]+$ ]] && [[ "$ms" -gt 0 ]]; then
    sleep "$(awk -v ms="$ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
  fi
}

find_socket() {
  if [[ -n "${YDOTOOL_SOCKET:-}" && -S "$YDOTOOL_SOCKET" ]]; then
    printf '%s\n' "$YDOTOOL_SOCKET"
    return 0
  fi

  for s in \
    "$XDG_RUNTIME_DIR/ydotoold/socket" \
    "/run/user/$(id -u)/ydotoold/socket" \
    "/run/ydotoold/socket" \
    "/tmp/.ydotool_socket"; do
    if [[ -S "$s" ]]; then
      printf '%s\n' "$s"
      return 0
    fi
  done

  return 1
}

if ! command -v ydotool >/dev/null 2>&1; then
  echo "ERROR: ydotool not found" >&2
  exit 127
fi

sleep_ms "${DICTATE_PASTE_DELAY_MS:-80}"

if SOCK="$(find_socket)"; then
  export YDOTOOL_SOCKET="$SOCK"
  echo "YDOTOOL_SOCKET=$YDOTOOL_SOCKET"
else
  echo "WARNING: ydotool socket not found; trying ydotool default" >&2
fi

# Press Ctrl+V. Key codes: KEY_LEFTCTRL=29, KEY_V=47.
ydotool key 29:1 47:1 47:0 29:0
SHPASTE

  chmod +x "$BIN/dictation-paste-active"
}

write_transcribe_client() {
  log "Writing transcribe client"

  mkdir -p "$BIN"

  cat > "$BIN/dictate-transcribe" <<'SHCLIENT'
#!/usr/bin/env bash
set -euo pipefail

WAV="${1:?audio wav path required}"

BASE="$HOME/.local/share/dictation"
VENV="$BASE/venv"
SOCKET="${XDG_RUNTIME_DIR:-/tmp}/dictation/dictation.sock"

printf 'WAV=%s\n' "$WAV"
printf 'SOCKET=%s\n' "$SOCKET"

if [[ ! -s "$WAV" ]]; then
  notify-send --app-name="Dictation" --transient "Dictation" "Audio file is empty"
  exit 1
fi

if [[ ! -S "$SOCKET" ]]; then
  notify-send --app-name="Dictation" --transient "Dictation" "Daemon is not running"
  echo "ERROR: daemon socket not found: $SOCKET"
  exit 1
fi

TEXT="$("$VENV/bin/python" - "$SOCKET" "$WAV" <<'PY'
import json
import socket
import sys

socket_path = sys.argv[1]
audio_path = sys.argv[2]

request = json.dumps({"audio_path": audio_path}).encode("utf-8")

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(socket_path)
client.sendall(request)
client.shutdown(socket.SHUT_WR)

chunks = []
while True:
    chunk = client.recv(65536)
    if not chunk:
        break
    chunks.append(chunk)

response = json.loads(b"".join(chunks).decode("utf-8"))

if not response.get("ok"):
    print(response.get("traceback") or response.get("error"), file=sys.stderr)
    sys.exit(1)

print(response.get("text", "").strip())
PY
)"

printf 'TEXT=[%s]\n' "$TEXT"

if [[ -z "$TEXT" ]]; then
  notify-send --app-name="Dictation" --transient "Dictation" "No speech recognized"
  exit 0
fi

printf '%s' "$TEXT" | wl-copy --trim-newline

CONFIG_FILE="$HOME/.config/dictation/config.env"
DICTATE_INSERT_MODE="clipboard"
DICTATE_RESULT_NOTIFY="0"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE" || true
fi

PASTE_STATUS="copied"
if [[ "${DICTATE_INSERT_MODE:-clipboard}" == "paste" ]]; then
  if "$HOME/.local/bin/dictation-paste-active"; then
    PASTE_STATUS="pasted"
  else
    PASTE_STATUS="copied; paste failed"
  fi
fi

SHORT="$(printf '%s' "$TEXT" | cut -c1-160)"
case "${DICTATE_RESULT_NOTIFY:-0}" in
  1|true|yes|on)
    notify-send --app-name="Dictation" --transient "Dictation" "$PASTE_STATUS: $SHORT"
    ;;
esac
SHCLIENT

  chmod +x "$BIN/dictate-transcribe"
}

write_toggle_script() {
  log "Writing toggle recorder script"

  mkdir -p "$BIN"

  cat > "$BIN/dictate-toggle" <<'SHTOGGLE'
#!/usr/bin/env bash
set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/dictation"
PIDFILE="$STATE/record.pid"
WAV="$STATE/input.wav"
LOG="$STATE/dictation.log"

mkdir -p "$STATE"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"
}

is_running() {
  [[ -s "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

if is_running; then
  PID="$(cat "$PIDFILE")"
  log "Stopping recorder pid=$PID"

  kill -INT "$PID" 2>/dev/null || true

  for _ in $(seq 1 50); do
    if ! kill -0 "$PID" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done

  if kill -0 "$PID" 2>/dev/null; then
    log "Recorder did not exit after SIGINT, sending SIGTERM"
    kill -TERM "$PID" 2>/dev/null || true
  fi

  rm -f "$PIDFILE"

  if [[ ! -s "$WAV" ]]; then
    log "ERROR: WAV is missing or empty: $WAV"
    notify-send --app-name="Dictation" --transient "Dictation" "Audio file is empty"
    exit 1
  fi

  ls -lh "$WAV" >> "$LOG" 2>&1 || true

  log "Starting transcribe"
  (
    "$HOME/.local/bin/dictate-transcribe" "$WAV" >> "$LOG" 2>&1
    RC=$?
    log "Transcribe finished rc=$RC"
  ) &

else
  rm -f "$WAV"
  : > "$LOG"

  log "Starting recorder"
  log "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
  log "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
  log "DISPLAY=${DISPLAY:-}"
  log "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}"

  pw-record \
    --rate 16000 \
    --channels 1 \
    --format s16 \
    "$WAV" >> "$LOG" 2>&1 &

  echo "$!" > "$PIDFILE"
  log "Recorder pid=$(cat "$PIDFILE")"
fi
SHTOGGLE

  chmod +x "$BIN/dictate-toggle"
}

write_config_cli() {
  log "Writing config CLI"

  mkdir -p "$BIN"

  cat > "$BIN/dictation-config" <<'SHCFG'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.config/dictation"
CONFIG_FILE="$CONFIG_DIR/config.env"
DAEMON_SERVICE="dictation-daemon.service"
TRAY_SERVICE="dictation-tray.service"

mkdir -p "$CONFIG_DIR"

ensure_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<'EOF'
DICTATE_MODEL=medium
DICTATE_DEVICE=cuda
DICTATE_COMPUTE_TYPE=float16
DICTATE_LANGUAGE=auto
DICTATE_INSERT_MODE=clipboard
DICTATE_PASTE_DELAY_MS=80
DICTATE_RESULT_NOTIFY=0
EOF
  fi
}

get_value() {
  local key="$1" default="${2:-}"
  ensure_config
  awk -F= -v key="$key" -v default="$default" '
    $1 == key { value=$2; found=1 }
    END { print found ? value : default }
  ' "$CONFIG_FILE"
}

set_value() {
  local key="$1" value="$2"
  ensure_config
  local tmp
  tmp="$(mktemp)"
  awk -F= -v key="$key" -v value="$value" '
    BEGIN { done=0 }
    $1 == key { print key "=" value; done=1; next }
    { print }
    END { if (!done) print key "=" value }
  ' "$CONFIG_FILE" > "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}

restart_daemon() {
  systemctl --user daemon-reload
  systemctl --user restart "$DAEMON_SERVICE"
}

notify() {
  notify-send --app-name="Dictation" --transient "Dictation" "$*" 2>/dev/null || true
}

usage() {
  cat <<EOF
Usage:
  dictation-config status
  dictation-config get model|language|device|compute-type|insert-mode|paste-delay|result-notify
  dictation-config set-model small|medium|large-v3|base|tiny
  dictation-config set-language auto|ru|en
  dictation-config set-insert-mode clipboard|paste
  dictation-config set-paste-delay milliseconds
  dictation-config set-result-notify on|off|1|0
  dictation-config set-device cuda|cpu
  dictation-config set-compute-type float16|int8|int8_float16
  dictation-config restart
  dictation-config open-logs
EOF
}

case "${1:-}" in
  status)
    ensure_config
    echo "Config: $CONFIG_FILE"
    cat "$CONFIG_FILE"
    echo
    systemctl --user --no-pager --lines=0 status "$DAEMON_SERVICE" || true
    ;;
  get)
    case "${2:-}" in
      model) get_value DICTATE_MODEL medium ;;
      language) get_value DICTATE_LANGUAGE auto ;;
      insert-mode) get_value DICTATE_INSERT_MODE clipboard ;;
      paste-delay) get_value DICTATE_PASTE_DELAY_MS 80 ;;
      result-notify) get_value DICTATE_RESULT_NOTIFY 0 ;;
      device) get_value DICTATE_DEVICE cuda ;;
      compute-type) get_value DICTATE_COMPUTE_TYPE float16 ;;
      *) usage; exit 2 ;;
    esac
    ;;
  set-model)
    value="${2:?model required}"
    set_value DICTATE_MODEL "$value"
    notify "Switching model to $value…"
    restart_daemon
    notify "Model: $value"
    ;;
  set-language)
    value="${2:?language required}"
    set_value DICTATE_LANGUAGE "$value"
    # No daemon restart needed; daemon reads language from config for every request.
    notify "Language: $value"
    ;;
  set-insert-mode)
    value="${2:?insert mode required}"
    case "$value" in clipboard|paste) ;; *) echo "Invalid insert mode: $value" >&2; exit 2 ;; esac
    set_value DICTATE_INSERT_MODE "$value"
    notify "Insert mode: $value"
    ;;
  set-paste-delay)
    value="${2:?paste delay milliseconds required}"
    case "$value" in (*[!0-9]*|'') echo "Paste delay must be integer milliseconds" >&2; exit 2 ;; esac
    set_value DICTATE_PASTE_DELAY_MS "$value"
    notify "Paste delay: ${value}ms"
    ;;
  set-result-notify)
    value="${2:?result notify value required}"
    case "$value" in
      on|true|yes|1) value="1" ;;
      off|false|no|0) value="0" ;;
      *) echo "Invalid result notify value: $value" >&2; exit 2 ;;
    esac
    set_value DICTATE_RESULT_NOTIFY "$value"
    if [[ "$value" == "1" ]]; then
      notify "Result notifications: on"
    else
      notify "Result notifications: off"
    fi
    ;;
  set-device)
    value="${2:?device required}"
    set_value DICTATE_DEVICE "$value"
    notify "Switching device to $value…"
    restart_daemon
    notify "Device: $value"
    ;;
  set-compute-type)
    value="${2:?compute type required}"
    set_value DICTATE_COMPUTE_TYPE "$value"
    notify "Switching compute type to $value…"
    restart_daemon
    notify "Compute type: $value"
    ;;
  restart)
    restart_daemon
    notify "Daemon restarted"
    ;;
  open-logs)
    if command -v ptyxis >/dev/null 2>&1; then
      ptyxis -- bash -lc "journalctl --user -u $DAEMON_SERVICE -f; exec bash" >/dev/null 2>&1 &
    elif command -v gnome-terminal >/dev/null 2>&1; then
      gnome-terminal -- bash -lc "journalctl --user -u $DAEMON_SERVICE -f; exec bash" >/dev/null 2>&1 &
    else
      journalctl --user -u "$DAEMON_SERVICE" -n 80 --no-pager
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
SHCFG

  chmod +x "$BIN/dictation-config"
}

write_tray_app() {
  [[ "$INSTALL_TRAY" == "1" ]] || return 0

  log "Writing tray app"

  mkdir -p "$BIN"

  cat > "$BIN/dictation-tray" <<'PYTRAY'
#!/usr/bin/env python3
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

Indicator = None
try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as Indicator
except (ValueError, ImportError):
    try:
        gi.require_version("AppIndicator3", "0.1")
        from gi.repository import AppIndicator3 as Indicator
    except (ValueError, ImportError) as e:
        print("Neither AyatanaAppIndicator3 nor AppIndicator3 is available", file=sys.stderr)
        raise e

CONFIG = os.path.expanduser("~/.config/dictation/config.env")
CONFIG_TOOL = os.path.expanduser("~/.local/bin/dictation-config")
DAEMON_SERVICE = "dictation-daemon.service"
TRAY_ID = "local-dictation-tray"

MODELS = ["tiny", "base", "small", "medium", "large-v3"]
LANGUAGES = [("auto", "Auto"), ("ru", "Russian"), ("en", "English")]
DEVICES = [("cuda", "CUDA"), ("cpu", "CPU")]
INSERT_MODES = [("clipboard", "Clipboard only"), ("paste", "Paste into active window")]
RESULT_NOTIFY_MODES = [("0", "Off"), ("1", "On")]


def notify(message: str):
    subprocess.Popen([
        "notify-send", "--app-name=Dictation", "--transient", "Dictation", message
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_async(*args):
    subprocess.Popen(list(args), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_sync(*args) -> str:
    try:
        return subprocess.check_output(list(args), text=True).strip()
    except Exception:
        return ""


def get_config(key: str, default: str) -> str:
    if os.path.exists(CONFIG):
        with open(CONFIG, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == key:
                    return v.strip().strip('"').strip("'")
    return default


def service_active() -> bool:
    return subprocess.call(
        ["systemctl", "--user", "is-active", "--quiet", DAEMON_SERVICE],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ) == 0


class Tray:
    def __init__(self):
        self.indicator = Indicator.Indicator.new(
            TRAY_ID,
            "audio-input-microphone-symbolic",
            Indicator.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(Indicator.IndicatorStatus.ACTIVE)
        self.indicator.set_title("Dictation")
        self.build_menu()
        GLib.timeout_add_seconds(5, self.refresh_status)

    def build_menu(self):
        menu = Gtk.Menu()

        self.status_item = Gtk.MenuItem(label="Dictation: checking…")
        self.status_item.set_sensitive(False)
        menu.append(self.status_item)
        menu.append(Gtk.SeparatorMenuItem())

        model_label = Gtk.MenuItem(label="Model")
        model_label.set_sensitive(False)
        menu.append(model_label)

        current_model = get_config("DICTATE_MODEL", "medium")
        model_group = []
        for model in MODELS:
            item = Gtk.RadioMenuItem.new_with_label(model_group, model)
            model_group = item.get_group()
            item.set_active(model == current_model)
            item.connect("toggled", self.on_model_changed, model)
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        lang_label = Gtk.MenuItem(label="Language")
        lang_label.set_sensitive(False)
        menu.append(lang_label)

        current_lang = get_config("DICTATE_LANGUAGE", "auto")
        lang_group = []
        for value, label in LANGUAGES:
            item = Gtk.RadioMenuItem.new_with_label(lang_group, label)
            lang_group = item.get_group()
            item.set_active(value == current_lang)
            item.connect("toggled", self.on_language_changed, value)
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        device_label = Gtk.MenuItem(label="Device")
        device_label.set_sensitive(False)
        menu.append(device_label)

        current_insert = get_config("DICTATE_INSERT_MODE", "clipboard")
        insert_label = Gtk.MenuItem(label="Insert")
        insert_label.set_sensitive(False)
        menu.append(Gtk.SeparatorMenuItem())
        menu.append(insert_label)

        insert_group = []
        for value, label in INSERT_MODES:
            item = Gtk.RadioMenuItem.new_with_label(insert_group, label)
            insert_group = item.get_group()
            item.set_active(value == current_insert)
            item.connect("toggled", self.on_insert_changed, value)
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        result_notify_label = Gtk.MenuItem(label="Result notification")
        result_notify_label.set_sensitive(False)
        menu.append(result_notify_label)

        current_result_notify = get_config("DICTATE_RESULT_NOTIFY", "0")
        result_notify_group = []
        for value, label in RESULT_NOTIFY_MODES:
            item = Gtk.RadioMenuItem.new_with_label(result_notify_group, label)
            result_notify_group = item.get_group()
            item.set_active(value == current_result_notify)
            item.connect("toggled", self.on_result_notify_changed, value)
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        current_device = get_config("DICTATE_DEVICE", "cuda")
        device_group = []
        for value, label in DEVICES:
            item = Gtk.RadioMenuItem.new_with_label(device_group, label)
            device_group = item.get_group()
            item.set_active(value == current_device)
            item.connect("toggled", self.on_device_changed, value)
            menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())

        restart = Gtk.MenuItem(label="Restart daemon")
        restart.connect("activate", self.on_restart)
        menu.append(restart)

        logs = Gtk.MenuItem(label="Open logs")
        logs.connect("activate", self.on_logs)
        menu.append(logs)

        status = Gtk.MenuItem(label="Show status")
        status.connect("activate", self.on_status)
        menu.append(status)

        menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit tray")
        quit_item.connect("activate", self.on_quit)
        menu.append(quit_item)

        menu.show_all()
        self.indicator.set_menu(menu)
        self.menu = menu
        self.refresh_status()

    def refresh_status(self):
        model = get_config("DICTATE_MODEL", "medium")
        lang = get_config("DICTATE_LANGUAGE", "auto")
        device = get_config("DICTATE_DEVICE", "cuda")
        insert = get_config("DICTATE_INSERT_MODE", "clipboard")
        result_notify = "notify" if get_config("DICTATE_RESULT_NOTIFY", "0") == "1" else "quiet"
        status = "running" if service_active() else "stopped"
        self.status_item.set_label(f"Dictation: {status} | {model} | {lang} | {device} | {insert} | {result_notify}")
        return True

    def on_model_changed(self, item, model):
        if not item.get_active():
            return
        notify(f"Switching model to {model}…")
        run_async(CONFIG_TOOL, "set-model", model)
        GLib.timeout_add_seconds(2, self.refresh_status)

    def on_language_changed(self, item, lang):
        if not item.get_active():
            return
        run_async(CONFIG_TOOL, "set-language", lang)
        self.refresh_status()

    def on_device_changed(self, item, device):
        if not item.get_active():
            return
        notify(f"Switching device to {device}…")
        run_async(CONFIG_TOOL, "set-device", device)
        GLib.timeout_add_seconds(2, self.refresh_status)

    def on_insert_changed(self, item, mode):
        if not item.get_active():
            return
        run_async(CONFIG_TOOL, "set-insert-mode", mode)
        self.refresh_status()

    def on_result_notify_changed(self, item, value):
        if not item.get_active():
            return
        run_async(CONFIG_TOOL, "set-result-notify", value)
        self.refresh_status()

    def on_restart(self, _item):
        notify("Restarting daemon…")
        run_async(CONFIG_TOOL, "restart")
        GLib.timeout_add_seconds(2, self.refresh_status)

    def on_logs(self, _item):
        run_async(CONFIG_TOOL, "open-logs")

    def on_status(self, _item):
        model = get_config("DICTATE_MODEL", "medium")
        lang = get_config("DICTATE_LANGUAGE", "auto")
        device = get_config("DICTATE_DEVICE", "cuda")
        insert = get_config("DICTATE_INSERT_MODE", "clipboard")
        result_notify = "notify" if get_config("DICTATE_RESULT_NOTIFY", "0") == "1" else "quiet"
        status = "running" if service_active() else "stopped"
        notify(f"{status} | model={model} | lang={lang} | device={device} | insert={insert} | result notifications={result_notify}")
        self.refresh_status()

    def on_quit(self, _item):
        Gtk.main_quit()


if __name__ == "__main__":
    Tray()
    Gtk.main()
PYTRAY

  chmod +x "$BIN/dictation-tray"
}

create_venv_and_install_python_deps() {
  log "Creating Python venv and installing Faster-Whisper"

  mkdir -p "$BASE"

  if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
  fi

  "$VENV/bin/pip" install -U pip wheel setuptools

  "$VENV/bin/pip" install -U \
    faster-whisper \
    ctranslate2 \
    nvidia-cublas-cu12 \
    nvidia-cudnn-cu12
}

write_systemd_services() {
  log "Writing systemd user services"

  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_USER_DIR/$DAEMON_SERVICE_NAME" <<UNIT
[Unit]
Description=Local Whisper dictation daemon

[Service]
Type=simple
ExecStart=%h/.local/bin/dictation-daemon-run
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
UNIT

  if [[ "$INSTALL_TRAY" == "1" ]]; then
    cat > "$SYSTEMD_USER_DIR/$TRAY_SERVICE_NAME" <<UNIT
[Unit]
Description=Local dictation tray controller
After=graphical-session.target $DAEMON_SERVICE_NAME
Wants=$DAEMON_SERVICE_NAME

[Service]
Type=simple
ExecStart=%h/.local/bin/dictation-tray
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
UNIT
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now "$DAEMON_SERVICE_NAME"

  if [[ "$INSTALL_TRAY" == "1" ]]; then
    # Make sure systemd user services have the current graphical session environment.
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XAUTHORITY DBUS_SESSION_BUS_ADDRESS || true
    systemctl --user enable --now "$TRAY_SERVICE_NAME"
  fi
}

install_gnome_shortcut() {
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not found; skipping GNOME shortcut"
    return 0
  fi

  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    warn "No graphical session detected; skipping GNOME shortcut"
    return 0
  fi

  log "Installing GNOME shortcut $DICTATE_BINDING"

  local key_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/dictation/"
  local schema="org.gnome.settings-daemon.plugins.media-keys"
  local custom_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$key_path"

  # Preserve existing custom shortcuts and append our path if missing.
  python3 - "$key_path" <<'PY'
import ast
import subprocess
import sys

key_path = sys.argv[1]
schema = "org.gnome.settings-daemon.plugins.media-keys"

try:
    raw = subprocess.check_output(
        ["gsettings", "get", schema, "custom-keybindings"],
        text=True,
    ).strip()
    current = ast.literal_eval(raw)
    if not isinstance(current, list):
        current = []
except Exception:
    current = []

if key_path not in current:
    current.append(key_path)

value = "[" + ", ".join(repr(x) for x in current) + "]"
subprocess.check_call(["gsettings", "set", schema, "custom-keybindings", value])
PY

  gsettings set "$custom_schema" name "Dictation"
  gsettings set "$custom_schema" command "$HOME/.local/bin/dictate-toggle"
  gsettings set "$custom_schema" binding "$DICTATE_BINDING"
}

wait_for_service() {
  log "Checking service"

  systemctl --user --no-pager status "$DAEMON_SERVICE_NAME" || true

  local socket_path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dictation/dictation.sock"

  for _ in $(seq 1 90); do
    if [[ -S "$socket_path" ]]; then
      log "Daemon socket is ready: $socket_path"
      break
    fi
    sleep 1
  done

  if [[ ! -S "$socket_path" ]]; then
    warn "Daemon socket was not found yet: $socket_path"
    warn "The model may still be downloading/loading. Check:"
    warn "  journalctl --user -u $DAEMON_SERVICE_NAME -f"
  fi

  if [[ "$INSTALL_TRAY" == "1" ]]; then
    systemctl --user --no-pager status "$TRAY_SERVICE_NAME" || true
  fi
}

print_summary() {
  cat <<EOF

============================================================
Installed.

Hotkey:
  $DICTATE_BINDING

Usage:
  Press Super+S once  -> start recording
  Press Super+S again -> stop, transcribe, copy to clipboard
  Ctrl+V              -> paste

Tray:
  The tray service is: $TRAY_SERVICE_NAME
  It provides model/language/device selection.
  GNOME needs AppIndicator/KStatusNotifierItem extension enabled.

Config file:
  $CONFIG_FILE

Current config:
$(sed 's/^/  /' "$CONFIG_FILE" 2>/dev/null || true)

Useful commands:
  dictation-config status
  dictation-config set-model small
  dictation-config set-model medium
  dictation-config set-model large-v3
  dictation-config set-language auto
  dictation-config set-language ru
  dictation-config set-language en
  dictation-config set-insert-mode clipboard
  dictation-config set-insert-mode paste
  dictation-config set-paste-delay 120
  dictation-config set-result-notify off
  dictation-config set-result-notify on
  systemctl --user status $DAEMON_SERVICE_NAME
  systemctl --user status $TRAY_SERVICE_NAME
  journalctl --user -u $DAEMON_SERVICE_NAME -f
  journalctl --user -u $TRAY_SERVICE_NAME -f
  cat "\${XDG_RUNTIME_DIR}/dictation/dictation.log"
  wl-paste

Examples:
  DICTATE_MODEL=small  ./install-dictation-with-tray.sh
  DICTATE_MODEL=medium ./install-dictation-with-tray.sh
  DICTATE_LANGUAGE=ru  ./install-dictation-with-tray.sh
  DICTATE_LANGUAGE=auto ./install-dictation-with-tray.sh
  DICTATE_INSERT_MODE=paste ./install-dictation-with-tray.sh
  DICTATE_RESULT_NOTIFY=1 ./install-dictation-with-tray.sh
  INSTALL_TRAY=0 ./install-dictation-with-tray.sh
============================================================

EOF
}

main() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    die "Do not run this installer as root. Run as your normal desktop user."
  fi

  log "Installing local GNOME dictation service with tray controller"

  install_host_packages_if_missing
  install_active_paste_packages_if_missing
  install_tray_packages_if_missing

  mkdir -p "$BASE" "$BIN" "$SYSTEMD_USER_DIR" "$CONFIG_DIR"

  write_config_file
  create_venv_and_install_python_deps
  write_daemon_py
  write_daemon_runner
  write_paste_script
  write_transcribe_client
  write_toggle_script
  write_config_cli
  write_tray_app
  configure_ydotool_service
  write_systemd_services
  install_gnome_shortcut
  wait_for_service
  print_summary
}

main "$@"
