#!/bin/bash
# ============================================================
# worker.sh — Rejoindre le cluster
# ============================================================
set -e

echo ">>> Attente de la commande join générée par le master..."
# Attendre que le master ait créé le fichier join-command.sh
RETRIES=30
until [ -f /vagrant/join-command.sh ] || [ $RETRIES -eq 0 ]; do
  echo "   En attente... ($RETRIES restants)"
  sleep 10
  RETRIES=$((RETRIES-1))
done

if [ ! -f /vagrant/join-command.sh ]; then
  echo "❌ Fichier join-command.sh introuvable. Lancez le master d'abord."
  exit 1
fi

echo ">>> Join du cluster"
bash /vagrant/join-command.sh

# Alias utiles
cat <<'EOF' >> /home/vagrant/.bashrc

# ── CKA shortcuts ──────────────────────────
alias k='kubectl'
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
EOF

echo "✅ $(hostname) a rejoint le cluster !"
