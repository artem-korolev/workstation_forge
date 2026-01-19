#!/usr/bin/env bash
set -euo pipefail

# Ensure default dotfiles exist (first-time home volume init)
if [ ! -e "$HOME/.bashrc" ] && [ -d /etc/skel ]; then
  cp -an /etc/skel/. "$HOME/" || true
fi

# Persist bash history and append it safely across sessions
BASHRC="$HOME/.bashrc"

# Add once (idempotent)
if ! grep -q "BEGIN devcontainer bash-history" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" <<'EOF'

# BEGIN devcontainer bash-history
# write history after every command
PROMPT_COMMAND='history -a; history -n'
shopt -s histappend
HISTSIZE=10000
HISTFILESIZE=20000
# END devcontainer bash-history
EOF
fi
