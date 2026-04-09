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

```mermaid
flowchart TD
    Internet((Internet))
    R53["Route 53\ntulunad.click"]
    SM["AWS Secrets Manager"]

    subgraph VPC["VPC — 10.0.0.0/16  (us-east-1)"]
        subgraph Public["Public Subnets  10.0.1-2.0/24  |  us-east-1a & 1b"]
            NLB["Network Load Balancer"]
            NAT["NAT Gateway\nElastic IP"]
            IGW["Internet Gateway"]
        end

        subgraph Private["Private Subnets  10.0.3-4.0/24  |  us-east-1a & 1b"]
            subgraph EKS["EKS Node Group  —  4 × t3.medium"]
                Traefik["Traefik\nIngress Controller"]
                FE["frontend :3000"]
                GW["api-gateway :3000"]
                PS["product-service :8000"]
                OS["order-service :3001"]
                ESO["External Secrets Operator"]
                ArgoCD["ArgoCD"]
            end
            RDS[("RDS PostgreSQL\ndb.t3.micro")]
            Redis[("ElastiCache Redis\ncache.t3.micro")]
        end
    end

    Internet -->|DNS query| R53
    R53 -->|resolves to| NLB
    NLB -->|forwards traffic| Traefik
    Private -->|outbound via| NAT
    NAT --> IGW
    IGW --> Internet

    ESO -->|IRSA — no keys stored| SM

    PS --> RDS
    OS --> Redis
```

### Subnet design

| Subnet | CIDR | What lives here | Internet access |
|--------|------|-----------------|-----------------|
| Public 1a/1b | 10.0.1-2.0/24 | NLB, NAT Gateway | Direct via Internet Gateway |
| Private 1a/1b | 10.0.3-4.0/24 | EKS nodes, RDS, ElastiCache | Outbound only via NAT |

**Why private subnets?** Nodes, RDS, and ElastiCache have no public IPs — completely unreachable from the internet directly. Traffic reaches pods only via NLB → Traefik.

**Why two AZs?** Subnets are mirrored across `us-east-1a` and `us-east-1b`. If one AZ goes down the cluster keeps running.

---

## Network Traffic Flow

### Inbound — user visiting the site

```mermaid
flowchart TD
    User(["👤 User Browser\nhttps://tulunad.click"])
    R53["Route 53\nDNS lookup"]
    NLB["Network Load Balancer\npublic subnet"]
    Traefik["Traefik Ingress\ncloudmart namespace"]
    FE["frontend :3000\nNext.js"]
    GW["api-gateway :3000"]

    User -->|HTTPS| R53
    R53 -->|resolves to NLB IP| NLB
    NLB -->|NodePort| Traefik

    Traefik -->|"PathPrefix /api/auth  priority 20"| FE
    Traefik -->|"PathPrefix /api  priority 10"| GW
    Traefik -->|"catch-all  priority 5"| FE
```

> The `/api/auth` rule has higher priority than `/api` so NextAuth OAuth callbacks always reach the frontend, not the api-gateway. Without this, Google sign-in returns 404.

### Outbound — pods reaching the internet

```mermaid
flowchart LR
    subgraph Private["Private Subnet (no public IP)"]
        Pods["Pods"]
    end
    subgraph Public["Public Subnet"]
        NAT["NAT Gateway\nElastic IP"]
    end

    Pods --> NAT
    NAT -->|ghcr.io| GHCR["GHCR\nImage Registry"]
    NAT -->|github.com| GitHub["GitHub\nArgoCD pulls gitops repo"]
    NAT -->|letsencrypt.org| LE["Let's Encrypt\ncert-manager"]
    NAT -->|"*.amazonaws.com"| AWS["AWS APIs\nSecrets Manager, EKS control plane"]
```

---

## API Interaction Map

