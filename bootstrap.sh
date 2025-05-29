#!/bin/bash

# If this script is being executed via curl | bash, create a proper wrapper
if [ -t 0 ]; then
    # Script is being run directly, proceed normally
    :
else
    # Script is being piped from curl, create a proper wrapper
    cat > /tmp/bootstrap_wrapper.sh << 'EOF'
#!/bin/bash

# Get the directory where the script was executed
EXEC_DIR="$(pwd)"

# Create a temporary file for the script
TEMP_SCRIPT="/tmp/bootstrap_$(date +%s).sh"

# Read the script from stdin and save it
cat > "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# Execute the script in the execution directory
cd "$EXEC_DIR"
"$TEMP_SCRIPT"

# Cleanup
rm "$TEMP_SCRIPT"
EOF
    chmod +x /tmp/bootstrap_wrapper.sh
    exec /tmp/bootstrap_wrapper.sh
    exit 0
fi

set -euo pipefail

# Main script execution
echo "Starting GitOps cluster bootstrap..."

# Store the current directory
CURRENT_DIR="$(pwd)"

# Function to create .env if it doesn't exist
create_example_env() {
    local env_file="$CURRENT_DIR/.env"
    if [ ! -f "$env_file" ]; then
        cat > "$env_file" <<EOF
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

# Other Configuration
DOCTL_CONTEXT="gitops-context"
# Optional: Install DigitalOcean CSI driver (true/false)
INSTALL_CSI_DRIVER="true"
EOF
        echo "Created .env file. Please edit it with your credentials."
        exit 1
    fi
}

# Create .env if it doesn't exist
create_example_env

# Source environment variables
set -a
source "$CURRENT_DIR/.env"
set +a

# Validate required environment variables
required_vars=("GITHUB_USER" "GITHUB_TOKEN" "DO_TOKEN")
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set in .env"
        exit 1
    fi
done

