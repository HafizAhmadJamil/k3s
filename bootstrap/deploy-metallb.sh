#!/bin/bash
set -euo pipefail

CONFIG_DIR="$1"
POOL_FILE="$CONFIG_DIR/ip-pool.yaml"
ADV_FILE="$CONFIG_DIR/l2adv.yaml"

if [[ ! -f "$POOL_FILE" || ! -f "$ADV_FILE" ]]; then
  echo "❌ MetalLB config files missing in: $CONFIG_DIR"
  exit 1
fi

echo "📦 Installing MetalLB and applying IP pool + L2 advertisement..."

helm repo add metallb https://metallb.github.io/metallb
helm repo update

helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --create-namespace

echo "⏱️ Waiting for MetalLB controller to be ready..."
kubectl wait --namespace metallb-system --for=condition=Available deployment --all --timeout=120s

echo "📄 Applying IPAddressPool and L2Advertisement..."
kubectl apply -f "$POOL_FILE"
kubectl apply -f "$ADV_FILE"

echo "✅ MetalLB configured successfully."