```mermaid
flowchart LR
    Browser(["Browser"])

    subgraph K8s["Kubernetes — cloudmart namespace"]
        Traefik["Traefik"]
        FE["frontend"]
        GW["api-gateway"]
        PS["product-service"]
        OS["order-service"]
        ESO["External Secrets\nOperator"]
        ArgoCD["ArgoCD"]
        CM["cert-manager"]
        Prom["Prometheus"]
        Loki["Loki"]
    end

    subgraph AWS["AWS"]
        NLB["NLB"]
        SM["Secrets Manager"]
        R53["Route 53"]
        LE["Let's Encrypt"]
    end

    subgraph Data["Data Stores"]
        RDS[("RDS\nPostgreSQL")]
        Redis[("Redis\nElastiCache")]
        Kafka[("Kafka\nStrimzi")]
    end

    GitHub["GitHub\ncloudmart-gitops"]

    Browser --> NLB --> Traefik
    Traefik -->|"/ and /api/auth"| FE
    Traefik -->|"/api/*"| GW
    FE -->|HTTP| GW
    GW -->|"/products/*"| PS
    GW -->|"/orders/*"| OS
    PS --> RDS
    OS --> Redis
    OS --> Kafka

    ESO -->|IRSA| SM
    SM -->|K8s Secrets| FE
    SM -->|K8s Secrets| PS
    SM -->|K8s Secrets| OS

    ArgoCD -->|polls every 3 min| GitHub
    CM -->|DNS-01 challenge| R53
    CM -->|ACME| LE
    Prom -->|scrapes /metrics| FE
    Prom -->|scrapes /metrics| GW
    Prom -->|scrapes /metrics| PS
    Prom -->|scrapes /metrics| OS
    Loki -->|tails logs| K8s
```

---

## GitOps Deployment Flow

```mermaid
flowchart TD
    Push["git push\ncloudmart-services or cloudmart-frontend"]

    subgraph CI["GitHub Actions CI"]
        Gitleaks["Gitleaks\nsecrets scan"]
        Semgrep["Semgrep\nSAST"]
        Trivy1["Trivy\ndependency scan"]
        Build["docker build\nmulti-stage"]
        Push2["docker push\nghcr.io/nidhi-s12/cloudmart/service:sha-abc1234"]
        Trivy2["Trivy\nimage scan"]
        Kustomize["kustomize edit set image\nupdate tag in gitops repo"]
    end

    ArgoCD["ArgoCD\ndetects diff in repo"]
    K8s["Kubernetes\nrolling update — zero downtime"]

    Push --> Gitleaks
    Push --> Semgrep
    Push --> Trivy1
    Gitleaks -->|pass| Build
    Semgrep -->|pass| Build
    Trivy1 -->|pass| Build
    Build --> Push2
    Push2 --> Trivy2
    Trivy2 --> Kustomize
    Kustomize -->|git push to cloudmart-gitops| ArgoCD
    ArgoCD -->|kubectl apply| K8s
```

---

## Secrets Flow

```mermaid
flowchart LR
    subgraph SM["AWS Secrets Manager"]
        S1["cloudmart/product-service\ndatabase-url"]
        S2["cloudmart/order-service\nredis-host, kafka-brokers"]
        S3["cloudmart/ghcr-pull\nghcr-token"]
        S4["cloudmart/google-oauth\nclient-id, client-secret, nextauth-secret"]
    end

    ESO["External Secrets Operator\n(uses IRSA — no AWS keys stored)"]

    subgraph KSec["Kubernetes Secrets"]
        KS1["product-service-secret"]
        KS2["order-service-secret"]
        KS3["ghcr-pull-secret"]
        KS4["frontend-oauth-secret"]
    end

    PS["product-service pod"]
    OS["order-service pod"]
    FE["frontend pod"]
    All["all pods\n(image pull)"]

    SM --> ESO
    ESO --> KSec
    KS1 -->|envFrom| PS
    KS2 -->|envFrom| OS
    KS4 -->|envFrom| FE
    KS3 -->|imagePullSecret| All
```

---

## TLS Certificate Flow

```mermaid
flowchart TD
    CM["cert-manager\nreads Certificate resource"]
    LE["Let's Encrypt\nACME server"]
    R53["Route 53\nDNS"]
    Secret["K8s Secret\ntls.crt + tls.key"]
    Traefik["Traefik\nserves HTTPS"]

    CM -->|"ACME DNS-01 challenge request"| LE
    LE -->|"prove ownership: create TXT record\n_acme-challenge.tulunad.click"| CM
    CM -->|"creates TXT record via IRSA"| R53
    R53 -->|"TXT record visible"| LE
    LE -->|"verified — issues certificate"| CM
    CM -->|"stores certificate"| Secret
    Secret -->|"TLS termination"| Traefik
```

> DNS-01 challenge is used instead of HTTP-01 because it works before the cluster is publicly reachable — cert-manager can provision the certificate during cluster bootstrap.

---

## Kubernetes Platform Stack

