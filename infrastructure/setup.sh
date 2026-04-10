#!/bin/bash
# CloudMart Infrastructure Setup Script
# Run this after terraform apply and kubeconfig update to install all platform components
#
# Usage:
#   cd infrastructure/
#   ./setup.sh
#
# Prerequisites:
#   - kubectl configured for the new cluster
#   - AWS CLI configured (same account as the cluster)
#   - helm installed

set -e

echo "=== CloudMart Infrastructure Setup ==="

REGION="us-east-1"
DOMAIN="tulunad.click"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="cloudmart-production"
ELB_ZONE="Z35SXDOTRQ7X7K"

# Look up hosted zone ID dynamically from domain name — never hardcode
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" = "None" ]; then
  echo "ERROR: No Route53 hosted zone found for $DOMAIN."
  echo "Run: ./create-hosted-zone.sh"
  exit 1
fi
echo "Hosted Zone ID: $HOSTED_ZONE_ID"

# ── Pre-flight: verify required AWS Secrets exist ─────────────────────────────
echo "Verifying required AWS Secrets Manager entries..."
for secret in cloudmart/product-service cloudmart/order-service cloudmart/ghcr-pull; do
  aws secretsmanager describe-secret --secret-id "$secret" --region "$REGION" > /dev/null 2>&1 || {
    echo "ERROR: Secret '$secret' not found in AWS Secrets Manager."
    echo "Create it manually before running setup.sh, then re-run."
    exit 1
  }
done
echo "All required secrets verified."

# ── Helm repos ────────────────────────────────────────────────────────────────
echo "Adding Helm repositories..."
helm repo add traefik https://traefik.github.io/charts
helm repo add strimzi https://strimzi.io/charts/
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo add jetstack https://charts.jetstack.io
helm repo add external-secrets https://charts.external-secrets.io
for i in 1 2 3; do
  helm repo update && break || { echo "Helm repo update failed (attempt $i/3), retrying in 10s..."; sleep 10; }
done

# ── Namespaces ────────────────────────────────────────────────────────────────
echo "Creating namespaces..."
for ns in cloudmart argocd monitoring kyverno cert-manager; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done

# ── Metrics Server ───────────────────────────────────────────────────────────
echo "Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status deployment metrics-server -n kube-system --timeout=60s

# ── Traefik ───────────────────────────────────────────────────────────────────
echo "Installing Traefik..."
helm upgrade --install traefik traefik/traefik -n cloudmart \
  -f traefik/values.yaml

# ── Strimzi Kafka Operator ────────────────────────────────────────────────────
echo "Installing Strimzi Kafka Operator..."
helm upgrade --install strimzi strimzi/strimzi-kafka-operator -n cloudmart \
  -f kafka/values.yaml

# ── ArgoCD ────────────────────────────────────────────────────────────────────
echo "Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd -n argocd \
  --set 'configs.params.server\.insecure=true' \
  --set server.service.type=ClusterIP \
  --disable-openapi-validation

# ── Prometheus + Grafana ──────────────────────────────────────────────────────
echo "Installing Prometheus + Grafana..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/prometheus-values.yaml

echo "Applying CloudMart alert rules..."
kubectl apply -f monitoring/alert-rules.yaml

# ── Loki ──────────────────────────────────────────────────────────────────────
echo "Installing Loki..."
helm upgrade --install loki grafana/loki -n monitoring \
  -f monitoring/loki-values.yaml

echo "Installing Promtail..."
helm upgrade --install promtail grafana/promtail -n monitoring \
  --set "config.clients[0].url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push" \
  --set resources.requests.memory=64Mi \
  --set resources.requests.cpu=50m \
  --set resources.limits.memory=128Mi \
  --set resources.limits.cpu=100m

# ── Kyverno ───────────────────────────────────────────────────────────────────
echo "Installing Kyverno..."
kubectl delete job kyverno-clean-reports -n kyverno --ignore-not-found
helm upgrade --install kyverno kyverno/kyverno -n kyverno --version 3.2.6 --timeout 5m --no-hooks

echo "Applying Kyverno policies..."
kubectl apply -f kyverno/

