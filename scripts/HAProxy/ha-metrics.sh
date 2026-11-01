#!/bin/bash
set -eu

DIR="/var/lib/prometheus/node-exporter"
TMP="${DIR}/ha_metrics.prom.$$"
OUT="${DIR}/ha_metrics.prom"

# Check HAProxy
if systemctl is-active --quiet haproxy; then
    HAPROXY=1
else
    HAPROXY=0
fi

# Check Keepalived
if systemctl is-active --quiet keepalived; then
    KEEPALIVED=1
else
    KEEPALIVED=0
fi

# Check whether the VIP is assigned to this machine
if ip -o addr show | grep -qE 'inet 192\.168\.56\.10/24([[:space:]]|$)'; then
    VIP=1
else
    VIP=0
fi

# Write metrics to a temporary file
cat > "$TMP" <<EOF
# HELP haproxy_service_up 1 if HAProxy is active, 0 otherwise.
# TYPE haproxy_service_up gauge
haproxy_service_up $HAPROXY
# HELP keepalived_service_up 1 if Keepalived is active, 0 otherwise.
# TYPE keepalived_service_up gauge
keepalived_service_up $KEEPALIVED
# HELP vip_present 1 if the VIP is present on this host, 0 otherwise.
# TYPE vip_present gauge
vip_present $VIP
EOF

# Set readable permissions
chmod 644 "$TMP"

# Atomically replace the previous metrics file
mv "$TMP" "$OUT"