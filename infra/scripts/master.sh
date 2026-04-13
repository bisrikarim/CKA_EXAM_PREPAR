#!/bin/bash
# ============================================================
# master.sh — Initialisation du control-plane
# ============================================================
set -e

echo ">>> [1/4] kubeadm init"
kubeadm init \
  --apiserver-advertise-address="${MASTER_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --kubernetes-version="v1.28.0" \
  --ignore-preflight-errors=NumCPU

echo ">>> [2/4] kubeconfig pour l'utilisateur vagrant"
mkdir -p /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config

# Aussi pour root
export KUBECONFIG=/etc/kubernetes/admin.conf

echo ">>> [3/4] Installation Flannel (CNI)"
kubectl apply -f \
  https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo ">>> [4/4] Génération de la commande join"
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "$JOIN_CMD" > /vagrant/join-command.sh
chmod +x /vagrant/join-command.sh

# Alias utiles pour la CKA
cat <<'EOF' >> /home/vagrant/.bashrc

# ── CKA shortcuts ──────────────────────────
alias k='kubectl'
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
EOF

echo "✅ Master prêt ! Cluster initialisé."
kubectl get nodes
