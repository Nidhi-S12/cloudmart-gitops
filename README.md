# CloudMart GitOps

![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-326CE5?logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-Charts-0F1689?logo=helm&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

Infrastructure-as-Code and Kubernetes manifests for the CloudMart e-commerce platform. This repo is the single source of truth for everything running on AWS — from the VPC and EKS cluster to application deployments.

**Live at:** `https://tulunad.click`

---

## Repositories

| Repo | Purpose |
|------|---------|
| [cloudmart-gitops](https://github.com/Nidhi-S12/cloudmart-gitops) | This repo — Terraform, Helm values, K8s manifests, ArgoCD config |
| [cloudmart-services](https://github.com/Nidhi-S12/cloudmart-services) | Backend microservices (Node.js + Python) |
| [cloudmart-frontend](https://github.com/Nidhi-S12/cloudmart-frontend) | Next.js frontend |

---

## AWS Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                  AWS  (us-east-1)                                │
│                                                                                  │
│   Route 53 (tulunad.click) ──DNS──▶ Network Load Balancer                       │
│   Secrets Manager          ◀──IRSA── External Secrets Operator (in cluster)     │
│   S3 (terraform state)                                                           │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐   │
│  │                          VPC   10.0.0.0/16                                │   │
│  │                                                                           │   │
│  │  ┌──────────────────────────────┐  ┌────────────────────────────────────┐ │   │
│  │  │     Public Subnets           │  │         Private Subnets            │ │   │
│  │  │  10.0.1.0/24  10.0.2.0/24   │  │   10.0.3.0/24    10.0.4.0/24      │ │   │
│  │  │  us-east-1a   us-east-1b    │  │   us-east-1a     us-east-1b       │ │   │
│  │  │                             │  │                                    │ │   │
│  │  │  ┌───────────────────────┐  │  │  ┌──────────────────────────────┐ │ │   │
│  │  │  │  Network Load         │  │  │  │    EKS Managed Node Group    │ │ │   │
│  │  │  │  Balancer             │──┼──┼─▶│    4 × t3.medium             │ │ │   │
│  │  │  │  (created by Traefik  │  │  │  │    min:2  desired:4  max:5   │ │ │   │
│  │  │  │   LoadBalancer svc)   │  │  │  │                              │ │ │   │
│  │  │  └───────────────────────┘  │  │  │  ┌─────────┐  ┌──────────┐  │ │ │   │
│  │  │                             │  │  │  │ Node 1  │  │ Node 2   │  │ │ │   │
│  │  │  ┌───────────────────────┐  │  │  │  │         │  │          │  │ │ │   │
│  │  │  │  NAT Gateway          │  │  │  │  │ [pods]  │  │ [pods]   │  │ │ │   │
│  │  │  │  (Elastic IP)         │◀─┼──┼──│  └─────────┘  └──────────┘  │ │ │   │
│  │  │  │  outbound internet    │  │  │  │                              │ │ │   │
│  │  │  └──────────┬────────────┘  │  │  └──────────────────────────────┘ │ │   │
│  │  │             │               │  │                                    │ │   │
│  │  │  ┌──────────▼────────────┐  │  │  ┌──────────────────────────────┐ │ │   │
│  │  │  │  Internet Gateway     │  │  │  │  RDS PostgreSQL               │ │ │   │
│  │  │  └───────────────────────┘  │  │  │  db.t3.micro                  │ │ │   │
│  │  └──────────────────────────┬──┘  │  │  cloudmart DB                 │ │ │   │
│  │                             │     │  └──────────────────────────────┘ │ │   │
│  │                        Internet   │                                    │ │   │
│  │                                   │  ┌──────────────────────────────┐ │ │   │
│  │                                   │  │  ElastiCache Redis            │ │ │   │
│  │                                   │  │  cache.t3.micro               │ │ │   │
│  │                                   │  └──────────────────────────────┘ │ │   │
│  │                                   └────────────────────────────────────┘ │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Subnet design

| Subnet | CIDR | What lives here | Internet access |
|--------|------|-----------------|-----------------|
| Public 1a | 10.0.1.0/24 | NLB, NAT Gateway | Direct via Internet Gateway |
| Public 1b | 10.0.2.0/24 | NLB, NAT Gateway (AZ-B) | Direct via Internet Gateway |
| Private 1a | 10.0.3.0/24 | EKS nodes, RDS, Redis | Outbound only via NAT Gateway |
| Private 1b | 10.0.4.0/24 | EKS nodes, RDS, Redis | Outbound only via NAT Gateway |

**Why private subnets for nodes?** EKS nodes, RDS, and ElastiCache have no public IPs. They are completely unreachable from the internet. Traffic can only reach them via the NLB → Traefik path. This is the standard production security posture.

**Why two AZs?** Every subnet is mirrored across `us-east-1a` and `us-east-1b`. If one AZ goes down, the NLB routes to the surviving AZ and the cluster keeps running.

---

## Network Traffic Flow

### Inbound — User visiting the site

```
User Browser
    │  HTTPS tulunad.click
    ▼
Route 53  ──resolves to NLB──▶  Network Load Balancer  (public subnet)
                                        │
                                        │  forwards to NodePort
                                        ▼
                               Traefik Ingress  (cloudmart namespace)
                                        │
                    ┌───────────────────┼───────────────────┐
                    │                   │                   │
             PathPrefix(/api/auth)  PathPrefix(/api)   everything else
             priority: 20           priority: 10        priority: 5
                    │                   │                   │
                    ▼                   ▼                   ▼
              frontend:3000      api-gateway:3000     frontend:3000
            (NextAuth OAuth)
```

The `/api/auth` rule has higher priority than `/api` so NextAuth OAuth callbacks go to the frontend, not the api-gateway. Without this, Google OAuth would 404.

### Outbound — Pods reaching the internet

```
Pod  (private subnet — no public IP)
    │
    ▼
NAT Gateway  (public subnet — has Elastic IP)
    │
    ▼
Internet
    ├── ghcr.io                   pull container images
    ├── github.com                ArgoCD pulls this repo every 3 min
    ├── acme-v02.api.letsencrypt  cert-manager gets TLS certificates
    └── *.amazonaws.com           Secrets Manager API, EKS control plane
```

**Why NAT Gateway and not just the Load Balancer?**
The Load Balancer only handles inbound traffic — it's a receiver. It has no ability to forward outbound requests from pods. The NAT Gateway handles the opposite direction: pods sending requests out.

---

## API Interaction Map

How every component talks to every other component at runtime:

```
  EXTERNAL
  ─────────────────────────────────────────────────────────────────────
  Browser  ──HTTPS──▶  Route 53  ──DNS──▶  NLB  ──TCP──▶  Traefik

  INGRESS ROUTING  (Traefik — IngressRoute rules)
  ─────────────────────────────────────────────────────────────────────
  tulunad.click/api/auth/*   priority 20  ──▶  frontend:3000
  tulunad.click/api/*        priority 10  ──▶  api-gateway:3000
  tulunad.click/*            priority  5  ──▶  frontend:3000
  http://tulunad.click       redirect 301 ──▶  https://tulunad.click

  INTERNAL SERVICE CALLS  (all within cloudmart namespace)
  ─────────────────────────────────────────────────────────────────────
  frontend          ──HTTP GET /api/products──▶  api-gateway:3000
  frontend          ──HTTP POST /api/orders──▶   api-gateway:3000
  api-gateway       ──HTTP proxy──▶  product-service:8000/products/*
  api-gateway       ──HTTP proxy──▶  order-service:3001/orders/*
  product-service   ──asyncpg──▶  RDS PostgreSQL:5432
  order-service     ──ioredis──▶  ElastiCache Redis:6379
  order-service     ──KafkaJS──▶  Kafka broker:9092  (topic: order.created)

  SECRET INJECTION  (at pod startup)
  ─────────────────────────────────────────────────────────────────────
  AWS Secrets Manager  ◀──IRSA──  External Secrets Operator
  External Secrets Operator  ──creates──▶  K8s Secrets
  K8s Secrets  ──envFrom──▶  product-service pod  (DATABASE_URL)
  K8s Secrets  ──envFrom──▶  order-service pod   (REDIS_HOST, KAFKA_BROKERS)
  K8s Secrets  ──envFrom──▶  frontend pod         (GOOGLE_CLIENT_ID, NEXTAUTH_SECRET)
  K8s Secrets  ──imagePullSecret──▶  all pods     (GHCR auth)

  PLATFORM COMPONENTS
  ─────────────────────────────────────────────────────────────────────
  ArgoCD       ──git poll──▶  github.com/Nidhi-S12/cloudmart-gitops
  ArgoCD       ──kubectl apply──▶  cluster (on diff detected)
  cert-manager ──ACME DNS-01──▶  Let's Encrypt API
  cert-manager ──Route53 API──▶  creates TXT record for domain validation
  Prometheus   ──scrape /metrics──▶  all pods (every 15s)
  Grafana      ──PromQL──▶  Prometheus
  Grafana      ──LogQL──▶   Loki
  Loki         ──tail logs──▶  all pods
```

## Kubernetes Platform Stack

All installed by `infrastructure/setup.sh` in dependency order:

| Component | Namespace | Why it's here |
|-----------|-----------|---------------|
| **Metrics Server** | kube-system | Provides real-time CPU/memory metrics — required for HPA to function |
| **Traefik** | cloudmart | Ingress controller. Receives all external traffic and routes it to the right service. Also terminates TLS. |
| **Strimzi** | cloudmart | Kafka operator. Manages the Kafka cluster used by order-service for event streaming. |
| **ArgoCD** | argocd | GitOps engine. Watches this repo and automatically applies any changes to the cluster. |
| **Prometheus + Grafana** | monitoring | Prometheus scrapes metrics from all pods. Grafana visualises them with dashboards. |
| **Loki** | monitoring | Log aggregation. All pod logs are collected and queryable from Grafana. |
| **Kyverno** | kyverno | Policy engine. Enforces rules like "no latest image tags" and "containers must not run as root". |
| **cert-manager** | cert-manager | Automatically provisions TLS certificates from Let's Encrypt using DNS-01 challenge via Route 53. |
| **External Secrets Operator** | cloudmart | Syncs secrets from AWS Secrets Manager into Kubernetes Secrets. Runs as a pod — no hardcoded AWS keys. |

---

## Application Services

```
                         ┌──────────────────┐
                         │    Frontend      │
                         │   (Next.js 14)   │
                         │   port 3000      │
                         └────────┬─────────┘
                                  │  all /api/* requests
                                  ▼
                        ┌──────────────────────┐
                        │     API Gateway       │
                        │     (Node.js)         │
                        │     port 3000         │
                        └──────────┬────────────┘
                                   │
             ┌─────────────────────┴──────────────────────┐
             │                                            │
             │ /api/products/*                            │ /api/orders/*
             ▼                                            ▼
  ┌──────────────────────┐                  ┌──────────────────────────┐
  │   Product Service    │                  │      Order Service        │
  │   (FastAPI / Python) │                  │      (Node.js)            │
  │   port 8000          │                  │      port 3001            │
  └──────────┬───────────┘                  └────────────┬─────────────┘
             │                                           │
             ▼                                      ┌────┴──────┐
  ┌──────────────────────┐                          │           │
  │  RDS PostgreSQL      │                          ▼           ▼
  │  (product catalogue) │               ElastiCache      Kafka Topic
  └──────────────────────┘               Redis             order.created
                                         (order store)     (event stream)
```

| Service | Language | Responsibility |
|---------|----------|---------------|
| **frontend** | Next.js 14 (App Router) | Product browsing, cart, Google OAuth login, order history |
| **api-gateway** | Node.js / Express | Single entry point for all API calls — proxies to the right backend service |
| **product-service** | Python / FastAPI | Product catalogue with category filtering and search. Backed by PostgreSQL. |
| **order-service** | Node.js / Express | Creates orders, stores them in Redis with 24h TTL, publishes `order.created` events to Kafka |

---

## GitOps Deployment Flow

```
Developer pushes code to cloudmart-services or cloudmart-frontend
            │
            ▼
    GitHub Actions CI
    ├── Gitleaks     — scans for accidentally committed secrets
    ├── Semgrep      — static analysis (OWASP top 10, language-specific rules)
    ├── Trivy        — scans dependencies and filesystem for CVEs
    ├── Docker build — multi-stage, minimal final image
    ├── Docker push  — ghcr.io/nidhi-s12/cloudmart/<service>:sha-<7-char-commit>
    └── Kustomize edit set image  — updates newTag in kustomization.yaml
            │
            ▼  git commit + push to cloudmart-gitops
    cloudmart-gitops  environments/production/kustomization.yaml updated
            │
            ▼
    ArgoCD polls repo every 3 minutes, detects the new tag
            │
            ▼
    ArgoCD applies updated Deployment to EKS
            │
            ▼
    Kubernetes rolling update — new pods start before old ones stop
                                zero-downtime deployment
```

Images are tagged with the short git SHA (`sha-abc1234`) not `latest`. This means every deployment is traceable to an exact commit and can be rolled back by changing the tag.

---

## Secrets Flow

Sensitive values (database URLs, API keys, OAuth secrets) are never stored in git. The flow:

```
AWS Secrets Manager
  cloudmart/product-service   →  database-url
  cloudmart/order-service     →  redis-host, kafka-brokers
  cloudmart/ghcr-pull         →  ghcr-token  (GHCR image pull)
  cloudmart/google-oauth      →  client-id, client-secret, nextauth-secret
          │
          │  IRSA — pod gets AWS permissions via K8s ServiceAccount
          │  No AWS access keys stored anywhere in the cluster
          ▼
  External Secrets Operator
  reads from Secrets Manager and creates K8s Secrets
          │
          ▼
  Kubernetes Secrets  (in cloudmart namespace)
          │
          ▼
  Pod env vars  (mounted via envFrom / secretRef)
```

**IRSA (IAM Roles for Service Accounts)** — Instead of giving the ESO pod an AWS access key, we annotate its ServiceAccount with an IAM role ARN. AWS OIDC federation trusts that ServiceAccount and issues temporary credentials automatically. No long-lived keys anywhere.

---

## TLS Certificate Flow

```
cert-manager reads the Certificate resource
        │
        ▼
Sends ACME certificate request to Let's Encrypt
        │
        ▼
Let's Encrypt issues DNS-01 challenge:
  "Create TXT record _acme-challenge.tulunad.click"
        │
        ▼
cert-manager creates the TXT record in Route 53  (using IRSA)
        │
        ▼
Let's Encrypt verifies the record → issues the certificate
        │
        ▼
cert-manager stores the certificate in a K8s Secret
        │
        ▼
Traefik reads the Secret and serves HTTPS
```

**Why DNS-01 and not HTTP-01?** DNS-01 proves domain ownership without needing the cluster to be publicly reachable. This means certificates can be provisioned even if the NLB isn't set up yet.

---

## Autoscaling

All 4 services have a HorizontalPodAutoscaler backed by Metrics Server:

| Service | Min pods | Max pods | Scale trigger |
|---------|----------|----------|---------------|
| frontend | 1 | 4 | CPU > 70% or Memory > 80% |
| api-gateway | 1 | 4 | CPU > 70% or Memory > 80% |
| product-service | 1 | 4 | CPU > 70% or Memory > 80% |
| order-service | 1 | 4 | CPU > 70% or Memory > 80% |

Scale-down has a 5-minute stabilisation window to avoid flapping during bursty traffic.

---

## Policy Enforcement (Kyverno)

Four policies run in Audit mode across all pods:

| Policy | Rule |
|--------|------|
| `disallow-latest-tag` | Image tag must be pinned (e.g. `sha-abc1234`) — `latest` is non-deterministic |
| `disallow-root-user` | Containers must run as a non-root user |
| `require-probes` | Liveness and readiness probes must be defined |
| `require-resource-limits` | CPU and memory limits must be set — prevents noisy-neighbour issues |

---

## Monitoring & Alerting

**Grafana** includes dashboards for:
- Kubernetes cluster overview (CPU, memory, pod counts)
- Per-pod resource usage
- Loki log explorer

**Prometheus alert rules** (`infrastructure/monitoring/alert-rules.yaml`):

| Alert | Fires when |
|-------|-----------|
| `PodCrashLooping` | Any pod is in CrashLoopBackOff |
| `PodImagePullFailed` | Any pod is in ImagePullBackOff |
| `HighCPUUsage` | Pod CPU > 85% for 5 minutes |
| `HighMemoryUsage` | Pod memory > 90% for 5 minutes |
| `HPAAtMaxReplicas` | Any HPA is at its replica ceiling (can't scale further) |
| `HPAScalingLimited` | HPA wants to scale but is being throttled |
| `KafkaUnderReplicatedPartitions` | Kafka partition has fewer replicas than expected |
| `KafkaConsumerGroupLag` | Consumer group is falling behind on messages |

---

## Repo Structure

```
cloudmart-gitops/
│
├── terraform/
│   ├── environments/production/    # Root module — wires all modules together
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   └── terraform.tfvars        # NOT in git — contains db_password
│   └── modules/
│       ├── vpc/                    # VPC, subnets, IGW, NAT, route tables
│       ├── eks/                    # EKS cluster + managed node group
│       ├── rds/                    # PostgreSQL (private subnet)
│       ├── elasticache/            # Redis (private subnet)
│       └── s3/                     # S3 bucket
│
├── base/                           # K8s manifests — environment-agnostic
│   ├── frontend/                   # Deployment, Service, HPA
│   ├── api-gateway/
│   ├── product-service/
│   ├── order-service/
│   ├── kafka/                      # Strimzi KafkaNodePool + Kafka CRs
│   └── external-secrets/           # SecretStore + ExternalSecrets
│
├── environments/
│   ├── production/                 # Kustomize overlay — pinned image tags
│   │   ├── kustomization.yaml      # Updated by CI on every deploy
│   │   └── patches/                # Env vars, resource overrides
│   └── local/                      # Kustomize overlay — local dev
│
├── argocd/apps/
│   └── services/cloudmart-production.yaml   # ArgoCD Application
│
└── infrastructure/
    ├── setup.sh                    # Full cluster bootstrap (run once after terraform apply)
    ├── cert-manager/               # ClusterIssuer, Certificate
    ├── ingress/                    # Subdomain IngressRoutes
    ├── traefik/values.yaml
    ├── kafka/values.yaml
    ├── kyverno/                    # 4 policy files
    └── monitoring/                 # prometheus-values.yaml, loki-values.yaml, alert-rules.yaml
```

---

## Spinning Up the Cluster

### Prerequisites

- AWS CLI configured
- Terraform ≥ 1.5, kubectl, helm, kustomize
- Domain in Route 53 with a hosted zone

### 1 — Provision AWS infrastructure

```bash
cd terraform/environments/production
echo 'db_password = "YourSecurePassword"' > terraform.tfvars
terraform init
terraform apply
```

### 2 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name cloudmart-production
```

### 3 — Create secrets in AWS Secrets Manager

```bash
# Use RDS and ElastiCache endpoints from: terraform output

aws secretsmanager create-secret --name cloudmart/product-service --region us-east-1 \
  --secret-string '{"database-url":"postgresql+asyncpg://cloudmart:<password>@<rds-endpoint>:5432/cloudmart"}'

aws secretsmanager create-secret --name cloudmart/order-service --region us-east-1 \
  --secret-string '{"redis-host":"<elasticache-endpoint>","kafka-brokers":"cloudmart-kafka-kafka-bootstrap.cloudmart.svc.cluster.local:9092"}'

aws secretsmanager create-secret --name cloudmart/ghcr-pull --region us-east-1 \
  --secret-string '{"ghcr-token":"<github-pat>"}'

aws secretsmanager create-secret --name cloudmart/google-oauth --region us-east-1 \
  --secret-string '{"client-id":"<id>","client-secret":"<secret>","nextauth-secret":"<random-32-chars>"}'
```

### 4 — Bootstrap the cluster

```bash
cd infrastructure/
./setup.sh
```

### Tear Down

```bash
cd terraform/environments/production
terraform destroy

# Then manually delete secrets (not managed by Terraform):
for secret in cloudmart/product-service cloudmart/order-service cloudmart/ghcr-pull cloudmart/google-oauth; do
  aws secretsmanager delete-secret --secret-id $secret --region us-east-1 --force-delete-without-recovery
done
```

---

## Accessing Services

```bash
# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# → http://localhost:3000  (admin / cloudmart123)

# ArgoCD
kubectl port-forward svc/argocd-server 8080:80 -n argocd
# → http://localhost:8080  (admin / get password below)
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# → http://localhost:9090
```