# Create and enter temporary directory for other operations
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to create remote-setup.sh
create_remote_setup() {
    cat > remote-setup.sh << 'EOF'
#!/bin/bash

set -euo pipefail

# Validate required parameters
if [ $# -lt 8 ]; then
    echo "Usage: $0 <GITHUB_USER> <GITHUB_REPO> <GITHUB_TOKEN> <S3_BUCKET> <S3_REGION> <S3_ENDPOINT> <DO_TOKEN> <CLUSTER_NAME> [INSTALL_CSI_DRIVER]"
    exit 1
fi

# Input parameters
GITHUB_USER="$1"
GITHUB_REPO="$2"
GITHUB_TOKEN="$3"
S3_BUCKET="$4"
S3_REGION="$5"
S3_ENDPOINT="$6"
DO_TOKEN="$7"
CLUSTER_NAME="$8"
INSTALL_CSI_DRIVER="${9:-false}"

# Validate parameters
for var in GITHUB_USER GITHUB_REPO GITHUB_TOKEN S3_BUCKET S3_REGION S3_ENDPOINT DO_TOKEN CLUSTER_NAME; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set"
        exit 1
    fi
done

# Disable package manager interaction
export DEBIAN_FRONTEND=noninteractive

# Function to clear package manager locks
clear_apt_locks() {
    echo "Clearing package manager locks..."
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock*
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    apt-get clean
}

# Function to safely run apt commands
run_apt_command() {
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        clear_apt_locks
        if "$@"; then
            return 0
        fi
        retry=$((retry + 1))
        echo "Retry $retry/$max_retries..."
        sleep 5
    done
    
    echo "Failed to run apt command after $max_retries attempts"
    return 1
}

# Fix GPG error
echo "Setting up GPG..."
run_apt_command apt-get update -o Acquire::AllowInsecureRepositories=true
run_apt_command apt-get install -y ca-certificates gnupg
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32 871920D1991BC93C

# Update system
echo "Updating system..."
run_apt_command apt-get update -o Acquire::AllowInsecureRepositories=true
run_apt_command apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
run_apt_command apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl wget git || true

# Install K3s
echo "Installing K3s..."
curl -sfL https://get.k3s.io | sh -

# Wait for K3s to be ready
echo "Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null; do
    echo "K3s not ready yet, waiting..."
    sleep 10
done

if [ "$INSTALL_CSI_DRIVER" = "true" ]; then
    echo "=== Starting CSI Driver Installation ==="
    
    # Create DigitalOcean secret for CSI driver
    echo "Creating DigitalOcean secret for CSI driver..."
    if ! kubectl create secret generic digitalocean --namespace kube-system --from-literal=access-token="$DO_TOKEN"; then
        echo "ERROR: Failed to create DigitalOcean secret"
        exit 1
    fi
    echo "✓ DigitalOcean secret created successfully"

    # Install DigitalOcean CSI driver
    echo "Installing DigitalOcean CSI driver CRDs..."
    if ! kubectl apply -f https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.14.0/crds.yaml; then
        echo "ERROR: Failed to install CSI driver CRDs"
        exit 1
    fi
    echo "✓ CSI driver CRDs installed successfully"

    echo "Installing CSI driver components..."
    if ! kubectl apply -f https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.14.0/driver.yaml; then
        echo "ERROR: Failed to install CSI driver components"
        exit 1
    fi
    echo "✓ CSI driver components installed successfully"

    echo "Installing snapshot controller..."
    if ! kubectl apply -f https://raw.githubusercontent.com/digitalocean/csi-digitalocean/master/deploy/kubernetes/releases/csi-digitalocean-v4.14.0/snapshot-controller.yaml; then
        echo "ERROR: Failed to install snapshot controller"
        exit 1
    fi
    echo "✓ Snapshot controller installed successfully"

    # Create volume snapshot class
    echo "Creating volume snapshot class..."
    if ! kubectl apply -f https://raw.githubusercontent.com/0xMattijs/microgitops/main/k8s/csi-driver.yaml; then
        echo "ERROR: Failed to create volume snapshot class"
        exit 1
    fi
    echo "✓ Volume snapshot class created successfully"

    # Wait for CSI driver to be ready
    echo "Waiting for CSI driver to be ready..."
    
    # Add initial delay to allow resources to be scheduled
    echo "Waiting 30 seconds for resources to be scheduled..."
    sleep 30
    
    echo "Checking for CSI controller pods..."
    echo "Current pod status:"
    kubectl get pods -n kube-system -l app=csi-do-controller
    
    # Wait for controller pods with increased timeout and retry
    max_retries=3
    retry=0
    while [ $retry -lt $max_retries ]; do
        if kubectl wait --for=condition=ready pod -l app=csi-do-controller -n kube-system --timeout=600s; then
            break
        fi
        retry=$((retry + 1))
        echo "Retry $retry/$max_retries: CSI controller pods not ready yet"
        echo "Current pod status:"
        kubectl get pods -n kube-system -l app=csi-do-controller
        if [ $retry -lt $max_retries ]; then
            echo "Waiting 30 seconds before retry..."
            sleep 30
        fi
    done
    
    if [ $retry -eq $max_retries ]; then
        echo "ERROR: CSI controller pods failed to become ready after $max_retries attempts"
        echo "Final pod status:"
        kubectl get pods -n kube-system -l app=csi-do-controller
        echo "Checking all pods in kube-system namespace:"
        kubectl get pods -n kube-system
        exit 1
    fi
    echo "✓ CSI controller pods are ready"

    echo "Checking for CSI node pods..."
    echo "Current pod status:"
    kubectl get pods -n kube-system -l app=csi-do-node
    
    # Wait for node pods with increased timeout and retry
    retry=0
    while [ $retry -lt $max_retries ]; do
        if kubectl wait --for=condition=ready pod -l app=csi-do-node -n kube-system --timeout=600s; then
            break
        fi
        retry=$((retry + 1))
        echo "Retry $retry/$max_retries: CSI node pods not ready yet"
        echo "Current pod status:"
        kubectl get pods -n kube-system -l app=csi-do-node
        if [ $retry -lt $max_retries ]; then
            echo "Waiting 30 seconds before retry..."
            sleep 30
        fi
    done
    
    if [ $retry -eq $max_retries ]; then
        echo "ERROR: CSI node pods failed to become ready after $max_retries attempts"
        echo "Final pod status:"
        kubectl get pods -n kube-system -l app=csi-do-node
        echo "Checking all pods in kube-system namespace:"
        kubectl get pods -n kube-system
        exit 1
    fi
    echo "✓ CSI node pods are ready"

    echo "Verifying storage classes..."
    if ! kubectl get storageclass do-block-storage; then
        echo "ERROR: Storage class 'do-block-storage' not found"
        exit 1
    fi
    echo "✓ Storage classes verified"

    echo "=== CSI Driver Installation Completed Successfully ==="
fi

# Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
until kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; do
    echo "ArgoCD not ready yet, waiting..."
    sleep 10
done

# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"

# Create GitHub credentials secret
echo "Creating GitHub credentials secret..."
kubectl create secret generic github-creds \
    --namespace argocd \
    --from-literal=type=git \
    --from-literal=url="https://github.com/$GITHUB_USER/$GITHUB_REPO.git" \
    --from-literal=username="$GITHUB_USER" \
    --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create NodePort service for ArgoCD
echo "Creating NodePort service for ArgoCD..."
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "targetPort": 8080, "nodePort": 30080}]}}'