# ── Cert-Manager ──────────────────────────────────────────────────────────────
echo "Installing Cert-Manager..."
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager \
  --set crds.enabled=true

# ── IRSA: cert-manager → Route 53 ────────────────────────────────────────────
echo "Setting up IRSA for cert-manager..."
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION \
  --query "cluster.identity.oidc.issuer" --output text | cut -d'/' -f5)

# Create/update trust policy (idempotent)
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:cert-manager:cert-manager",
        "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF
)
aws iam update-assume-role-policy \
  --role-name cert-manager-route53 \
  --policy-document "$TRUST_POLICY" 2>/dev/null || \
aws iam create-role \
  --role-name cert-manager-route53 \
  --assume-role-policy-document "$TRUST_POLICY"

aws iam put-role-policy \
  --role-name cert-manager-route53 \
  --policy-name Route53DNS01 \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"route53:GetChange\",\"route53:ChangeResourceRecordSets\",\"route53:ListResourceRecordSets\"],
      \"Resource\": [\"arn:aws:route53:::hostedzone/${HOSTED_ZONE_ID}\",\"arn:aws:route53:::change/*\"]
    },{
      \"Effect\": \"Allow\",
      \"Action\": \"route53:ListHostedZonesByName\",
      \"Resource\": \"*\"
    }]
  }"

echo "Waiting for cert-manager to be ready..."
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-cainjector -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s

kubectl annotate serviceaccount cert-manager -n cert-manager \
  eks.amazonaws.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/cert-manager-route53 \
  --overwrite

kubectl rollout restart deployment cert-manager -n cert-manager
kubectl rollout status deployment cert-manager -n cert-manager --timeout=60s

# ── IRSA: external-secrets → Secrets Manager ──────────────────────────────────
echo "Setting up IRSA for external-secrets..."
ESO_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:cloudmart:external-secrets",
        "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF
)
aws iam update-assume-role-policy \
  --role-name cloudmart-external-secrets \
  --policy-document "$ESO_TRUST_POLICY" 2>/dev/null || \
aws iam create-role \
  --role-name cloudmart-external-secrets \
  --assume-role-policy-document "$ESO_TRUST_POLICY"

aws iam put-role-policy \
  --role-name cloudmart-external-secrets \
  --policy-name SecretsManagerRead \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"secretsmanager:GetSecretValue\",\"secretsmanager:DescribeSecret\"],
      \"Resource\": \"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:cloudmart/*\"
    }]
  }"

# ── External Secrets Operator ─────────────────────────────────────────────────
echo "Installing External Secrets Operator..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n cloudmart \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT_ID}:role/cloudmart-external-secrets" \
  --set serviceAccount.name=external-secrets

echo "Waiting for External Secrets Operator to be ready..."
kubectl rollout status deployment external-secrets -n cloudmart --timeout=120s
kubectl rollout status deployment external-secrets-webhook -n cloudmart --timeout=120s
kubectl rollout status deployment external-secrets-cert-controller -n cloudmart --timeout=60s

# ── cert-manager resources ────────────────────────────────────────────────────
echo "Cleaning up stale cert-manager resources..."
# Remove finalizers from stuck challenges (they block deletion when old hosted zone is gone)
for challenge in $(kubectl get challenges -n cloudmart -o name 2>/dev/null); do
  kubectl patch $challenge -n cloudmart -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null
done
kubectl delete challenges -n cloudmart --all --ignore-not-found 2>/dev/null
kubectl delete certificaterequest -n cloudmart --all --ignore-not-found 2>/dev/null
kubectl delete certificate tulunad-click-tls -n cloudmart --ignore-not-found 2>/dev/null

echo "Applying ClusterIssuer and Certificate..."
sed "s/__HOSTED_ZONE_ID__/$HOSTED_ZONE_ID/g" cert-manager/cluster-issuer.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-prod --timeout=60s
kubectl apply -f cert-manager/certificate.yaml -n cloudmart

