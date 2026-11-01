#!/bin/bash
# install-calico.sh - Installation du plugin réseau Calico (CNI)

set -Eeuo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}==> $1${NC}"; }
ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
die()  { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# Vérification du nom d'hôte (adapté à ton /etc/hosts)
if [[ "$(hostname)" != "master1" ]]; then
  die "Ce script d'initialisation doit être exécuté UNIQUEMENT sur master1."
fi

# Vérification si le cluster n'est pas déjà initialisé
if [[ -f /etc/kubernetes/admin.conf ]]; then
  die "Le cluster semble déjà initialisé (/etc/kubernetes/admin.conf existe)."
fi

# Localisation du fichier de configuration Kubeadm
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${BASE_DIR}/scripts/kubeadm-config.yaml"

if [[ ! -f "$CONFIG" ]]; then
  die "Fichier de configuration absent : $CONFIG"
fi

info "[1/6] Vérification du runtime containerd..."
if ! systemctl is-active --quiet containerd; then
  die "containerd n'est pas actif. Vérifie le service avant de continuer."
fi
ok "containerd est actif."

info "[2/6] Adaptation de la version Kubernetes dans le fichier de config..."
K8S_VERSION="$(kubeadm version -o short)"
sed -i -E "s/^kubernetesVersion:.*/kubernetesVersion: ${K8S_VERSION}/" "$CONFIG"
ok "Version K8s fixée à : $K8S_VERSION"

info "[3/6] Initialisation du cluster (cette étape peut prendre quelques minutes)..."
kubeadm init --config "$CONFIG" --upload-certs

info "[4/6] Configuration des accès administrateur (kubectl)..."
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config
# Export explicite pour être sûr que kubectl marche dans la suite du script
export KUBECONFIG=/etc/kubernetes/admin.conf

info "[5/6] Installation du plugin réseau Calico (Tigera Operator)..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml

info "[5/6] Attente de la création des CRD (Custom Resource Definitions)..."


# Boucle d'attente intelligente : on patiente tant que le CRD n'existe pas
until kubectl get crd installations.operator.tigera.io &>/dev/null; do
  echo -n "."
  sleep 2
done
echo ""

kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=60s
kubectl wait --for=condition=Established crd/apiservers.operator.tigera.io --timeout=60s
kubectl wait --for=condition=Established crd/goldmanes.operator.tigera.io --timeout=60s
kubectl wait --for=condition=Established crd/whiskers.operator.tigera.io --timeout=60s

info "[5/6] Configuration du réseau Calico (CIDR: 10.244.0.0/16) avec Goldmane et Whisker..."
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
---
apiVersion: operator.tigera.io/v1
kind: Goldmane
metadata:
  name: default
spec: {}
---
apiVersion: operator.tigera.io/v1
kind: Whisker
metadata:
  name: default
spec: {}
EOF

info "[6/6] Génération des scripts de jointure pour les autres nœuds..."
TOKEN="$(kubeadm token create)"
CA_HASH="sha256:$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex | awk '{print $NF}')"

CERT_KEY="$(kubeadm init phase upload-certs --upload-certs --config "$CONFIG" | tail -n 1)"

if [[ -z "$CERT_KEY" || "$CERT_KEY" == *" "* ]]; then
  die -e "${RED}[ERROR] Impossible de récupérer la clé des certificats (CERT_KEY).${NC}" >&2
fi

JOIN_DIR=/home/vagrant/join-scripts
mkdir -p "$JOIN_DIR"


cat > "$JOIN_DIR/worker.sh" <<EOF
#!/usr/bin/env bash
set -e
echo "Rejoindre en tant que Worker..."
kubeadm join 192.168.56.10:6443 \\
  --token ${TOKEN} \\
  --discovery-token-ca-cert-hash ${CA_HASH}
EOF

cat > "$JOIN_DIR/control-plane.sh" <<EOF
#!/usr/bin/env bash
set -e
echo "Rejoindre en tant que Master (Control Plane)..."
kubeadm join 192.168.56.10:6443 \\
  --token ${TOKEN} \\
  --discovery-token-ca-cert-hash ${CA_HASH} \\
  --control-plane \\
  --certificate-key ${CERT_KEY}
EOF

chmod 700 "$JOIN_DIR"/*.sh

echo
echo -e "${CYAN}============================================${NC}"
ok "Cluster initialisé avec succès !"
echo -e "Commandes de jointure générées et prêtes :"
echo -e "  - Pour les workers : ${BOLD}$JOIN_DIR/worker.sh${NC}"
echo -e "  - Pour les masters : ${BOLD}$JOIN_DIR/control-plane.sh${NC}"
echo -e "${CYAN}============================================${NC}"
echo

# Affiche l'état des nœuds
kubectl get nodes