# trunk-ignore-all(checkov/CKV_DOCKER_2)
# trunk-ignore-all(checkov/CKV_DOCKER_7)
# trunk-ignore-all(checkov/CKV_DOCKER_3)
# trunk-ignore(hadolint/DL3007)
FROM kalilinux/kali-rolling:latest

# Install nmap and iputils-ping
# trunk-ignore(hadolint/DL3008)
RUN apt-get update && \
    apt-get install -y --no-install-recommends nmap iputils-ping iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set default command to bash
CMD ["/bin/bash"]