# ── Kafka cluster ──────────────────────────────────────────────────────────────
echo "Waiting for Strimzi operator and CRDs to be ready..."
kubectl rollout status deployment strimzi-cluster-operator -n cloudmart --timeout=120s
kubectl wait --for=condition=Established crd/kafkas.kafka.strimzi.io --timeout=60s
kubectl wait --for=condition=Established crd/kafkanodepools.kafka.strimzi.io --timeout=60s

echo "Deploying Kafka cluster..."
kubectl apply -f ../base/kafka/kafka.yaml -n cloudmart

# ── DNS records ───────────────────────────────────────────────────────────────
echo "Waiting for Traefik LoadBalancer hostname..."
for i in $(seq 1 36); do
  LB=$(kubectl get svc traefik -n cloudmart -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$LB" ]; then break; fi
  echo "  ($i/36) LB not ready yet, waiting..."
  sleep 10
done

if [ -z "$LB" ]; then
  echo "ERROR: Traefik LB not ready after 6 minutes"
  exit 1
fi

echo "Updating DNS records → $LB"
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [
      {\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"$DOMAIN\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"$ELB_ZONE\",\"DNSName\":\"$LB\",\"EvaluateTargetHealth\":false}}},
      {\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"argocd.$DOMAIN\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"$ELB_ZONE\",\"DNSName\":\"$LB\",\"EvaluateTargetHealth\":false}}},
      {\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"grafana.$DOMAIN\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"$ELB_ZONE\",\"DNSName\":\"$LB\",\"EvaluateTargetHealth\":false}}},
      {\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"traefik.$DOMAIN\",\"Type\":\"A\",\"AliasTarget\":{\"HostedZoneId\":\"$ELB_ZONE\",\"DNSName\":\"$LB\",\"EvaluateTargetHealth\":false}}}
    ]
  }"

# ── IngressRoutes ─────────────────────────────────────────────────────────────
echo "Applying IngressRoutes..."
kubectl apply -f ../base/ingress/ingressroute.yaml -n cloudmart
kubectl apply -f ../base/ingress/ingressroute-tls.yaml -n cloudmart
kubectl apply -f ../base/ingress/redirect-middleware.yaml -n cloudmart
kubectl apply -f ingress/subdomain-ingressroutes.yaml

# ── Wait for ArgoCD server before applying App-of-Apps ───────────────────────
echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment argocd-server -n argocd --timeout=180s

# ── ArgoCD App-of-Apps ────────────────────────────────────────────────────────
echo "Deploying ArgoCD App-of-Apps..."
kubectl apply -f ../argocd/apps/cloudmart-app-of-apps.yaml -n argocd

# ── Seed database ─────────────────────────────────────────────────────────────
echo "Waiting for ArgoCD to sync and deploy services..."
for i in $(seq 1 60); do
  STATUS=$(kubectl get application cloudmart-production -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
  HEALTH=$(kubectl get application cloudmart-production -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
  if [ "$STATUS" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then break; fi
  echo "  ($i/60) ArgoCD status: sync=$STATUS health=$HEALTH, waiting..."
  sleep 10
done

echo "Waiting for product-service pod to be ready..."
kubectl rollout status deployment product-service -n cloudmart --timeout=300s

echo "Seeding database with products..."
PRODUCT_POD=$(kubectl get pod -n cloudmart -l app=product-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n cloudmart "$PRODUCT_POD" -- python seed.py

echo ""
echo "=== Setup Complete ==="
echo ""
echo "ArgoCD:  https://argocd.$DOMAIN"
echo "  user:  admin"
echo "  pass:  $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "Grafana: https://grafana.$DOMAIN"
echo "  user:  admin"
echo "  pass:  cloudmart123"
echo ""
echo "App:     https://$DOMAIN"
echo ""
echo "Traefik: https://traefik.$DOMAIN"
echo ""
echo "NOTE: TLS cert takes ~5 min to issue (DNS-01 challenge via Route53)."
echo "NOTE: ArgoCD will sync and deploy all app services automatically."
echo "NOTE: Kafka takes ~3 min. order-service will restart until it's ready — this is normal."
echo "NOTE: AWS Secrets Manager → ESO will sync secrets into the cluster automatically."
