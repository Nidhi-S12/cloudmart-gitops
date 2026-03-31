#!/bin/bash
# Creates Kubernetes secrets for local development.
# Run this once after applying the kustomize overlay.
# This script is gitignored — secrets never touch git.

set -e

NAMESPACE="cloudmart"

echo "Creating secrets in namespace: $NAMESPACE"

# host.docker.internal resolves to your host machine from inside Docker Desktop k8s pods
# docker-compose exposes postgres on 5432, redis on 6379, kafka on 9092

kubectl create secret generic product-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=database-url="postgresql+asyncpg://postgres:postgres@host.docker.internal:5432/cloudmart" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic order-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=redis-host="host.docker.internal" \
  --from-literal=kafka-brokers="host.docker.internal:9092" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets created successfully."
echo ""
echo "Verify with:"
echo "  kubectl get secrets -n $NAMESPACE"
