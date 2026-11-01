# ==========================================
# Alias pour Kubernetes (kubeadm)
# ==========================================
# How to use it: 
# Copy/paste this bloc in your ~/.bashrc or your custom alias file.
# Example in ~/.bashrc:
# if [ -f "$HOME/alias.sh" ]; then
#     source "$HOME/alias.sh"
# fi
# source ~/.bashrc

# 1. Alias de base (gère l'authentification et les certificats)
alias etcdctl-k8s='sudo etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key'

# 2. Raccourcis de diagnostic rapides
alias etcd-health='etcdctl-k8s endpoint health'
alias etcd-status='etcdctl-k8s endpoint status -w table'
alias etcd-members='etcdctl-k8s member list -w table'
alias etcd-alarms='etcdctl-k8s alarm list'

# 3. Raccourcis avancés
alias etcd-leader='etcdctl-k8s endpoint status -w table | grep -E "true|IS LEADER"'
alias etcd-version='etcdctl-k8s version'
alias etcd-perf='etcdctl-k8s check perf'

# 4. Sauvegarde (Snapshot)
alias etcd-backup='etcdctl-k8s snapshot save "/var/backups/etcd/etcd-$(date +%Y%m%d-%H%M%S).db"'

# 5. Kubernetes versions table alias

k8sv() {
    local rows=()
    local component version
    local width=25

    add_row() {
        rows+=("$1|$2")
    }

    # Local binaries
    if command -v kubectl >/dev/null 2>&1; then
        version=$(kubectl version --client -o json 2>/dev/null |
            grep -o '"gitVersion":[[:space:]]*"[^"]*"' |
            head -1 | cut -d '"' -f4)
        add_row "kubectl" "${version:-Unknown}"
    else
        add_row "kubectl" "Not installed"
    fi

    if command -v kubeadm >/dev/null 2>&1; then
        version=$(kubeadm version -o short 2>/dev/null)
        add_row "kubeadm" "${version:-Unknown}"
    else
        add_row "kubeadm" "Not installed"
    fi

    if command -v kubelet >/dev/null 2>&1; then
        version=$(kubelet --version 2>/dev/null | awk '{print $2}')
        add_row "kubelet (local)" "${version:-Unknown}"
    else
        add_row "kubelet (local)" "Not installed"
    fi

    # Kubernetes API server
    version=$(kubectl version -o json 2>/dev/null |
        grep -o '"gitVersion":[[:space:]]*"[^"]*"' |
        tail -1 | cut -d '"' -f4)
    add_row "Kubernetes API Server" "${version:-Unavailable}"

    # Versions of all nodes
    if command -v kubectl >/dev/null 2>&1; then
        while IFS='|' read -r component version; do
            [[ -n "$component" ]] &&
                add_row "kubelet ($component)" "$version"
        done < <(
            kubectl get nodes \
                -o custom-columns='NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion' \
                --no-headers 2>/dev/null |
            awk '{print $1 "|" $2}'
        )
    fi

    # Control-plane and etcd image versions
    while IFS='|' read -r component version; do
        [[ -n "$component" ]] && add_row "$component" "$version"
    done < <(
        kubectl -n kube-system get pods \
            -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
            2>/dev/null |
        while IFS='|' read -r pod images; do
            case "$pod" in
                kube-scheduler-*)
                    image=${images%% *}
                    echo "kube-scheduler|${image##*:}"
                    ;;
                kube-controller-manager-*)
                    image=${images%% *}
                    echo "kube-controller-manager|${image##*:}"
                    ;;
                etcd-*)
                    image=${images%% *}
                    echo "etcd|${image##*:}"
                    ;;
            esac
        done | awk -F'|' '!seen[$1]++'
    )

    # Container runtime
    if command -v containerd >/dev/null 2>&1; then
        version=$(containerd --version 2>/dev/null | awk '{print $3}')
        add_row "containerd (local)" "${version:-Unknown}"
    elif command -v crio >/dev/null 2>&1; then
        version=$(crio --version 2>/dev/null |
            awk '/Version:/ {print $2; exit}')
        add_row "CRI-O (local)" "${version:-Unknown}"
    else
        add_row "Container runtime (local)" "Not installed"
    fi

    # Table header
    printf '\n┌─────────────────────────┬──────────────────────────────┐\n'
    printf '│ %-23s │ %-28s │\n' "COMPONENT" "VERSION"
    printf '├─────────────────────────┼──────────────────────────────┤\n'

    for row in "${rows[@]}"; do
        component=${row%%|*}
        version=${row#*|}

        printf '│ %-23.23s │ %-28.28s │\n' "$component" "$version"
    done

    printf '└─────────────────────────┴──────────────────────────────┘\n\n'
}