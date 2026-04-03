#!/bin/bash
# CloudMart Infrastructure Setup Script
# Run this after terraform apply and kubeconfig update to install all platform components

set -e

echo "=== CloudMart Infrastructure Setup ==="

# Add Helm repos
echo "Adding Helm repositories..."
helm repo add traefik https://traefik.github.io/charts
helm repo add strimzi https://strimzi.io/charts/
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Create namespaces
echo "Creating namespaces..."
kubectl create namespace cloudmart --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# Install Traefik (ingress controller)
echo "Installing Traefik..."
helm upgrade --install traefik traefik/traefik -n cloudmart \
  -f traefik/values.yaml

# Install Strimzi Kafka Operator
echo "Installing Strimzi Kafka Operator..."
helm upgrade --install strimzi strimzi/strimzi-kafka-operator -n cloudmart \
  -f kafka/values.yaml

# Install ArgoCD
echo "Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd -n argocd \
  --set server.service.type=LoadBalancer

# Install Prometheus + Grafana
echo "Installing Prometheus + Grafana..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/prometheus-values.yaml

# Install Loki
echo "Installing Loki..."
helm upgrade --install loki grafana/loki -n monitoring \
  -f monitoring/loki-values.yaml

# Install Kyverno
echo "Installing Kyverno..."
helm upgrade --install kyverno kyverno/kyverno -n kyverno --version 3.2.6

# Apply Kyverno policies
echo "Applying Kyverno policies..."
kubectl apply -f kyverno/

# Install Cert-Manager
echo "Installing Cert-Manager..."
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager \
  --set crds.enabled=true

# Apply Cert-Manager resources
echo "Applying ClusterIssuer and Certificate..."
kubectl apply -f cert-manager/cluster-issuer.yaml
kubectl apply -f cert-manager/certificate.yaml

# Apply Kafka cluster
echo "Deploying Kafka cluster..."
kubectl apply -f ../base/kafka/kafka.yaml -n cloudmart

# Apply ArgoCD App-of-Apps
echo "Deploying ArgoCD App-of-Apps..."
kubectl apply -f ../argocd/apps/cloudmart-app-of-apps.yaml -n argocd

echo ""
echo "=== Setup Complete ==="
echo ""
echo "ArgoCD password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Grafana password: cloudmart123"
echo ""
echo "Note: You still need to create secrets in the cloudmart namespace."
echo "See environments/production/ for details."
