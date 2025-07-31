#!/bin/bash
set -euo pipefail

### 🌍 Input Vars
SITE="${1:-}"
NODE_IP="${2:-}"

CONFIG_DIR="/mnt/k3s/site-configs/${SITE}"
KUBECONFIG_OUT="/mnt/k3s/kubeconfigs/${SITE}.kubeconfig.yaml"
K3S_FLAG_FILE="/etc/rancher/k3s/.installed"
LOG_DIR="/mnt/k3s/logs"

### ✅ Validate Inputs
if [[ -z "$SITE" || -z "$NODE_IP" ]]; then
  echo "❌ Usage: $0 <site-name> <node-ip>"
  exit 1
fi

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "❌ Config directory not found: $CONFIG_DIR"
  exit 1
fi

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/${SITE}.log") 2>&1

echo -e "\n🚀 Starting bootstrap for site: $SITE"
echo "🌐 Node IP: $NODE_IP"
echo "📁 Using config from: $CONFIG_DIR"

### 🧰 Step 0: CLI Prep
echo -e "\n🔹 Step 0: Ensuring kubectl completion, alias, and helm availability..."

# Always append these to ~/.bashrc if not already present
BASHRC="$HOME/.bashrc"

ensure_line() {
  grep -qF -- "$1" "$BASHRC" || echo "$1" >> "$BASHRC"
}

ensure_line "source <(kubectl completion bash)"
ensure_line "alias k=kubectl"
ensure_line "complete -F __start_kubectl k"
ensure_line "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"

echo "✅ kubectl aliases, completion, and KUBECONFIG export ensured in .bashrc"

# Apply in current shell too
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
alias k=kubectl
complete -F __start_kubectl k

if ! command -v helm &>/dev/null; then
  echo "📦 Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
else
  echo "✅ Helm already installed"
fi


### 🧱 Step 1: Install K3s
echo -e "\n🔹 Step 1: Installing K3s (if not already installed)..."
if [[ ! -f "$K3S_FLAG_FILE" ]]; then
  /mnt/k3s/bootstrap/install-k3s.sh "$NODE_IP"
  touch "$K3S_FLAG_FILE"
else
  echo "✅ K3s already installed, skipping..."
fi

echo "⏱️ Waiting for Kubernetes API to respond..."
until kubectl get nodes &>/dev/null; do sleep 2; done


### 🌐 Step 2: Deploy MetalLB
echo -e "\n🔹 Step 2: Deploying MetalLB..."
/mnt/k3s/bootstrap/deploy-metallb.sh "$CONFIG_DIR"

### 🌐 Step 3: Deploy Traefik
echo -e "\n🔹 Step 3: Deploying Traefik Ingress..."
/mnt/k3s/bootstrap/deploy-traefik.sh "$CONFIG_DIR"

### 🚀 Step 4: Deploy ArgoCD (only on main site)
echo -e "\n🔹 Step 4: ArgoCD setup..."
if [[ "$SITE" == "ksa-jed" ]]; then
  echo "🎛️  Deploying ArgoCD on control cluster [$SITE]..."
  /mnt/k3s/bootstrap/deploy-argocd.sh "$CONFIG_DIR"
else
  echo "ℹ️  Skipping ArgoCD for non-control site [$SITE]"
fi

### 💾 Step 5: Save Kubeconfig
echo -e "\n🔹 Step 5: Saving kubeconfig..."
if [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
  cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_OUT"
  sed -i "s/127.0.0.1/$NODE_IP/g" "$KUBECONFIG_OUT"
  echo "✅ Kubeconfig saved to $KUBECONFIG_OUT"
else
  echo "❌ Error: kubeconfig not found at /etc/rancher/k3s/k3s.yaml"
  exit 1
fi

echo -e "\n✅ [$SITE] Bootstrap complete!\nLog: $LOG_DIR/${SITE}.log"
