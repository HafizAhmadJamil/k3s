#!/bin/bash
set -euo pipefail

CONFIG_DIR="$1"
VALUES_FILE="$CONFIG_DIR/values-traefik.yaml"
SITE="$(basename "$CONFIG_DIR")"
CERT_SECRET="traefik-wildcard"
TLS_NAMESPACE="traefik"

echo "📁 Ensuring namespace '$TLS_NAMESPACE' exists..."
kubectl create namespace "$TLS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Generate wildcard TLS cert (only if not already created)
if ! kubectl get secret "$CERT_SECRET" -n "$TLS_NAMESPACE" &>/dev/null; then
  echo "🔐 Generating self-signed wildcard cert for *.${SITE}.lab.net"
  openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 365 \
    -nodes -subj "/CN=*.${SITE}.lab.net" -addext "subjectAltName=DNS:*.${SITE}.lab.net"

  echo "🔐 Creating TLS secret $CERT_SECRET in namespace $TLS_NAMESPACE"
  kubectl create secret tls "$CERT_SECRET" \
    --cert=tls.crt --key=tls.key \
    -n "$TLS_NAMESPACE"

  rm -f tls.crt tls.key
else
  echo "✅ TLS secret '$CERT_SECRET' already exists in namespace '$TLS_NAMESPACE'"
fi

echo "📦 Installing Traefik using values from: $VALUES_FILE"
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm upgrade --install traefik traefik/traefik \
  --namespace "$TLS_NAMESPACE" \
  --create-namespace \
  -f "$VALUES_FILE"

echo "🌐 Exposing Traefik dashboard securely via websecure..."
kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: $TLS_NAMESPACE
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`traefik.${SITE}.lab.net\`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
  tls:
    secretName: $CERT_SECRET
EOF

echo "✅ Traefik with wildcard TLS setup completed for site '$SITE'"
