# Minimal GitOps-Driven Kubernetes System for DigitalOcean

## 1. Purpose

To deliver a **bootstrappable, self-contained, GitOps-driven Kubernetes system** that can be deployed and fully restored on a single DigitalOcean droplet using only:

* A GitHub token
* A DigitalOcean API token

The system should include:

* Kubernetes (K3s initially, scalable to full K8s HA setup)
* ArgoCD for GitOps
* S3-compatible object storage (external preferred)
* Dynamic volume provisioning via CSI
* Full snapshot and restore capability using cloud object storage
* Option to scale vertically (bigger droplet) and horizontally (additional nodes)

## 2. Scope

### In-Scope

* Bootstrap via a single script
* Kubernetes provisioning on a DigitalOcean droplet
* Installation and configuration of:

  * ArgoCD with "App of Apps" pattern
  * S3-compatible external storage for backups (Spaces, B2, Wasabi)
  * CSI driver (DigitalOcean CSI) for dynamic volume provisioning
* Initial usage of K3s SQLite, with upgrade path to HA etcd
* GitOps sync to a GitHub repo
* Snapshot and restore functionality using Velero and external S3
* Support vertical and horizontal scaling via restore/bootstrap

### Out-of-Scope

* Managed Kubernetes (e.g., DOKS)
* High availability from day one (but upgradable)
* Multi-region or hybrid cloud
* Manual configuration outside GitOps

## 3. Requirements

### 3.1 Functional Requirements

| ID  | Requirement                                                                 |
| --- | --------------------------------------------------------------------------- |
| F1  | The bootstrap script provisions a DO droplet and injects user-data.         |
| F2  | A DO block storage volume is provisioned and managed via CSI.               |
| F3  | K3s is installed and initialized (optionally upgraded to HA).               |
| F4  | ArgoCD is installed and bootstrapped with "App of Apps" Application.        |
| F5  | External S3-compatible storage (Spaces, Wasabi, etc.) is configured.        |
| F6  | Persistent volumes are dynamically provisioned via DigitalOcean CSI driver. |
| F7  | Velero is configured to snapshot cluster state and volumes to S3.           |
| F8  | System can be fully restored via bootstrap script using Velero.             |
| F9  | GitOps repo defines complete cluster state (infra, apps, config).           |
| F10 | System supports both scale-up (larger droplets) and scale-out (more nodes). |

### 3.2 Non-Functional Requirements

| ID | Requirement                                                         |
| -- | ------------------------------------------------------------------- |
| N1 | System must be fully reproducible and GitOps-driven.                |
| N2 | Bootstrap should run with only GitHub and DO tokens.                |
| N3 | Snapshots must survive full cluster wipe and allow full recovery.   |
| N4 | Minimized cost footprint (\$20/month target start).                 |
| N5 | Bootstrap must configure secrets securely (avoid plaintext in Git). |

## 4. Technical Design Overview

### 4.1 Bootstrap Script Responsibilities

* Inputs:

  * GitHub API token
  * DigitalOcean API token
* Steps:

  1. Generate and upload SSH keys (if not present)
  2. Create DO droplet with cloud-init/user-data
  3. Install K3s via user-data script
  4. Install ArgoCD and bootstrap Application via manifest
  5. Apply DigitalOcean CSI manifests and create required secrets
  6. Install Velero with S3 provider and DO snapshot plugin
  7. If restoring, perform Velero restore from snapshot

### 4.2 GitOps Repo Layout (Example)

```
.
├── clusters/
│   └── single-node/
│       ├── apps/
│       ├── csi-driver.yaml
│       ├── velero.yaml
│       └── ingress.yaml
├── applications/
│   └── app-of-apps.yaml
├── storage/
│   └── pvc.yaml
├── README.md
```

### 4.3 Snapshots

* Velero for backing up Kubernetes object state and volumes.
* Backup destination: external S3-compatible storage.
* DO API used for volume snapshot support.
* Scheduled and on-demand backups supported.

### 4.4 Restore Workflow

* Bootstrap script installs cluster, Velero, and restores from backup.
* K8s resources and volume data restored from S3 and snapshot location.
* Restore script accepts snapshot name or backup metadata.

### 4.5 Scalability

* **Scale-Up**: Resize droplet (manual or via script).
* **Scale-Out**: Provision new droplets and join via K3s token.
* Upgrade to HA via K3s embedded etcd + multiple control plane nodes.

## 5. Tech Stack

| Component          | Choice                     | Purpose                                 |
| ------------------ | -------------------------- | --------------------------------------- |
| Kubernetes         | K3s                        | Lightweight K8s, scalable to full HA    |
| GitOps             | ArgoCD                     | Declarative infra & app management      |
| Object Storage     | DO Spaces / B2 / Wasabi    | External S3 storage for Velero backups  |
| Volume Provisioner | DigitalOcean CSI Driver    | Dynamic PVs with DO Volumes             |
| Backup/Restore     | Velero + DO Plugin         | Cluster & volume snapshot/restore       |
| Ingress            | Traefik (default) or NGINX | Service ingress and TLS                 |
| Bootstrap Script   | Bash + doctl + cloud-init  | Full system install, restore, and scale |

## 6. Future Enhancements

* HA setup (K3s etcd cluster mode)
* DNS automation (Cloudflare integration)
* Secrets management via Sealed Secrets or Vault
* Monitoring/observability (Prometheus stack)
* GitHub Actions or CI/CD integration
* App-level RBAC and multi-tenancy

## 7. Risks & Mitigations

| Risk                         | Mitigation                              |
| ---------------------------- | --------------------------------------- |
| Droplet failure or data loss | Full snapshot + restore with Velero     |
| Secrets in plaintext         | Use sealed secrets / in-cluster Secrets |
| DO API rate limits           | Use retries and exponential backoff     |
| Manual restore complexity    | Automate with bootstrap restore mode    |
| Network or DNS downtime      | Use resilient DNS + monitoring setup    |

## 8. Deliverables

* `bootstrap.sh` – Provisioning and restore script
* GitHub GitOps repo with ArgoCD apps and manifests
* Velero snapshot/restore config
* CSI driver and storage class YAML
* Documentation:

  * Setup & bootstrap
  * Restore procedures
  * Scaling guide
  * Security & secrets handling
