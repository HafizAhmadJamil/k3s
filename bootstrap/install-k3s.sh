#!/bin/bash
set -euo pipefail

NODE_IP="$1"

if [[ -z "$NODE_IP" ]]; then
  echo "❌ Usage: $0 <node-ip>"
  exit 1
fi

echo "📦 Installing K3s without Traefik and ServiceLB..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

echo "🔁 Waiting for Kubernetes to be ready..."
until kubectl get nodes &>/dev/null; do sleep 2; done

echo "⚙️ Rewriting kubeconfig to use IP: $NODE_IP"
KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sed -i "s/127.0.0.1/$NODE_IP/g" "$KUBECONFIG"

echo "✅ K3s installed and kubeconfig patched."