# Wait for the service to be ready
echo "Waiting for NodePort service to be ready..."
until kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}' 2>/dev/null | grep -q "NodePort"; do
    echo "Service not ready yet, waiting..."
    sleep 5
done

echo "Remote setup complete!"
EOF
    chmod +x remote-setup.sh
}

# Create remote-setup.sh
create_remote_setup

# Function to create S3 bucket in Digital Ocean
create_s3_bucket() {
    local bucket_name="$1"
    local region="$2"
    local endpoint="$3"
    local do_token="$4"
    
    # Create access key first
    echo "Creating access key for bucket: $bucket_name"
    local key_name="${bucket_name}-access-key"
    local key_output=$(doctl spaces keys create "$key_name" \
        --access-token "$do_token" \
        --grants "bucket=;permission=fullaccess" \
        --output json)
    
    if [ $? -eq 0 ]; then
        echo "Successfully created access key for bucket: $bucket_name"
        # Store the access key and secret for later use
        S3_ACCESS_KEY=$(echo "$key_output" | jq -r '.[0].access_key')
        S3_SECRET_KEY=$(echo "$key_output" | jq -r '.[0].secret_key')
        
        # Configure AWS CLI with the new credentials
        export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
        export AWS_DEFAULT_REGION="$region"
        
        # Create AWS CLI config file
        mkdir -p ~/.aws
        cat > ~/.aws/config << 'EOF'
[default]
region = $region
s3 =
    endpoint_url = https://$region.digitaloceanspaces.com
    use_path_style_endpoint = true
    addressing_style = path
EOF
        
        # Create AWS CLI credentials file
        cat > ~/.aws/credentials << 'EOF'
[default]
aws_access_key_id = $S3_ACCESS_KEY
aws_secret_access_key = $S3_SECRET_KEY
EOF
        
        # Debug output
        echo "AWS CLI Configuration:"
        echo "Region: $region"
        echo "Endpoint: https://$region.digitaloceanspaces.com"
        echo "Access Key: ${S3_ACCESS_KEY:0:5}..."
        
        # Create the bucket using AWS CLI
        echo "Creating bucket: $bucket_name"
        if ! aws --endpoint-url "https://$region.digitaloceanspaces.com" s3 mb "s3://$bucket_name" --region "$region"; then
            echo "Failed to create bucket: $bucket_name"
            exit 1
        fi
        
        # Verify bucket access
        echo "Verifying bucket access..."
        if ! aws --endpoint-url "https://$region.digitaloceanspaces.com" s3 ls "s3://$bucket_name" --region "$region"; then
            echo "Failed to verify bucket access"
            exit 1
        fi
    else
        echo "Failed to create access key for bucket: $bucket_name"
        exit 1
    fi
}

