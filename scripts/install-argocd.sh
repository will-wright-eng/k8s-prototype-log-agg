#!/bin/bash
# Create argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Install ArgoCD
echo "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
# Get ArgoCD admin password
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
# Install ArgoCD CLI
echo "Installing ArgoCD CLI..."
ARGOCD_VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64
sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
rm /tmp/argocd-linux-amd64
# Port forward for ArgoCD API access (run in background for CLI access)
echo "Setting up port-forward for ArgoCD API (press Ctrl+C to stop)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PORT_FORWARD_PID=$!
sleep 5
# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
# Login to ArgoCD
echo "Logging in to ArgoCD..."
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure
# Kill port-forward process
kill $PORT_FORWARD_PID
echo "ArgoCD installation complete!"
echo "To access ArgoCD UI, run: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then access: https://localhost:8080 with username 'admin' and the password shown above"
