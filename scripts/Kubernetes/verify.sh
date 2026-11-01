#!/bin/bash
# check-cluster.sh - Validation de l'état du cluster et test de déploiement

set -Eeuo pipefail

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "\n${BLUE}==> $1${NC}"; }
ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
die()  { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# Vérification et configuration de l'accès au cluster
if [[ -f /etc/kubernetes/admin.conf ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
elif [[ -f "$HOME/.kube/config" ]]; then
  export KUBECONFIG="$HOME/.kube/config"
else
  die "Aucun fichier Kubeconfig trouvé. Exécute ce script sur un nœud Master."
fi

echo -e "${CYAN}${BOLD}============================================${NC}"
echo -e "${CYAN}${BOLD}     DIAGNOSTIC DU CLUSTER KUBERNETES       ${NC}"
echo -e "${CYAN}${BOLD}============================================${NC}"

info "[1/6] Version de Kubernetes"
kubectl version

info "[2/6] État des Nœuds (Masters & Workers)"
kubectl get nodes -o wide

info "[3/6] État des Pods Système (Réseau, CoreDNS, etc.)"
kubectl get pods -A

info "[4/6] Santé de l'API Server"
API_STATUS=$(kubectl get --raw='/readyz')
if [[ "$API_STATUS" == "ok" ]]; then
  ok "API Server : Prêt (readyz = ok)"
else
  die "L'API Server a retourné un statut inattendu : $API_STATUS"
fi

info "[5/6] Membres de la base de données (etcd)"
kubectl get pods -n kube-system -l component=etcd -o wide

info "[6/6] Test d'un déploiement réel (Serveur Web Nginx)..."
# Création propre d'un déploiement sans écraser s'il existe déjà
kubectl create deployment nginx --image=nginx:stable --dry-run=client -o yaml | kubectl apply -f -


echo -e "${YELLOW}En attente du démarrage du Pod Nginx (timeout: 180s)...${NC}"
kubectl rollout status deployment/nginx --timeout=180s

echo -e "\n${CYAN}--- Résultat du Déploiement ---${NC}"
kubectl get deployment nginx
echo -e "\n${CYAN}--- Emplacement du Pod Nginx ---${NC}"
kubectl get pods -l app=nginx -o wide

echo -e "\n${CYAN}${BOLD}============================================${NC}"
ok "Diagnostic terminé ! Ton cluster est 100% fonctionnel."
echo -e "${CYAN}${BOLD}============================================${NC}\n"