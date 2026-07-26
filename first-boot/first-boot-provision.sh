#!/usr/bin/env bash
set -euo pipefail

# URL du dépôt à cloner au premier boot réel de la machine installée.
# HTTPS anonyme (dépôt public) : aucune clé SSH à provisionner sur la
# machine cible. Modifiez cette variable si le dépôt est renommé/déplacé.
REPO_URL="https://github.com/loicjazon/ubuntu-freshinstall.git"

INSTALL_DIR="/opt/ubuntu-freshinstall"
LOG_FILE="/var/log/first-boot-provision.log"
SERVICE_NAME="first-boot-provision.service"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== first-boot-provision : démarrage $(date --iso-8601=seconds) ==="

wait_for_network() {
  echo "Attente de la connectivité réseau..."
  local attempt=0
  local max_attempts=60
  # Utilise le /dev/tcp natif de bash plutôt que curl/wget : aucune
  # dépendance externe requise, alors qu'à ce stade seuls les paquets
  # listés dans autoinstall.yaml (packages:) sont garantis installés.
  until (exec 3<>/dev/tcp/github.com/443) 2>/dev/null; do
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
  cd "${INSTALL_DIR}/ansible"
  echo "Installation des collections Ansible requises..."
  ansible-galaxy collection install -r requirements.yml
  echo "Lancement du playbook Ansible..."
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
