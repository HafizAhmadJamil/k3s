#!/bin/bash
set -euo pipefail

# Ensure yq is installed
if ! command -v yq &>/dev/null; then
  echo "📦 yq not found — installing..."
  sudo wget -q -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  sudo chmod +x /usr/local/bin/yq
  echo "✅ yq installed at /usr/local/bin/yq"
else
  echo "✅ yq already installed"
fi

# Prepare kubeconfig output file
mkdir -p ~/.kube
OUT=~/.kube/config
> "$OUT"

echo "🔄 Merging kubeconfigs..."

TMPFILES=()
for SITE in ksa-jed ksa-dmm ksa-ruh; do
  SRC="./kubeconfigs/${SITE}.kubeconfig.yaml"
  DST="/tmp/${SITE}-renamed.yaml"

  if [[ ! -f "$SRC" ]]; then
    echo "❌ Missing $SRC"
    continue
  fi

  CONTEXT_NAME="$SITE"
  CLUSTER_NAME="$SITE-cluster"
  USER_NAME="$SITE-user"

  echo "🔧 Patching kubeconfig for $SITE"

  yq eval "
    .clusters[0].name = \"$CLUSTER_NAME\" |
    .users[0].name = \"$USER_NAME\" |
    .contexts[0].name = \"$CONTEXT_NAME\" |
    .contexts[0].context.cluster = \"$CLUSTER_NAME\" |
    .contexts[0].context.user = \"$USER_NAME\"
  " "$SRC" > "$DST"

  TMPFILES+=("$DST")
done

# Merge all patched configs into one
export KUBECONFIG=$(IFS=:; echo "${TMPFILES[*]}")
kubectl config view --flatten > "$OUT"
chmod 600 "$OUT"

# Reset KUBECONFIG and set current context
unset KUBECONFIG
KUBECONFIG="$OUT" kubectl config use-context ksa-jed

echo "✅ Merged kubeconfigs:"
KUBECONFIG="$OUT" kubectl config get-contexts
