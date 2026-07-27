# ubuntu-freshinstall

Automatisation complète de la préparation d'un poste de dev sous **Ubuntu
26.04 LTS "Resolute Raccoon"** : de l'ISO d'installation jusqu'à une machine
opérationnelle (paquets, logiciels desktop, dotfiles), sans aucune étape
manuelle après le premier boot.

## Ce que fait le projet

1. **`autoinstall/autoinstall.yaml`** : un seed [autoinstall](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
   (format curtin-subiquity `version: 1`) qui pilote l'installeur Ubuntu de
   façon non interactive : locale française, clavier AZERTY, partitionnement
   LVM sur disque entier, réseau en DHCP, SSH sans mot de passe root. Il
   installe aussi un service systemd qui se déclenchera au tout premier
   démarrage réel de la machine (pas pendant l'installation elle-même, où le
   réseau/environnement n'est pas assez fiable).
2. **`first-boot/first-boot-provision.sh`** : au premier boot, ce script
   attend la connexion réseau, clone ce dépôt, puis lance le playbook
   Ansible en local. Il se désactive lui-même une fois terminé.
3. **`ansible/`** : le playbook qui installe tout le reste (paquets apt,
   .deb téléchargés directement, snaps, applications en tarball, dotfiles
   optionnels).

## Prérequis pour builder l'ISO

- Une machine Linux (ou VM) avec `xorriso` et `wget` installés :
  ```bash
  sudo apt install xorriso wget
  ```
- Pour le préremplissage de l'identité utilisateur (optionnel) :
  `openssl` et le module Python `python3-yaml`.
- Pour tester sans clé USB : `qemu-system-x86_64` (paquet `qemu-system-x86`).
- Pour le lint : `yamllint` et `ansible-lint`.
- Espace disque : environ 10 Go (ISO source + ISO générée).

## Builder l'ISO

```bash
make build-iso
```

Télécharge l'ISO officielle Ubuntu 26.04 Desktop si absente
(`downloads/`), y injecte le seed autoinstall, et produit
`output/ubuntu-autoinstall.iso`.

### Création de l'utilisateur : deux méthodes

- **Interactif (par défaut)** : ne définissez aucune variable
  d'environnement. L'écran de création d'utilisateur de Subiquity s'affiche
  normalement au boot sur la machine cible.
- **Automatique** : exportez ces variables avant `make build-iso` — le
  script remplace alors la section `identity` du seed et désactive la
  saisie interactive pour ce champ :
  ```bash
  export BUILD_USERNAME="loic"
  export BUILD_USER_PASSWORD="un-mot-de-passe-fort"
  export BUILD_HOSTNAME="mon-poste"   # optionnel, défaut: ubuntu-freshinstall
  make build-iso
  ```
  Le mot de passe est haché (SHA-512 via `openssl passwd -6`) avant
  d'être écrit dans le seed — il n'est jamais stocké en clair sur l'ISO.

## Écrire l'ISO sur une clé USB

```bash
make write-usb DEVICE=/dev/sdX
```

Remplacez `/dev/sdX` par le périphérique de votre clé USB (vérifiez avec
`lsblk` avant de lancer la commande : **toutes les données du périphérique
seront effacées**). Une confirmation interactive est demandée avant le `dd`.

## Tester sans clé USB physique

```bash
make test-vm
```

Démarre l'ISO générée dans QEMU/KVM avec un disque virtuel de test
(`output/test-vm-disk.qcow2`, créé automatiquement au premier lancement).
Pratique pour valider le seed autoinstall avant d'écrire sur du matériel
réel.

**Attention** : relancer `make test-vm` redémarre toujours depuis l'ISO
(`-boot once=d` ne s'applique qu'au process QEMU en cours, pas d'un
lancement à l'autre) — sur un disque déjà installé, l'installeur détectera
des partitions existantes ("Unchanged") au lieu de faire un vrai test. Pour
reprendre une VM déjà installée (ex : tester un ajout au playbook sans tout
réinstaller) :

```bash
make boot-vm
```

Démarre directement sur `output/test-vm-disk.qcow2`, sans l'ISO.

## Ajouter un logiciel

Tout se passe dans `ansible/group_vars/all.yml` :

- `apt_packages` : liste simple de paquets apt.
- `deb_url_packages` : `{name, url}` pour un `.deb` téléchargé directement.
- `snap_packages` : liste simple de paquets snap.
- `tarball_apps` : `{name, url, binary_path, desktop_name}` pour une
  application distribuée en tarball, installée dans `/opt/<name>`.

Le rôle `oh_my_zsh` installe `zsh` + [Oh My Zsh](https://ohmyz.sh/) pour
l'utilisateur principal (premier compte humain détecté, UID >= 1000) et le
définit comme shell par défaut — pas de variable à configurer, activé par
défaut. Un `.zshrc` n'est créé que s'il n'existe pas déjà (n'écrase jamais
une config existante lors d'un re-run).

Pas besoin de relancer un build d'ISO pour tester un ajout : lancez
directement le playbook sur une machine déjà installée :

```bash
cd ansible
ansible-playbook -i inventory.ini site.yml --connection=local
```

### Maintenance des URLs de téléchargement

- **Google Chrome** (`dl.google.com/linux/direct/...`) : lien permanent
  maintenu par Google, jamais besoin de le changer.
- **JetBrains Toolbox** : utilise l'endpoint de redirection officiel
  `data.services.jetbrains.com/products/download?platform=linux&code=TBA`,
  qui pointe toujours vers la dernière version — pas de maintenance
  nécessaire.
- **Slack** : ne fournit pas de lien "latest" stable. L'URL dans
  `all.yml` est **versionnée** et devra être mise à jour manuellement de
  temps en temps (vérifier sur https://slack.com/downloads/linux).

## Dotfiles et secrets

Le rôle `dotfiles` est désactivé par défaut. Pour l'activer, passez l'URL de
votre dépôt de dotfiles **en ligne de commande**, jamais dans un fichier
commité :

```bash
ansible-playbook -i inventory.ini site.yml --connection=local \
  -e dotfiles_repo_url=git@github.com:votre-user/dotfiles.git
```

Le rôle clone le dépôt puis applique les liens avec `stow`. Ne committez
jamais de mots de passe, tokens ou clés privées dans ce dépôt : utilisez des
variables d'environnement ou `-e` sur la ligne de commande pour tout secret.

## Note Wayland

Ubuntu 26.04 passe l'édition GNOME en **Wayland uniquement** (la session
Xorg n'est plus proposée par défaut). Certaines applications Electron/Java
plus anciennes (JetBrains Toolbox, Slack) peuvent afficher des soucis
mineurs d'icône système ou de mise à l'échelle sous Wayland pur. En cas de
souci d'affichage, une session **"Ubuntu sur Xorg"** reste sélectionnable à
l'écran de connexion GDM comme solution de repli (non activée par défaut).

## Chiffrement disque matériel (HW FDE)

Le chiffrement disque matériel optionnel introduit en 26.04 (beta) n'est
**pas activé** dans `autoinstall.yaml`. Pour l'activer, ajoutez dans la
section `storage` :

```yaml
storage:
  layout:
    name: hybrid
    encrypted: yes
```

Nécessite un TPM 2.0 et Secure Boot actif sur la machine cible.

## Lint / CI

```bash
make lint
```

Exécute `yamllint` et `ansible-lint`. La CI GitHub Actions
(`.github/workflows/ci.yml`) lance en plus une vérification syntaxique du
playbook à chaque push/PR.

## Licence

MIT — voir [LICENSE](LICENSE).
