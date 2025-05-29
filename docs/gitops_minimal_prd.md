# Minimal GitOps-Driven Kubernetes System for DigitalOcean

## 1. Purpose

To deliver a **bootstrappable, self-contained, GitOps-driven Kubernetes system** that can be deployed and fully restored on a single DigitalOcean droplet using only:
- A GitHub token
- A DigitalOcean API token

The system should include:
- Kubernetes (virtualized or micro-distribution)
- ArgoCD for GitOps
- S3-compatible object storage
- Dynamic volume provisioning
- Full snapshot and restore capability using cloud object storage
- Scale-up and scale-out options via restore process

## 2. Scope

### In-Scope
- Bootstrap via a single script
- Kubernetes provisioning on a single DO droplet
- Installation and configuration of:
  - ArgoCD
  - S3-compatible storage (e.g., MinIO)
  - CSI driver for dynamic volume provisioning
- Networking configuration (ingress, DNS optional)
- GitOps sync to a specified GitHub repo
- Snapshot and restore functionality using S3-compatible storage
- Scalability (larger droplet or additional nodes using restore)

### Out-of-Scope
- Managed Kubernetes (e.g., DO Kubernetes)
- High availability
- Complex service meshes or multi-tenancy
- In-cluster app deployments beyond core infrastructure

## 3. Requirements

### 3.1 Functional Requirements

| ID  | Requirement                                                                 |
|-----|------------------------------------------------------------------------------|
| F1  | The bootstrap script provisions a DO droplet using the API token.           |
| F2  | A DO block storage volume is provisioned and attached to the droplet.       |
| F3  | Kubernetes (e.g., k3s or microk8s) is installed and configured.              |
| F4  | ArgoCD is installed and bootstraps the GitOps repository.                   |
| F5  | An S3-compatible object store (e.g., MinIO) is installed.                    |
| F6  | Persistent volumes are dynamically provisioned using a CSI plugin.          |
| F7  | System state can be snapshotted to S3-compatible storage.                   |
| F8  | System can be restored from snapshot via bootstrap script.                  |
| F9  | GitOps repo must define full cluster state (infra, config, volumes).        |
| F10 | Support scale-up and scale-out by re-running the bootstrap with options.    |

### 3.2 Non-Functional Requirements

| ID  | Requirement                                                                 |
|-----|------------------------------------------------------------------------------|
| N1  | Entire system must be reproducible and idempotent.                          |
| N2  | No manual SSH access or hand configuration post-bootstrap.                  |
| N3  | Snapshot/restore must not require live cluster access.                      |
| N4  | Script must work on Unix-like systems with only Git, Docker, and curl.      |

## 4. Technical Design Overview

### 4.1 Bootstrap Script Responsibilities

- **Inputs:**
  - GitHub API token (for GitOps repo)
  - DigitalOcean API token

- **Steps:**
  1. Create droplet (configurable size)
  2. Attach and mount block storage
  3. Install k3s (or microk8s)
  4. Install ArgoCD and sync GitOps repo
  5. Install MinIO and configure S3 endpoint
  6. Install CSI driver for DO Block Storage or hostPath for single-node
  7. Configure snapshot/restore tooling (Velero or custom rsync + S3)
  8. Bootstrap ArgoCD with apps (from Git repo)

### 4.2 GitOps Repo Layout (Example)

```
.
├── cluster/
│   ├── base/
│   ├── overlays/
│   └── argo-bootstrap.yaml
├── storage/
│   ├── minio/
│   └── csi-driver/
├── snapshot/
│   └── config/
├── README.md
```

### 4.3 Snapshots

- Use **Velero** or **custom tarball/rsync-based backup** to MinIO
- Store cluster manifests, PV data, and etcd snapshot
- Hook into bootstrap to check for and restore from snapshot

### 4.4 Restore Workflow

- Droplet boots
- Bootstrap script detects snapshot in S3
- Fetches and restores:
  - Volume data
  - etcd snapshot (if needed)
  - GitOps sync

### 4.5 Scalability

- **Scale-Up:** Bootstrap to larger droplet size (configurable)
- **Scale-Out:** Script provisions extra droplets and joins them to cluster (via restore logic + k3s token or kubeadm)

## 5. Tech Stack

| Component          | Choice                     | Purpose                               |
|-------------------|----------------------------|---------------------------------------|
| Kubernetes         | k3s                        | Lightweight K8s for single node       |
| GitOps             | ArgoCD                     | Declarative infra & app management    |
| Object Storage     | MinIO                      | S3-compatible, self-hosted            |
| Volume Provisioner | CSI + DO Block Storage     | Dynamic PVs                           |
| Backup/Snapshot    | Velero or rsync + MinIO    | Cluster state and volume backup       |
| IaC Scripting      | Bash + doctl + kubectl     | Minimal dependencies                  |

## 6. Future Enhancements

- Multi-node HA support
- DNS integration (e.g., with Cloudflare)
- Monitoring/Observability (Prometheus + Grafana)
- GitHub Actions-based GitOps automation
- Optional Tailscale/ZeroTier integration for secure admin access

## 7. Risks & Mitigations

| Risk                             | Mitigation                                      |
|----------------------------------|-------------------------------------------------|
| Droplet failure or data loss     | Full snapshot + restore capability              |
| Manual misconfiguration          | ArgoCD enforces desired state from Git          |
| Complexity in scale-out          | Keep single-node as default, add node script    |
| Storage cost from snapshot size  | Compress and deduplicate data                   |

## 8. Deliverables

- `bootstrap.sh` – The full provisioning and restore script
- GitHub template repository for ArgoCD configuration
- Documentation for:
  - Setup & bootstrap
  - Restore process
  - Customization
  - Scale operations
