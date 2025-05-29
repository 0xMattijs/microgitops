# Minimal GitOps-Driven Kubernetes System for DigitalOcean

A bootstrappable, self-contained, GitOps-driven Kubernetes system that can be deployed and fully restored on a single DigitalOcean droplet using only a GitHub token and a DigitalOcean API token.

## Features

- 🚀 **Single-Command Bootstrap**: Deploy a complete Kubernetes cluster with one command
- 🔄 **GitOps-Driven**: ArgoCD for declarative infrastructure and application management
- 💾 **Persistent Storage**: Dynamic volume provisioning via DigitalOcean CSI driver
- 📦 **Backup & Restore**: Full snapshot and restore capability using cloud object storage
- 📈 **Scalable**: Support for both vertical (bigger droplet) and horizontal (additional nodes) scaling
- 🔒 **Secure**: Minimal cost footprint with secure secret management

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/0xMattijs/microgitops.git
   cd microgitops
   ```

2. Create a `.env` file with your credentials:
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

   # Optional: Install DigitalOcean CSI driver
   INSTALL_CSI_DRIVER="true"
   ```

3. Run the bootstrap script:
   ```bash
   ./bootstrap.sh
   ```

4. Access your cluster:
   - Kubernetes: `kubectl get nodes`
   - ArgoCD UI: `http://<droplet-ip>:30080` (admin / password from secret)

## Components

- **Kubernetes**: K3s (upgradable to full HA setup)
- **GitOps**: ArgoCD with "App of Apps" pattern
- **Storage**: DigitalOcean CSI driver for dynamic volume provisioning
- **Backup**: Velero with S3-compatible storage (Spaces, B2, Wasabi)
- **Ingress**: Traefik (default) or NGINX

## Documentation

- [Setup & Bootstrap Guide](docs/documentation.md#setup--bootstrap)
- [Restore Procedure](docs/documentation.md#restore-procedure)
- [Scaling Guide](docs/documentation.md#scaling-guide)
- [Security & Secrets](docs/documentation.md#security--secrets-handling)
- [Troubleshooting](docs/documentation.md#troubleshooting)
- [Storage Management](docs/documentation.md#storage)

## Requirements

- GitHub account with personal access token
- DigitalOcean account with API token
- `doctl` CLI installed
- External S3-compatible storage (e.g., DigitalOcean Spaces)

## Architecture

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
├── bootstrap.sh
└── README.md
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 