#!/bin/bash
set -euo pipefail

CONFIG_DIR="${1:-/mnt/k3s/site-configs/ksa-jed}"
SITE="$(basename "$CONFIG_DIR")"
DOMAIN="argocd.${SITE}.lab.net"

echo "📦 Installing ArgoCD via Helm..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace

#echo "✏️ Patching ArgoCD server deployment to use --insecure..."
#kubectl -n argocd patch deployment argocd-server \
#  --type=json \
#  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]' || true

echo "🔐 Creating skip-verify ServersTransport (if not exists)..."
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: skip-verify
  namespace: argocd
spec:
  insecureSkipVerify: true
EOF

echo "🌐 Exposing ArgoCD via Traefik IngressRoute (HTTPS)..."
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`$DOMAIN\`)
      kind: Rule
      services:
        - name: argocd-server
          port: 443
          scheme: https
          serversTransport: skip-verify
  tls:
    secretName: traefik-wildcard
EOF

echo "📦 Installing ArgoCD CLI (if not already installed)..."
if ! command -v argocd &>/dev/null; then
  curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x /usr/local/bin/argocd
  echo "✅ ArgoCD CLI installed."
else
  echo "✅ ArgoCD CLI already present."
fi
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
echo "🔐 Fetching ArgoCD admin password..."
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "🌐 Logging into ArgoCD at $DOMAIN..."
argocd login "$DOMAIN" --username admin --password "$ARGO_PASSWORD" --insecure || true

echo "✅ ArgoCD setup completed and CLI authenticated."
