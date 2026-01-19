FROM ghcr.io/ansible/community-ansible-dev-tools:latest

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD bash -lc 'true'

# Установить необходимые пакеты

# trunk-ignore(hadolint/DL3041)
RUN dnf -y install \
      ansible-core \
      python3-ansible-lint \
 && dnf -y clean all \
 && rm -rf /var/cache/dnf

WORKDIR /workspace
RUN useradd -m vscode
USER vscode