# Determine project/repo name
if [ -z "${PROJECT_NAME:-}" ]; then
    DEFAULT_PROJECT_NAME="gitops-cluster-$(date +%Y%m%d-%H%M%S)"
    if [ -t 0 ]; then
        read -p "Enter project name for GitHub repo [${DEFAULT_PROJECT_NAME}]: " USER_PROJECT_NAME
        PROJECT_NAME="${USER_PROJECT_NAME:-$DEFAULT_PROJECT_NAME}"
    else
        PROJECT_NAME="$DEFAULT_PROJECT_NAME"
    fi
fi

GITHUB_REPO="$PROJECT_NAME"

# Set default values for derived variables
S3_BUCKET="${S3_BUCKET:-${PROJECT_NAME}-backup}"
S3_REGION="${S3_REGION:-nyc3}"
S3_ENDPOINT="${S3_ENDPOINT:-https://nyc3.digitaloceanspaces.com}"
DOCTL_CONTEXT="${DOCTL_CONTEXT:-gitops-context}"

# Set default values for droplet configuration if not defined in .env
DROPLET_SIZE="${DROPLET_SIZE:-s-2vcpu-4gb}"
DROPLET_IMAGE="${DROPLET_IMAGE:-ubuntu-22-04-x64}"
DROPLET_REGION="${DROPLET_REGION:-ams3}"
DROPLET_NAME="${DROPLET_NAME:-gitops-node}"

# Create S3 bucket if it doesn't exist
create_s3_bucket "$S3_BUCKET" "$S3_REGION" "$S3_ENDPOINT" "$DO_TOKEN"

# Generate unique cluster name with timestamp
CLUSTER_NAME="gitops-cluster-$(date +%Y%m%d-%H%M%S)"
echo "Generated cluster name: $CLUSTER_NAME"

# Check for previous state
STATE_FILE="cluster_state.txt"
if [ -f "$STATE_FILE" ]; then
    echo "Found previous state file. Loading state..."
    source "$STATE_FILE"
else
    echo "No previous state found. Starting fresh setup..."
fi

# Function to create GitHub repository
create_github_repo() {
    local repo_name="$1"
    local description="GitOps cluster configuration for $CLUSTER_NAME"
    
    # Check if repository exists
    if curl -s -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_USER/$repo_name" | grep -q "Not Found"; then
        echo "Creating GitHub repository: $repo_name"
        curl -X POST \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            https://api.github.com/user/repos \
            -d "{\"name\":\"$repo_name\",\"description\":\"$description\",\"private\":true}"
    else
        echo "Repository $repo_name already exists, using existing repository"
    fi
}

