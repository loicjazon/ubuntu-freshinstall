#!/usr/bin/env bash
set -euo pipefail

# Installé automatiquement dans /usr/local/bin/freshinstall-update (déjà
# dans le PATH par défaut) : tire les derniers changements du dépôt et
# relance le playbook, sans avoir à taper git pull + ansible-playbook à
# la main. Usage : sudo freshinstall-update

REPO_DIR="/opt/ubuntu-freshinstall"

if [ "$(id -u)" -ne 0 ]; then
  echo "Ce script doit être lancé avec sudo (il installe des paquets et modifie le système)." >&2
  exit 1
fi

echo "=== Mise à jour du dépôt (${REPO_DIR}) ==="
git -C "${REPO_DIR}" pull --ff-only

echo "=== Installation des collections Ansible requises ==="
ansible-galaxy collection install -r "${REPO_DIR}/ansible/requirements.yml"

echo "=== Lancement du playbook ==="
cd "${REPO_DIR}/ansible"
ansible-playbook -i inventory.ini site.yml --connection=local

echo "=== Terminé ==="
