# CloudMart GitOps

![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-326CE5?logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-Charts-0F1689?logo=helm&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

Infrastructure-as-Code and Kubernetes manifests for the CloudMart e-commerce platform. This repo is the single source of truth for everything running on AWS — from the VPC and EKS cluster to application deployments.

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
    classDef aws fill:#FF9900,stroke:#232F3E,color:#fff
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff
    classDef app fill:#059669,stroke:#065f46,color:#fff
    classDef db fill:#7C3AED,stroke:#4c1d95,color:#fff
    classDef ext fill:#475569,stroke:#1e293b,color:#fff

    Internet((Internet)):::ext
    R53["Route 53\nDNS"]:::aws
    SM["Secrets Manager"]:::aws

    subgraph VPC["VPC"]
        subgraph Public["Public Subnets — Multi-AZ"]
            NLB["Network Load Balancer"]:::aws
            NAT["NAT Gateway"]:::aws
            IGW["Internet Gateway"]:::aws
        end

        subgraph Private["Private Subnets — Multi-AZ"]
            subgraph EKS["EKS Node Group"]
                Traefik["Traefik\nIngress Controller"]:::k8s
                FE["frontend"]:::app
                GW["api-gateway"]:::app
                PS["product-service"]:::app
                OS["order-service"]:::app
                ESO["External Secrets\nOperator"]:::k8s
                ArgoCD["ArgoCD"]:::k8s
            end
            RDS[("RDS PostgreSQL")]:::db
            Redis[("ElastiCache Redis")]:::db
        end
    end

    Internet -->|DNS query| R53
    R53 -->|resolves to| NLB
    NLB -->|forwards traffic| Traefik
    Private -->|outbound requests| NAT
    NAT --> IGW
    IGW --> Internet
    ESO -->|IRSA — no keys stored| SM
    PS --> RDS
    OS --> Redis
```

### Subnet design

| Subnet | What lives here | Internet access |
|--------|-----------------|-----------------|
| Public (Multi-AZ) | NLB, NAT Gateway | Direct via Internet Gateway |
| Private (Multi-AZ) | EKS nodes, RDS, ElastiCache | Outbound only via NAT |

**Why private subnets?** Nodes, RDS, and ElastiCache have no public IPs — unreachable from the internet directly. Traffic reaches pods only via NLB → Traefik.

**Why two AZs?** Every resource is replicated across two availability zones. If one AZ goes down the cluster keeps running.

---

## Network Traffic Flow

### Inbound — user visiting the site

```mermaid
flowchart TD
    classDef aws fill:#FF9900,stroke:#232F3E,color:#fff
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff
    classDef app fill:#059669,stroke:#065f46,color:#fff
    classDef user fill:#F59E0B,stroke:#92400e,color:#fff

    User(["User Browser"]):::user
    R53["Route 53"]:::aws
    NLB["Network Load Balancer"]:::aws
    Traefik["Traefik Ingress"]:::k8s
    FE["frontend\nNext.js"]:::app
    GW["api-gateway"]:::app

    User -->|HTTPS| R53
    R53 -->|resolves to NLB| NLB
    NLB -->|NodePort| Traefik
    Traefik -->|"/api/auth  priority 20"| FE
    Traefik -->|"/api/*  priority 10"| GW
    Traefik -->|"all other routes  priority 5"| FE
```

> The `/api/auth` rule has higher priority than `/api` so NextAuth OAuth callbacks always reach the frontend, not the api-gateway. Without this, Google sign-in returns 404.

### Outbound — pods reaching the internet

```mermaid
flowchart LR
    classDef aws fill:#FF9900,stroke:#232F3E,color:#fff
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff
    classDef ext fill:#475569,stroke:#1e293b,color:#fff

    subgraph Private["Private Subnet — no public IP"]
        Pods["Pods"]:::k8s
    end
    subgraph Public["Public Subnet"]
        NAT["NAT Gateway"]:::aws
    end

    GHCR["Container Registry\nimage pulls"]:::ext
    GitHub["GitHub\nArgoCD git sync"]:::ext
    LE["Let's Encrypt\ncert-manager"]:::ext
    AWSAPI["AWS APIs\nSecrets Manager, EKS"]:::aws

    Pods --> NAT
    NAT --> GHCR
    NAT --> GitHub
    NAT --> LE
    NAT --> AWSAPI
```

---

## GitOps Deployment Flow

```mermaid
flowchart TD
    classDef git fill:#24292e,stroke:#000,color:#fff
    classDef sec fill:#EF4444,stroke:#991b1b,color:#fff
    classDef build fill:#0EA5E9,stroke:#0369a1,color:#fff
    classDef cd fill:#EF7B4D,stroke:#9a3412,color:#fff
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff

    Push["git push\nto services or frontend repo"]:::git

    subgraph CI["GitHub Actions CI"]
        Scans["Security Scans\nGitleaks · Semgrep · Trivy"]:::sec
        Tests["Unit Tests\nJest / pytest"]:::build
        Build["docker build\nmulti-stage"]:::build
        Publish["push image\ntagged with git SHA"]:::build
        ImageScan["Trivy image scan"]:::sec
        Update["kustomize edit set image\nupdate tag in gitops repo"]:::build
    end

    ArgoCD["ArgoCD\ndetects diff — auto sync"]:::cd
    K8s["Kubernetes\nrolling update — zero downtime"]:::k8s

    Push --> Scans
    Scans -->|all pass| Tests -->|all pass| Build --> Publish --> ImageScan --> Update
    Update -->|git push| ArgoCD
    ArgoCD -->|kubectl apply| K8s
```

---

## Secrets Flow

```mermaid
flowchart LR
    classDef aws fill:#FF9900,stroke:#232F3E,color:#fff
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff
    classDef app fill:#059669,stroke:#065f46,color:#fff

    subgraph SM["AWS Secrets Manager"]
        S1["product-service secret\ndatabase credentials"]:::aws
        S2["order-service secret\nredis + kafka config"]:::aws
        S3["image pull secret\ncontainer registry token"]:::aws
        S4["oauth secret\nGoogle client credentials"]:::aws
    end

    ESO["External Secrets Operator\nIRSA — no AWS keys in cluster"]:::k8s

    subgraph KSec["Kubernetes Secrets"]
        KS1["product-service-secret"]:::k8s
        KS2["order-service-secret"]:::k8s
        KS3["ghcr-pull-secret"]:::k8s
        KS4["frontend-oauth-secret"]:::k8s
    end

    PS["product-service"]:::app
    OS["order-service"]:::app
    FE["frontend"]:::app
    All["all pods"]:::app

    SM --> ESO --> KSec
    KS1 -->|envFrom| PS
    KS2 -->|envFrom| OS
    KS4 -->|envFrom| FE
    KS3 -->|imagePullSecret| All
```

---

## TLS Certificate Flow

```mermaid
flowchart TD
    classDef aws fill:#FF9900,stroke:#232F3E,color:#fff
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff
    classDef ext fill:#475569,stroke:#1e293b,color:#fff

    CM["cert-manager"]:::k8s
    LE["Let's Encrypt\nACME server"]:::ext
    R53["Route 53"]:::aws
    Secret["K8s TLS Secret"]:::k8s
    Traefik["Traefik\nserves HTTPS"]:::k8s

    CM -->|certificate request| LE
    LE -->|DNS-01 challenge\nprove domain ownership| CM
    CM -->|create DNS TXT record\nvia IRSA| R53
    R53 -->|record visible| LE
    LE -->|certificate issued| CM
    CM -->|store cert| Secret
    Secret -->|TLS termination| Traefik
```

> DNS-01 is used instead of HTTP-01 so the certificate can be provisioned during cluster bootstrap, before the cluster is publicly reachable.

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
| **Promtail** | monitoring | DaemonSet log shipper — collects pod logs, ships to Loki |
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

### Alert Delivery — SNS → Email

```mermaid
flowchart LR
    classDef k8s fill:#326CE5,stroke:#1a3a8f,color:#fff
    classDef aws fill:#FF9900,stroke:#232F3E,color:#fff
    classDef user fill:#F59E0B,stroke:#92400e,color:#fff

    Prom["Prometheus\nrule evaluation"]:::k8s
    AM["AlertManager\nrouting + grouping"]:::k8s
    SNS["SNS Topic\ncloudmart-production-alerts"]:::aws
    Email["Email subscriber"]:::user

    Prom -->|alert fires| AM
    AM -->|sns:Publish via IRSA| SNS
    SNS -->|SMTP fan-out| Email
```

AlertManager authenticates to SNS using **IRSA** — its ServiceAccount assumes the `cloudmart-alertmanager-sns` IAM role (scoped to `sns:Publish` on a single topic). No static AWS credentials anywhere.

On first deploy, AWS sends a confirmation email to the subscriber address; click the link to activate delivery. The email address is set via the `alert_email` Terraform variable (default: `nidhisnrao@gmail.com`).

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
│       ├── alerting/               # SNS topic + email subscription for AlertManager
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
    ├── setup.sh                    # Full cluster bootstrap — dynamic zone lookup, idempotent
    ├── create-hosted-zone.sh       # Creates Route53 zone + updates domain nameservers
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
- Domain registered in Route 53

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

### 3 — Create the Route 53 hosted zone

Terraform does not manage the hosted zone (it outlives the cluster). If this is a fresh setup or you've previously run `terraform destroy`, the hosted zone may not exist.

```bash
cd infrastructure/
./create-hosted-zone.sh
```

This script:
- Creates a hosted zone if one doesn't exist for the domain
- Compares nameservers with the domain registrar and updates them if they differ
- Is idempotent — safe to run multiple times

### 4 — Create secrets in AWS Secrets Manager

Secrets are **not** managed by Terraform or setup.sh — they must exist before the cluster can deploy apps. ESO (External Secrets Operator) syncs them into Kubernetes, but it can't create what doesn't exist in AWS.

```bash
# Use RDS and ElastiCache endpoints from: terraform output

aws secretsmanager create-secret --name cloudmart/product-service --region us-east-1 \
  --secret-string '{"database-url":"postgresql+asyncpg://cloudmart_admin:<password>@<rds-endpoint>:5432/cloudmart?ssl=require"}'

aws secretsmanager create-secret --name cloudmart/order-service --region us-east-1 \
  --secret-string '{"redis-host":"<elasticache-endpoint>","kafka-brokers":"kafka-kafka-bootstrap.cloudmart.svc.cluster.local:9092"}'

aws secretsmanager create-secret --name cloudmart/ghcr-pull --region us-east-1 \
  --secret-string '{"username":"<github-username>","password":"<github-pat>"}'

aws secretsmanager create-secret --name cloudmart/google-oauth --region us-east-1 \
  --secret-string '{"client-id":"<id>","client-secret":"<secret>","nextauth-secret":"<random-32-chars>"}'
```

> **Note:** The RDS master username is `cloudmart_admin` (set in Terraform), not `cloudmart`. The connection string must include `?ssl=require` for RDS. The Kafka broker name inside the cluster is `kafka-kafka-bootstrap` (not `cloudmart-kafka-kafka-bootstrap`).

### 5 — Bootstrap the cluster

```bash
cd infrastructure/
./setup.sh
```

`setup.sh` dynamically looks up the hosted zone ID from Route 53 — no hardcoded IDs. It installs all platform components, cleans up stale cert-manager challenges from previous runs, creates DNS records, and seeds the database.

### Tear Down

```bash
cd terraform/environments/production
terraform destroy

# Secrets are not managed by Terraform — delete manually:
for secret in cloudmart/product-service cloudmart/order-service cloudmart/ghcr-pull cloudmart/google-oauth; do
  aws secretsmanager delete-secret --secret-id $secret --region us-east-1 --force-delete-without-recovery
done
```

> **Note:** `terraform destroy` does **not** delete the Route 53 hosted zone (it's created separately). This is intentional — the zone and its nameserver delegation survive teardowns so you don't have to wait for DNS propagation on every rebuild.

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
