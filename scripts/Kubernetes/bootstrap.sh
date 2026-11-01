#!/bin/bash
# bootstrap.sh

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
K8S_MINOR="${K8S_MINOR:-v1.36}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
info() { echo -e "${BLUE}==> $1${NC}"; }
ok()   { echo -e "${GREEN}[OK] $1${NC}"; }


info "[1/8] Mise à jour et préparation du système Debian..."
apt-get update
apt-get install -y ca-certificates curl gpg apt-transport-https

info "[2/8] Désactivation du Swap (prérequis Kubernetes)..."
swapoff -a
sed -i '/swap/d' /etc/fstab

info "[3/8] Chargement des modules noyau (overlay, br_netfilter)..."
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

info "[4/8] Application des paramètres sysctl pour le réseau..."
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system > /dev/null

info "[5/8] Déploiement du runtime de conteneurs (Containerd)..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Charge les variables d'environnement de l'OS (ex: VERSION_CODENAME=bookworm)
. /etc/os-release

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y containerd.io

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Utiliser systemd comme gestionnaire des cgroups.
sed -i \
  's/SystemdCgroup = false/SystemdCgroup = true/' \
  /etc/containerd/config.toml
systemctl enable containerd
systemctl restart containerd

info "[6/8] Ajout du dépôt officiel Kubernetes (${K8S_MINOR})..."
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL \
  "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes \
      -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /
EOF

apt-get update

info "[7/8] Installation des composants clés (kubelet, kubeadm, kubectl)..."
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

info "[8/8] Configuration de la résolution DNS locale (/etc/hosts)..."
touch /etc/hosts
sed -i '/# BEGIN K8S LAB/,/# END K8S LAB/d' /etc/hosts

cat >> /etc/hosts <<'EOF'
# BEGIN K8S LAB
192.168.56.20 lb
192.168.56.30 lb2
192.168.56.11 master1
192.168.56.12 master2
192.168.56.13 master3
192.168.56.21 worker1
192.168.56.22 worker2
# END K8S LAB
EOF

info "=== Vérification des versions déployées ==="
containerd --version
kubeadm version
kubelet --version

ok "Opération terminée ! Le nœud $(hostname) est prêt."