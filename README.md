# cloudmart-gitops

GitOps repository for CloudMart — ArgoCD watches this repo and deploys all services.

## Structure

| Folder | Purpose |
|---|---|
| `argocd/apps/` | App-of-Apps pattern — one ArgoCD Application manifest per service |
| `base/` | Base Kubernetes manifests shared across all environments |
| `environments/local/` | Kustomize overlay for Docker Desktop Kubernetes (local dev) |
| `environments/production/` | Kustomize overlay for AWS EKS (production) |
| `infrastructure/` | Cluster-wide tools: Traefik, Kafka, Prometheus, Cert-Manager |
| `terraform/` | AWS infrastructure code — applied only at final demo |

## How GitOps works here

1. ArgoCD is installed on the cluster and pointed at this repo
2. `argocd/apps/root-app.yaml` is the single app you register manually — the "root"
3. The root app discovers all other apps in `argocd/apps/` automatically (App-of-Apps)
4. Any `git push` to this repo triggers ArgoCD to sync the cluster to match
