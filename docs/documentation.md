# Documentation for Minimal GitOps-Driven Kubernetes System

## Setup & Bootstrap

### Prerequisites

* GitHub account with personal access token
* DigitalOcean account with API token
* `doctl` CLI installed
* SSH access setup (script generates SSH key)
* External S3-compatible storage (e.g., DigitalOcean Spaces)

### Bootstrap Steps

1. Clone the GitOps repo or use template
2. Set environment variables in `.env`:

   ```bash
   # GitHub Configuration
   GITHUB_USER="your-gh-username"
   GITHUB_TOKEN="your-gh-token"
   GITHUB_REPO="gitops-cluster"

   # DigitalOcean Configuration
   DO_TOKEN="your-do-token"
   DROPLET_NAME="gitops-node"
   DROPLET_SIZE="s-2vcpu-4gb"
   DROPLET_REGION="ams3"
   SSH_KEY_NAME="gitops-ssh"

   # S3 Configuration
   S3_BUCKET="gitops-backup"
   S3_REGION="nyc3"
   S3_ENDPOINT="https://nyc3.digitaloceanspaces.com"
   ```
3. Run bootstrap script:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/0xMattijs/microgitops/main/bootstrap.sh | bash
   ```
4. Wait for provisioning (~2–3 minutes)
5. Access K8s cluster via `kubectl` (kubeconfig will be automatically configured)
6. Access ArgoCD UI:

   ```
   http://<droplet-ip>:30080
   Username: admin
   Password: <retrieved from ArgoCD secret>
   ```

## Restore Procedure

### Prerequisites

* Snapshot tarball in S3 bucket
* Velero installed on new cluster

### Steps

1. Install Velero and configure S3 bucket
2. Download backup from S3
3. Run Velero restore:

   ```bash
   velero restore create --from-backup <backup-name>
   ```
4. Wait for pods to come back online

## Scaling Guide

### Scale-Up (Vertical)

1. Power off droplet
2. Resize to larger plan via DO control panel or API
3. Power on and verify with `kubectl get nodes`

### Scale-Out (Horizontal)

1. Create new DO droplet(s)
2. Join node using K3s token:

   ```bash
   curl -sfL https://get.k3s.io | K3S_URL=https://<main-node-ip>:6443 K3S_TOKEN=<token> sh -
   ```
3. Confirm with `kubectl get nodes`

## Security & Secrets Handling

### Recommendations

* Use Sealed Secrets or Vault for managing secrets
* Avoid hardcoding tokens in Git
* Use Kubernetes RBAC and Namespaces to isolate workloads
* Limit ArgoCD access with RBAC roles

### ArgoCD Secrets Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-creds
  namespace: argocd
stringData:
  type: git
  url: https://github.com/<your-username>/<your-repo>.git
  username: <your-username>
  password: <your-token>
type: Opaque
```

Apply using:

```bash
kubectl apply -f github-creds.yaml
```

## Troubleshooting

### Common Issues

1. **ArgoCD UI Not Accessible**
   - Verify the NodePort service is running: `kubectl get svc -n argocd argocd-server`
   - Check if port 30080 is open on the droplet
   - Ensure the service type is NodePort

2. **GitHub Authentication Issues**
   - Verify GitHub token has correct permissions
   - Check if the github-creds secret exists: `kubectl get secret -n argocd github-creds`
   - Ensure the repository URL is correct in the secret

3. **K3s Installation Issues**
   - Check system requirements
   - Verify network connectivity
   - Check logs: `journalctl -u k3s`

### Logs and Debugging

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# View ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Check service status
kubectl get svc -n argocd

# View K3s logs
journalctl -u k3s
```

---

This documentation is the operational guide for setting up, maintaining, and restoring the GitOps-based Kubernetes environment as defined in the project PRD.
