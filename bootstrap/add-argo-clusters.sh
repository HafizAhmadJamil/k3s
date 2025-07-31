#!/bin/bash
set -euo pipefail

# Constants
KUBECONFIG_PATH="$HOME/.kube/config"
ARGOCD_NAMESPACE="argocd"
ARGOCD_BINARY="/usr/local/bin/argocd"
PRIMARY_SITE="ksa-jed"
ARGOCD_DOMAIN="argocd.${PRIMARY_SITE}.lab.net"
CONTEXTS=("ksa-jed" "ksa-dmm" "ksa-ruh")

# Ensure ArgoCD CLI is installed
install_argocd_cli() {
  if ! command -v argocd &>/dev/null; then
    echo "📦 Installing ArgoCD CLI..."
    curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x argocd
    mv argocd "$ARGOCD_BINARY"
  else
    echo "✅ ArgoCD CLI already installed."
  fi
}

# Check /etc/hosts for primary ArgoCD domain
check_hosts_entry() {
  local domain="$1"
  if ! grep -q "$domain" /etc/hosts; then
    echo "❌ Missing entry for $domain in /etc/hosts"
    exit 1
  fi
}

# Login once to ArgoCD at primary site
argocd_login() {
  echo "🔐 Fetching ArgoCD admin password for $PRIMARY_SITE..."
  ARGOCD_PASSWORD=$(KUBECONFIG="$KUBECONFIG_PATH" kubectl --context "$PRIMARY_SITE" -n "$ARGOCD_NAMESPACE" \
    get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

  echo "🔐 Logging into ArgoCD at https://$ARGOCD_DOMAIN"
  "$ARGOCD_BINARY" login "$ARGOCD_DOMAIN" \
    --username admin \
    --password "$ARGOCD_PASSWORD" \
    --insecure \
    --grpc-web
}

# Register clusters with ArgoCD
add_clusters() {
  for ctx in "${CONTEXTS[@]}"; do
    echo "🔗 Registering cluster: $ctx"
    export KUBECONFIG="$KUBECONFIG_PATH"
    kubectl config use-context "$ctx" >/dev/null

    if "$ARGOCD_BINARY" cluster list --grpc-web | grep -q "$ctx"; then
      echo "✅ Cluster '$ctx' already registered."
    else
      "$ARGOCD_BINARY" cluster add "$ctx" --yes --grpc-web || echo "⚠️ Failed to add cluster '$ctx'"
    fi
  done
}

# Run
echo "🚀 Starting ArgoCD cluster registration..."
export KUBECONFIG="$KUBECONFIG_PATH"

install_argocd_cli
check_hosts_entry "$ARGOCD_DOMAIN"
argocd_login
add_clusters

echo "✅ All clusters registered in ArgoCD."
