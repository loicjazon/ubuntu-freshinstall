#!/usr/bin/env bash
set -euo pipefail

# URL du dépôt à cloner au premier boot réel de la machine installée.
# Modifiez cette variable si le dépôt est renommé/déplacé.
REPO_URL="git@github.com:loicjazon/ubuntu-freshinstall.git"

INSTALL_DIR="/opt/ubuntu-freshinstall"
LOG_FILE="/var/log/first-boot-provision.log"
SERVICE_NAME="first-boot-provision.service"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== first-boot-provision : démarrage $(date --iso-8601=seconds) ==="

wait_for_network() {
  echo "Attente de la connectivité réseau..."
  local attempt=0
  local max_attempts=60
  until curl -fsS --max-time 5 https://github.com >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "${attempt}" -ge "${max_attempts}" ]; then
      echo "Réseau indisponible après ${max_attempts} tentatives, abandon." >&2
      exit 1
    fi
    sleep 5
  done
  echo "Réseau disponible."
}

clone_repo() {
  if [ -d "${INSTALL_DIR}/.git" ]; then
    echo "Dépôt déjà présent dans ${INSTALL_DIR}, pull des dernières modifications."
    git -C "${INSTALL_DIR}" pull --ff-only
  else
    echo "Clonage de ${REPO_URL} dans ${INSTALL_DIR}..."
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
  fi
}

run_provisioning() {
  echo "Lancement du playbook Ansible..."
  cd "${INSTALL_DIR}/ansible"
  ansible-playbook -i inventory.ini site.yml --connection=local
}

disable_self() {
  echo "Provisioning terminé, désactivation de ${SERVICE_NAME} pour ne pas se relancer au prochain boot."
  systemctl disable "${SERVICE_NAME}" || true
}

wait_for_network
clone_repo
run_provisioning
disable_self

echo "=== first-boot-provision : terminé $(date --iso-8601=seconds) ==="