| Component | Namespace | Why it's here |
|-----------|-----------|---------------|
| **Metrics Server** | kube-system | Provides CPU/memory metrics — required for HPA to work |
| **Traefik** | cloudmart | Ingress controller — routes HTTPS traffic, terminates TLS |
| **Strimzi** | cloudmart | Kafka operator — manages the Kafka cluster for order events |
| **ArgoCD** | argocd | GitOps engine — watches this repo, applies changes to cluster |
| **Prometheus + Grafana** | monitoring | Metrics collection and dashboards |
| **Loki** | monitoring | Log aggregation — all pod logs queryable from Grafana |
| **Kyverno** | kyverno | Policy enforcement — no latest tags, no root containers |
| **cert-manager** | cert-manager | Auto-provisions and renews Let's Encrypt TLS certificates |
| **External Secrets Operator** | cloudmart | Syncs secrets from AWS Secrets Manager into K8s Secrets |

---

## Application Services

| Service | Language | Port | Backing store |
|---------|----------|------|---------------|
| frontend | Next.js 14 | 3000 | — |
| api-gateway | Node.js / Express | 3000 | — |
| product-service | Python / FastAPI | 8000 | RDS PostgreSQL |
| order-service | Node.js / Express | 3001 | ElastiCache Redis + Kafka |

---

## Autoscaling

All 4 services have a HorizontalPodAutoscaler backed by Metrics Server:

| Service | Min | Max | Scale trigger |
|---------|-----|-----|---------------|
| frontend | 1 | 4 | CPU > 70% or Memory > 80% |
| api-gateway | 1 | 4 | CPU > 70% or Memory > 80% |
| product-service | 1 | 4 | CPU > 70% or Memory > 80% |
| order-service | 1 | 4 | CPU > 70% or Memory > 80% |

Scale-down has a 5-minute stabilisation window to avoid flapping.

---

## Policy Enforcement (Kyverno)

| Policy | Rule |
|--------|------|
| `disallow-latest-tag` | Image tag must be pinned (e.g. `sha-abc1234`) — `latest` is non-deterministic |
| `disallow-root-user` | Containers must run as a non-root user |
| `require-probes` | Liveness and readiness probes must be defined |
| `require-resource-limits` | CPU and memory limits must be set |

---

## Monitoring & Alerting

| Alert | Fires when |
|-------|-----------|
| `PodCrashLooping` | Any pod is in CrashLoopBackOff |
| `PodImagePullFailed` | Any pod is in ImagePullBackOff |
| `HighCPUUsage` | Pod CPU > 85% for 5 minutes |
| `HighMemoryUsage` | Pod memory > 90% for 5 minutes |
| `HPAAtMaxReplicas` | Any HPA is at its replica ceiling |
| `HPAScalingLimited` | HPA wants to scale but is throttled |
| `KafkaUnderReplicatedPartitions` | Kafka partition has fewer replicas than expected |
| `KafkaConsumerGroupLag` | Consumer group is falling behind |

---

## Repo Structure

```
cloudmart-gitops/
├── terraform/
│   ├── environments/production/    # Root module
│   │   ├── main.tf                 # Wires all modules together
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars        # NOT in git — contains db_password
│   └── modules/
│       ├── vpc/                    # VPC, subnets, IGW, NAT, route tables
│       ├── eks/                    # EKS cluster + managed node group
│       ├── rds/                    # PostgreSQL (private subnet)
│       ├── elasticache/            # Redis (private subnet)
│       └── s3/
├── base/                           # K8s manifests — environment-agnostic
│   ├── frontend/                   # Deployment, Service, HPA
│   ├── api-gateway/
│   ├── product-service/
│   ├── order-service/
│   ├── kafka/                      # Strimzi KafkaNodePool + Kafka CRs
│   └── external-secrets/           # SecretStore + ExternalSecrets
├── environments/
│   ├── production/                 # Kustomize overlay — pinned image tags
│   │   ├── kustomization.yaml      # Updated by CI on every deploy
│   │   └── patches/
│   └── local/                      # Kustomize overlay — local dev
├── argocd/apps/
│   └── services/cloudmart-production.yaml
└── infrastructure/
    ├── setup.sh                    # Full cluster bootstrap script
    ├── cert-manager/
    ├── traefik/values.yaml
    ├── kafka/values.yaml
    ├── kyverno/
    └── monitoring/                 # prometheus-values.yaml, loki-values.yaml, alert-rules.yaml
```

---

## Spinning Up the Cluster

### Prerequisites
- AWS CLI configured, Terraform ≥ 1.5, kubectl, helm, kustomize
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

# Secrets are not managed by Terraform — delete manually:
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
# → http://localhost:8080
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# → http://localhost:9090
```
