# Documentation for Minimal GitOps-Driven Kubernetes System

## Setup & Bootstrap

### Prerequisites

* GitHub account with personal access token
* DigitalOcean account with API token
* `doctl` CLI installed
* SSH access setup (script generates SSH key)
* External S3-compatible storage (e.g., DigitalOcean Spaces)

### Bootstrap Methods

#### Option 1: Direct Installation (Recommended)

1. Create a `.env` file in your current directory:
   ```bash
   # GitHub Configuration
   GITHUB_USER="your-gh-username"
   GITHUB_TOKEN="your-gh-token"
   GITHUB_REPO="gitops-cluster"

   # DigitalOcean Configuration
   DO_TOKEN="your-do-token"
   DROPLET_NAME="gitops-node"
   DROPLET_SIZE="s-2vcpu-4gb"
   DROPLET_IMAGE="ubuntu-22-04-x64"
   DROPLET_REGION="ams3"
   SSH_KEY_NAME="gitops-ssh"

   # S3 Configuration
   S3_BUCKET="gitops-backup"
   S3_REGION="nyc3"
   S3_ENDPOINT="https://nyc3.digitaloceanspaces.com"

   # CSI Driver Configuration
   INSTALL_CSI_DRIVER="true"
   ```

2. Run the bootstrap script directly from GitHub:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/0xMattijs/microgitops/main/bootstrap.sh | bash
   ```

#### Option 2: Local Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/0xMattijs/microgitops.git
   cd microgitops
   ```

2. Create a `.env` file with your credentials (same as Option 1)

3. Run the bootstrap script:
   ```bash
   ./bootstrap.sh
   ```

### What the Script Does

1. Creates a new GitHub repository for your GitOps configuration
   - Initializes with basic Kubernetes manifests
   - Sets up GitHub Actions workflows
   - Configures branch protection

2. Sets up a DigitalOcean droplet with K3s
   - Installs latest stable K3s
   - Configures system security
   - Sets up networking

3. Installs and configures ArgoCD
   - Deploys ArgoCD server
   - Configures NodePort service
   - Sets up initial admin credentials

4. Creates necessary Kubernetes resources
   - Namespaces
   - Service accounts
   - RBAC rules
   - Network policies

5. Sets up S3 backup storage
   - Creates S3 bucket
   - Configures access keys
   - Sets up backup policies

6. Configures your local kubectl
   - Downloads kubeconfig
   - Updates server address
   - Sets up context

### Accessing Your Cluster

After the script completes:

1. Access the ArgoCD UI:
   ```
   http://<droplet-ip>:30080
   Username: admin
   Password: <displayed in script output>
   ```

2. Use kubectl:
   ```bash
   # Verify cluster access
   kubectl get nodes
   kubectl get pods -A
   
   # Check ArgoCD status
   kubectl get pods -n argocd
   kubectl get svc -n argocd
   ```

## Restore Procedure

### Prerequisites

* Snapshot tarball in S3 bucket
* Velero installed on new cluster
* DigitalOcean CSI driver installed (if using volume snapshots)

### Steps

1. Install Velero and configure S3 bucket:
   ```bash
   velero install \
     --provider aws \
     --plugins velero/velero-plugin-for-aws:v1.5.0 \
     --bucket $S3_BUCKET \
     --backup-location-config region=$S3_REGION,s3ForcePathStyle=true,s3Url=$S3_ENDPOINT \
     --secret-file ./credentials-velero
   ```

2. Download backup from S3:
   ```bash
   aws s3 cp s3://$S3_BUCKET/backups/<backup-name> ./backup.tar.gz
   ```

3. Run Velero restore:
   ```bash
   velero restore create --from-backup <backup-name>
   ```

4. Wait for pods to come back online:
   ```bash
   kubectl get pods -A -w
   ```

## Scaling Guide

### Scale-Up (Vertical)

1. Power off droplet:
   ```bash
   doctl compute droplet-action power-off <droplet-id>
   ```

2. Resize to larger plan:
   ```bash
   doctl compute droplet-action resize <droplet-id> --size <new-size>
   ```

3. Power on and verify:
   ```bash
   doctl compute droplet-action power-on <droplet-id>
   kubectl get nodes
   ```

### Scale-Out (Horizontal)

1. Create new DO droplet(s):
   ```bash
   doctl compute droplet create <new-node-name> \
     --size $DROPLET_SIZE \
     --image $DROPLET_IMAGE \
     --region $DROPLET_REGION \
     --ssh-keys $SSH_KEY_ID
   ```

2. Join node using K3s token:
   ```bash
   curl -sfL https://get.k3s.io | \
     K3S_URL=https://<main-node-ip>:6443 \
     K3S_TOKEN=<token> \
     sh -
   ```

3. Verify node addition:
   ```bash
   kubectl get nodes
   ```

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

## Storage

### DigitalOcean CSI Driver

The cluster uses the DigitalOcean CSI driver for dynamic volume provisioning. This allows you to:

1. Create persistent volumes on demand
2. Automatically provision block storage
3. Take volume snapshots
4. Expand volumes when needed

#### Storage Class

The default storage class `do-block-storage` is configured with:
- Filesystem: ext4
- Volume expansion: enabled
- Default class: yes

#### Creating a PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: do-block-storage
```

#### Taking a Snapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-snapshot
spec:
  volumeSnapshotClassName: do-block-storage-snapshot
  source:
    persistentVolumeClaimName: my-pvc
```

#### Restoring from Snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-restored-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: do-block-storage
  dataSource:
    name: my-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

#### Troubleshooting

1. Check CSI driver status:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-do-controller
   kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-do-node
   ```

2. Check storage class:
   ```bash
   kubectl get storageclass
   kubectl describe storageclass do-block-storage
   ```

3. Check PVC status:
   ```bash
   kubectl get pvc
   kubectl describe pvc <pvc-name>
   ```

4. Check volume snapshots:
   ```bash
   kubectl get volumesnapshot
   kubectl get volumesnapshotcontent
   ```

## Future Enhancements

* HA setup (K3s etcd cluster mode)
* DNS automation (Cloudflare integration)
* Secrets management via Sealed Secrets or Vault
* Monitoring/observability (Prometheus stack)
* GitHub Actions or CI/CD integration
* App-level RBAC and multi-tenancy

## Risks & Mitigations

| Risk                         | Mitigation                              |
| ---------------------------- | --------------------------------------- |
| Droplet failure or data loss | Full snapshot + restore with Velero     |
| Secrets in plaintext         | Use sealed secrets / in-cluster Secrets |
| DO API rate limits           | Use retries and exponential backoff     |
| Manual restore complexity    | Automate with bootstrap restore mode    |
| Network or DNS downtime      | Use resilient DNS + monitoring setup    |

---

This documentation is the operational guide for setting up, maintaining, and restoring the GitOps-based Kubernetes environment as defined in the project PRD.
