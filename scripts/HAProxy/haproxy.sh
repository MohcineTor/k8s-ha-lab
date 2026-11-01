#!/bin/bash
# Load balancer TCP pour l'API server Kubernetes (port 6443)
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

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

VIP="192.168.56.10"
LB1="192.168.56.20"
LB2="192.168.56.30"

hostname="$(hostname -s)"

case "$hostname" in
  lb)
    LOCAL_IP="$LB1"
    PEER_IP="$LB2"
    PRIORITY="150"
    STATE="MASTER"
    ;;
  lb2)
    LOCAL_IP="$LB2"
    PEER_IP="$LB1"
    PRIORITY="100"
    STATE="BACKUP"
    ;;
  *)
    echo "Nom de machine inattendu : $hostname" >&2
    exit 1
    ;;
esac


info "[1/5] Mise à jour des paquets et installation de HAProxy..."
apt-get update -y
apt-get install -y haproxy keepalived

info "[2/5] Détecter l'interface qui correspond à l'IP locale ($LOCAL_IP)..."
IFACE="$(ip -o -4 addr show |
  awk -v ip="$LOCAL_IP" '$4 ~ ("^" ip "/") {print $2; exit}')"

if [ -z "$IFACE" ]; then
  echo "Adresse $LOCAL_IP introuvable sur $hostname." >&2
  ip -br addr
  exit 1
fi

info "[3/5] Sauvegarde de la configuration d'origine de HAProxy..."
if [ -f /etc/haproxy/haproxy.cfg ]; then
  cp -n /etc/haproxy/haproxy.cfg \
    /etc/haproxy/haproxy.cfg.original || true
fi

info "[4/5] Génération de la configuration HAProxy (Load Balancing TCP)..."
cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 5s
    timeout client  1h
    timeout server  1h

frontend kubernetes-api
    bind *:6443
    default_backend kubernetes-control-planes

backend kubernetes-control-planes
    option tcp-check
    balance roundrobin
    default-server inter 3s fall 3 rise 2
    server master1  192.168.56.11:6443 check
    server master2  192.168.56.12:6443 check
    server master3  192.168.56.13:6443 check

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
EOF

haproxy -c -f /etc/haproxy/haproxy.cfg

info "[5/6] Génération de script surveillance du service HAProxy..."
cat > /usr/local/sbin/check-haproxy.sh <<'EOF'
#!/bin/sh
systemctl is-active --quiet haproxy
EOF

chmod 755 /usr/local/sbin/check-haproxy.sh

info "[6/7] Configuration de Keepalived..."
cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id ${hostname}
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/local/sbin/check-haproxy.sh"
    interval 2
    timeout 2
    fall 2
    rise 2
    weight -60
}

vrrp_instance VI_K8S {
    state ${STATE}
    interface ${IFACE}
    virtual_router_id 51
    priority ${PRIORITY}
    advert_int 1

    # Unicast : évite de dépendre du multicast VRRP
    unicast_src_ip ${LOCAL_IP}
    unicast_peer {
        ${PEER_IP}
    }

    authentication {
        auth_type PASS
        auth_pass K8sHA51
    }

    virtual_ipaddress {
        ${VIP}/24 dev ${IFACE}
    }

    track_script {
        chk_haproxy
    }
}
EOF

info "[7/7] Redémarrage des services..."

systemctl enable haproxy keepalived
systemctl restart haproxy
systemctl restart keepalived

ok "Configuration terminée sur $hostname ($LOCAL_IP, interface $IFACE)"