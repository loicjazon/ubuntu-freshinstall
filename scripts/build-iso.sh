#!/usr/bin/env bash
set -euo pipefail

# Construit une ISO Ubuntu 26.04 Desktop avec le seed autoinstall injecté,
# prête à démarrer en mode "sans surveillance" (autoinstall ds=nocloud).
#
# Prérequis (Debian/Ubuntu) :
#   sudo apt install xorriso wget

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="${REPO_ROOT}/downloads"
OUTPUT_DIR="${REPO_ROOT}/output"
OUTPUT_ISO="${OUTPUT_DIR}/ubuntu-autoinstall.iso"

# Modifiable si Canonical publie sous un autre nom de fichier ou point de
# version (ex: 26.04.1). Vérifier sur https://releases.ubuntu.com/26.04/ en
# cas d'échec du téléchargement.
ISO_URL="${ISO_URL:-https://releases.ubuntu.com/26.04/ubuntu-26.04-desktop-amd64.iso}"
ISO_FILE="${DOWNLOAD_DIR}/$(basename "${ISO_URL}")"

WORK_DIR="$(mktemp -d /tmp/ubuntu-autoinstall-build.XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

for bin in xorriso wget; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "Dépendance manquante : ${bin}. Installez-la avec 'sudo apt install xorriso wget'." >&2
    exit 1
  fi
done

mkdir -p "${DOWNLOAD_DIR}" "${OUTPUT_DIR}"

if [ ! -f "${ISO_FILE}" ]; then
  echo "Téléchargement de l'ISO Ubuntu 26.04 Desktop..."
  wget -O "${ISO_FILE}" "${ISO_URL}"
else
  echo "ISO déjà présente : ${ISO_FILE}"
fi

echo "Extraction de l'ISO dans ${WORK_DIR}/extracted..."
mkdir -p "${WORK_DIR}/extracted"
xorriso -osirrox on -indev "${ISO_FILE}" -extract / "${WORK_DIR}/extracted"
chmod -R u+w "${WORK_DIR}/extracted"

echo "Injection du seed autoinstall (nocloud)..."
mkdir -p "${WORK_DIR}/extracted/nocloud"
cp "${REPO_ROOT}/first-boot/first-boot-provision.sh" "${WORK_DIR}/extracted/nocloud/"
cp "${REPO_ROOT}/first-boot/first-boot-provision.service" "${WORK_DIR}/extracted/nocloud/"
touch "${WORK_DIR}/extracted/nocloud/meta-data"

AUTOINSTALL_SRC="${REPO_ROOT}/autoinstall/autoinstall.yaml"
AUTOINSTALL_DEST="${WORK_DIR}/extracted/nocloud/user-data"

if [ -n "${BUILD_USERNAME:-}" ] && [ -n "${BUILD_USER_PASSWORD:-}" ]; then
  echo "Variables d'environnement détectées : préremplissage de l'identité utilisateur."
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl est requis pour hasher BUILD_USER_PASSWORD." >&2
    exit 1
  fi
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "Le module Python 'yaml' est requis (sudo apt install python3-yaml)." >&2
    exit 1
  fi
  PASSWORD_HASH="$(openssl passwd -6 "${BUILD_USER_PASSWORD}")"
  HOSTNAME_VALUE="${BUILD_HOSTNAME:-ubuntu-freshinstall}"

  python3 - "${AUTOINSTALL_SRC}" "${AUTOINSTALL_DEST}" "${BUILD_USERNAME}" "${PASSWORD_HASH}" "${HOSTNAME_VALUE}" <<'PYEOF'
import sys
import yaml

src, dest, username, password_hash, hostname = sys.argv[1:6]

with open(src, encoding="utf-8") as handle:
    data = yaml.safe_load(handle)

autoinstall = data["autoinstall"]
autoinstall["identity"] = {
    "hostname": hostname,
    "username": username,
    "password": password_hash,
}
autoinstall["interactive-sections"] = [
    section for section in autoinstall.get("interactive-sections", []) if section != "identity"
]

with open(dest, "w", encoding="utf-8") as handle:
    handle.write("#cloud-config\n")
    yaml.safe_dump(data, handle, default_flow_style=False, sort_keys=False)
PYEOF
else
  echo "Aucune variable d'environnement d'identité fournie : saisie interactive au boot."
  cp "${AUTOINSTALL_SRC}" "${AUTOINSTALL_DEST}"
fi

GRUB_CFG="${WORK_DIR}/extracted/boot/grub/grub.cfg"
if [ -f "${GRUB_CFG}" ]; then
  echo "Ajout du paramètre autoinstall dans ${GRUB_CFG}..."
  sed -i 's#---#autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---#' "${GRUB_CFG}"
else
  echo "Attention : boot/grub/grub.cfg introuvable, vérifiez manuellement l'ISO extraite." >&2
fi

echo "Récupération des options de boot hybride de l'ISO source..."
BOOT_OPTS_FILE="${WORK_DIR}/xorriso_opts.txt"
xorriso -indev "${ISO_FILE}" -report_el_torito as_mkisofs > "${BOOT_OPTS_FILE}" 2>/dev/null || true

echo "Reconstruction de l'ISO -> ${OUTPUT_ISO}..."
# shellcheck disable=SC2046
xorriso -as mkisofs \
  -r -V "UbuntuAutoinstall" -J -joliet-long \
  $(grep -E '^-(b|c|e|no-emul-boot|boot-load-size|boot-info-table|eltorito-alt-boot|isohybrid|-grub2)' "${BOOT_OPTS_FILE}" 2>/dev/null || true) \
  -o "${OUTPUT_ISO}" \
  "${WORK_DIR}/extracted"

echo "ISO générée : ${OUTPUT_ISO}"
echo "Testez-la avec 'make test-vm' avant de l'écrire sur une clé USB réelle."
