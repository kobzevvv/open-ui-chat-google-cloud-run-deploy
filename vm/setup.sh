#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER" || true
  fi
}

install_docker

if ! command -v docker compose >/dev/null 2>&1; then
  # Fallback to docker-compose
  sudo apt-get install -y docker-compose
fi

echo "Docker installed and ready."




