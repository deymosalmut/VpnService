#!/usr/bin/env bash
set -Eeuo pipefail

# Docker install script for Ubuntu 24.04 (run as root)
# Usage:
#   sudo bash install_docker_ubuntu.sh

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: run as root (sudo)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating apt and installing prerequisites..."
apt update -y
apt install -y ca-certificates curl gnupg

echo "==> Preparing keyrings directory..."
install -m 0755 -d /etc/apt/keyrings

echo "==> Importing Docker GPG key..."
rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor --yes \
  | tee /etc/apt/keyrings/docker.gpg >/dev/null
chmod a+r /etc/apt/keyrings/docker.gpg

echo "==> Adding Docker apt repository..."
. /etc/os-release
ARCH="$(dpkg --print-architecture)"
CODENAME="${VERSION_CODENAME}"

cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

echo "==> Installing Docker Engine + Compose plugin..."
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

echo "==> Validating installation..."
docker info >/dev/null
docker compose version

echo "==> Running hello-world test..."
docker run --rm hello-world >/dev/null

echo "OK: Docker installed and working."
echo "Next: run your devmenu Postgres option (P1)."
