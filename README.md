# MicroGitOps

A minimal GitOps-driven Kubernetes system that sets up a K3s cluster with ArgoCD on DigitalOcean. This project provides a simple way to bootstrap a production-ready Kubernetes cluster with GitOps practices.

## Features

- 🚀 One-command cluster bootstrap
- 🔄 GitOps workflow with ArgoCD
- 🔒 Secure secret management
- 💾 S3-compatible backup storage
- 🔍 Built-in monitoring and logging
- 🔧 Easy scaling and maintenance

## TODO

### High Priority
- [ ] Implement DigitalOcean CSI driver for dynamic volume provisioning
- [ ] Add Velero for backup and restore functionality
- [ ] Set up proper secret management using Sealed Secrets
- [ ] Add support for cluster scaling (both vertical and horizontal)
- [ ] Implement proper error handling and retry mechanisms

### Medium Priority
- [ ] Add Prometheus stack for monitoring
- [ ] Implement logging solution (e.g., Loki)
- [ ] Add support for K3s HA mode
- [ ] Create comprehensive backup and restore documentation
- [ ] Add cost monitoring and optimization features

### Low Priority
- [ ] Add DNS automation (Cloudflare integration)
- [ ] Implement GitHub Actions workflows
- [ ] Add multi-tenancy support
- [ ] Create detailed troubleshooting guide
- [ ] Add performance benchmarking tools

## Quick Start

```bash
# Run the bootstrap script
curl -fsSL https://raw.githubusercontent.com/0xMattijs/microgitops/main/bootstrap.sh | bash
```

## Prerequisites

Before running the script, ensure you have:

1. A GitHub account with a personal access token
   - Required permissions: `repo`, `workflow`
   - [Create a token here](https://github.com/settings/tokens)

2. A DigitalOcean account with an API token
   - [Create a token here](https://cloud.digitalocean.com/account/api/tokens)
   - Required permissions: `read` and `write`

3. `doctl` CLI installed (optional, for manual management)
   ```bash
   # macOS
   brew install doctl
   
   # Linux
   snap install doctl
   ```

## Configuration

The script will create an `.env` file if it doesn't exist. Edit this file with your credentials:

```bash
# GitHub Configuration
GITHUB_USER="your-gh-username"
GITHUB_TOKEN="your-gh-token"
GITHUB_REPO="gitops-cluster"

# DigitalOcean Configuration
DO_TOKEN="your-do-token"
DROPLET_NAME="gitops-node"
DROPLET_SIZE="s-2vcpu-4gb"  # Minimum recommended size
DROPLET_REGION="ams3"       # Choose your preferred region
SSH_KEY_NAME="gitops-ssh"

# S3 Configuration
S3_BUCKET="gitops-backup"
S3_REGION="nyc3"
S3_ENDPOINT="https://nyc3.digitaloceanspaces.com"
```

## What the Script Does

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

## Accessing Your Cluster

After the script completes, you can:

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

## Monitoring and Maintenance

### Health Checks

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check ArgoCD sync status
kubectl get applications -n argocd
```

### Backup and Restore

See [docs/documentation.md](docs/documentation.md) for detailed backup and restore procedures.

## Troubleshooting

If you encounter issues:

1. Check the script output for error messages
2. Verify your credentials in `.env`
3. Ensure your GitHub token has the necessary permissions
4. Check if the DigitalOcean API token is valid

Common issues and solutions are documented in [docs/documentation.md](docs/documentation.md).

### Common Issues

1. **ArgoCD UI Not Accessible**
   - Verify the NodePort service is running
   - Check if port 30080 is open
   - Ensure the service type is NodePort

2. **GitHub Authentication Issues**
   - Verify GitHub token permissions
   - Check repository access
   - Ensure correct repository URL

3. **K3s Installation Issues**
   - Check system requirements
   - Verify network connectivity
   - Check K3s logs

## Cleanup

To remove all created resources:

1. Delete the GitHub repository
   ```bash
   # Using GitHub CLI
   gh repo delete <username>/<repo-name>
   ```

2. Delete the DigitalOcean droplet
   ```bash
   # Using doctl
   doctl compute droplet delete <droplet-id>
   ```

3. Remove the S3 bucket
   ```bash
   # Using AWS CLI
   aws s3 rb s3://<bucket-name> --force
   ```

4. Delete the SSH key from DigitalOcean
   ```bash
   # Using doctl
   doctl compute ssh-key delete <key-id>
   ```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/0xMattijs/microgitops/issues)
- [Documentation](docs/documentation.md)
- [Discussions](https://github.com/0xMattijs/microgitops/discussions) 