# Function to initialize repository with Kubernetes manifests
init_repo() {
    local repo_name="$1"
    local repo_dir="$TEMP_DIR/$repo_name"
    
    # Create repository directory
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    
    # Initialize git repository
    git init
    
    # Create k8s directory
    mkdir -p k8s
    
    # Create namespace manifest
    cat > k8s/namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: gitops-demo
EOF
    
    # Create deployment manifest
    cat > k8s/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: gitops-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF
    
    # Create service manifest
    cat > k8s/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: gitops-demo
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
    
    # Create README
    cat > README.md <<EOF
# GitOps Cluster Configuration

This repository contains the Kubernetes manifests for the GitOps cluster.

## Structure

- \`k8s/\`: Contains all Kubernetes manifests
  - \`namespace.yaml\`: Defines the namespace
  - \`deployment.yaml\`: Defines the nginx deployment
  - \`service.yaml\`: Defines the nginx service
EOF
    
    # Add and commit files
    git add .
    if git diff --staged --quiet; then
        echo "No changes to commit, but continuing with setup..."
    else
        git commit -m "Initial commit: Add Kubernetes manifests"
    fi
    
    # Configure git to use the token
    git config --global credential.helper store
    echo "https://$GITHUB_USER:$GITHUB_TOKEN@github.com" > ~/.git-credentials
    
    # Add remote and push
    git remote add origin "https://github.com/$GITHUB_USER/$repo_name.git" 2>/dev/null || true
    # Explicitly set the remote with the token
    git remote set-url origin "https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$repo_name.git"
    
    # Create main branch if it doesn't exist
    git branch -M main
    
    # Try to pull first in case remote has content
    git pull origin main --allow-unrelated-histories || true
    
    # Force push to ensure our content is used
    git push -f origin main
    
    # Clean up credentials
    rm -f ~/.git-credentials
    git config --global --unset credential.helper
    
    # Return to original directory
    cd "$TEMP_DIR"
}

# Create and initialize GitHub repository
echo "Setting up GitHub repository..."
create_github_repo "$GITHUB_REPO"
init_repo "$GITHUB_REPO"

# Set up doctl authentication
echo "Authenticating doctl with provided token"
doctl auth init -t "$DO_TOKEN"

# Create SSH key pair
SSH_KEY_NAME="gitops-key-$CLUSTER_NAME"
SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"

# Remove existing key if it exists
if [ -f "$SSH_KEY_PATH" ]; then
    echo "Removing existing SSH key: $SSH_KEY_NAME"
    rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
fi

# Generate new SSH key
echo "Generating new SSH key pair"
ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "gitops-key-$CLUSTER_NAME"

# Add SSH key to DigitalOcean
echo "Adding SSH key to DigitalOcean"
doctl compute ssh-key import "$SSH_KEY_NAME" --public-key-file "$SSH_KEY_PATH.pub"

# Get SSH key ID
SSH_KEY_ID=$(doctl compute ssh-key list | grep "$SSH_KEY_NAME" | awk '{print $1}')

# Create droplet
echo "Creating droplet..."
DROPLET_ID=$(doctl compute droplet create "$CLUSTER_NAME" \
    --size "$DROPLET_SIZE" \
    --image "$DROPLET_IMAGE" \
    --region "$DROPLET_REGION" \
    --ssh-keys "$SSH_KEY_ID" \
    --wait \
    --format ID \
    --no-header)

# Get droplet IP
DROPLET_IP=$(doctl compute droplet get "$DROPLET_ID" --format PublicIPv4 --no-header)
echo "Droplet created with IP: $DROPLET_IP"

# Wait for SSH to be available
echo "Waiting for SSH to be available..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$DROPLET_IP" echo "ready" 2>/dev/null; then
        break
    fi
    echo "Attempt $attempt/$max_attempts: SSH not ready yet, waiting..."
    sleep 10
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    echo "Failed to connect to droplet after $max_attempts attempts"
    exit 1
fi

# Copy remote setup script
echo "Copying remote setup script..."
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$(pwd)/remote-setup.sh" root@"$DROPLET_IP":/root/

# Execute remote setup
echo "Executing remote setup..."
INSTALL_CSI_DRIVER="${INSTALL_CSI_DRIVER:-false}"  # Set default value if not set
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no root@"$DROPLET_IP" "bash /root/remote-setup.sh '$GITHUB_USER' '$GITHUB_REPO' '$GITHUB_TOKEN' '$S3_BUCKET' '$S3_REGION' '$S3_ENDPOINT' '$DO_TOKEN' '$CLUSTER_NAME' '$INSTALL_CSI_DRIVER'"

# Get kubeconfig
echo "Getting kubeconfig..."
mkdir -p ~/.kube
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no root@"$DROPLET_IP":/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update kubeconfig
sed -i '' "s/127.0.0.1/$DROPLET_IP/g" ~/.kube/config

# Record state
echo "CLUSTER_NAME=$CLUSTER_NAME" > "$STATE_FILE"
echo "DROPLET_IP=$DROPLET_IP" >> "$STATE_FILE"

echo "Setup complete! Your cluster is ready at $DROPLET_IP"
echo "You can access the cluster using: kubectl --kubeconfig ~/.kube/config"
echo "ArgoCD web UI is available at: http://$DROPLET_IP:30080"
echo "ArgoCD admin username: admin"
echo "ArgoCD admin password: $(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no root@"$DROPLET_IP" "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d")"

# Verify kubectl configuration
echo "Verifying kubectl configuration..."
kubectl cluster-info
kubectl get nodes

echo "Cluster bootstrapped at $DROPLET_IP"
echo "Access ArgoCD at http://$DROPLET_IP:30080 with 'admin' user"
echo "Cluster name: $CLUSTER_NAME"
echo "Kubectl context set to: $CLUSTER_NAME"

# Cleanup
rm -f remote-setup.sh
