#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dictation"
BASE="$HOME/.local/share/dictation"
BIN="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

VENV="$BASE/venv"
SERVICE_NAME="dictation-daemon.service"

DICTATE_MODEL="${DICTATE_MODEL:-medium}"
DICTATE_DEVICE="${DICTATE_DEVICE:-cuda}"
DICTATE_COMPUTE_TYPE="${DICTATE_COMPUTE_TYPE:-float16}"
DICTATE_LANGUAGE="${DICTATE_LANGUAGE:-auto}"
DICTATE_BINDING="${DICTATE_BINDING:-<Super>s}"

REQUIRED_CMDS=(python3 systemctl pw-record wl-copy wl-paste notify-send)

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
      esac
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log "Required host commands already exist"
    return 0
  fi

  # Deduplicate packages.
  mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)

  warn "Missing host packages: ${missing[*]}"

  if is_silverblue_like; then
    if ! command -v rpm-ostree >/dev/null 2>&1; then
      die "This looks like an ostree system, but rpm-ostree was not found"
    fi

    log "Installing missing packages with rpm-ostree"
    sudo rpm-ostree install "${missing[@]}"

    warn "rpm-ostree package install requires reboot before commands are available."
    warn "Reboot, then run this installer again."
    exit 0
  else
    if ! command -v dnf >/dev/null 2>&1; then
      die "dnf not found. This installer currently targets Fedora systems."
    fi

    log "Installing missing packages with dnf"
    sudo dnf install -y "${missing[@]}"
  fi
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

    lang = os.environ.get("DICTATE_LANGUAGE", "auto").strip().lower()
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

echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}"
echo "DICTATE_MODEL=$DICTATE_MODEL"
echo "DICTATE_DEVICE=$DICTATE_DEVICE"
echo "DICTATE_COMPUTE_TYPE=$DICTATE_COMPUTE_TYPE"
echo "DICTATE_LANGUAGE=$DICTATE_LANGUAGE"

exec "$VENV/bin/python" "$BASE/dictation_daemon.py"
SHRUN

  chmod +x "$BIN/dictation-daemon-run"
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

echo "WAV=$WAV"
echo "SOCKET=$SOCKET"

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

echo "TEXT=[$TEXT]"

if [[ -z "$TEXT" ]]; then
  notify-send --app-name="Dictation" --transient "Dictation" "No speech recognized"
  exit 0
fi

printf '%s' "$TEXT" | wl-copy --trim-newline

SHORT="$(printf '%s' "$TEXT" | cut -c1-160)"
notify-send --app-name="Dictation" --transient "Dictation" "$SHORT"
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

write_systemd_service() {
  log "Writing systemd user service"

  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$SYSTEMD_USER_DIR/$SERVICE_NAME" <<UNIT
[Unit]
Description=Local Whisper dictation daemon

[Service]
Type=simple
Environment=DICTATE_MODEL=$DICTATE_MODEL
Environment=DICTATE_DEVICE=$DICTATE_DEVICE
Environment=DICTATE_COMPUTE_TYPE=$DICTATE_COMPUTE_TYPE
Environment=DICTATE_LANGUAGE=$DICTATE_LANGUAGE
ExecStart=%h/.local/bin/dictation-daemon-run
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
UNIT

  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME"
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

  # Use Python to preserve existing custom shortcuts and append our path if missing.
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

  systemctl --user --no-pager status "$SERVICE_NAME" || true

  local socket_path="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dictation/dictation.sock"

  for _ in $(seq 1 60); do
    if [[ -S "$socket_path" ]]; then
      log "Daemon socket is ready: $socket_path"
      return 0
    fi
    sleep 1
  done

  warn "Daemon socket was not found yet: $socket_path"
  warn "The model may still be downloading/loading. Check:"
  warn "  journalctl --user -u $SERVICE_NAME -f"
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

Paste:
  Ctrl+V

Useful commands:
  systemctl --user status $SERVICE_NAME
  journalctl --user -u $SERVICE_NAME -f
  cat "\${XDG_RUNTIME_DIR}/dictation/dictation.log"
  wl-paste

Configuration:
  model:        $DICTATE_MODEL
  device:       $DICTATE_DEVICE
  compute type: $DICTATE_COMPUTE_TYPE
  language:     $DICTATE_LANGUAGE

To change model later, edit:
  $SYSTEMD_USER_DIR/$SERVICE_NAME

Then run:
  systemctl --user daemon-reload
  systemctl --user restart $SERVICE_NAME

Examples:
  DICTATE_MODEL=small  ./install-dictation.sh
  DICTATE_MODEL=medium ./install-dictation.sh
  DICTATE_LANGUAGE=ru  ./install-dictation.sh
  DICTATE_LANGUAGE=auto ./install-dictation.sh
============================================================

EOF
}

main() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    die "Do not run this installer as root. Run as your normal desktop user."
  fi

  log "Installing local GNOME dictation service"

  install_host_packages_if_missing
  mkdir -p "$BASE" "$BIN" "$SYSTEMD_USER_DIR"

  create_venv_and_install_python_deps
  write_daemon_py
  write_daemon_runner
  write_transcribe_client
  write_toggle_script
  write_systemd_service
  install_gnome_shortcut
  wait_for_service
  print_summary
}

main "$@"
