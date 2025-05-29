You are a gitops expert

Create a PRD for a self-contained, minimalistic gitops driven system. Starting very small and bootstrappable to a single Digital Ocean droplet. The system should comprise of a k8s (virtual) cluster, have s3 compatibe object storage, dynamic volumes and networking. Everything should be gitops driven. A key requirement is that the entire system should be able to be snapshotted and rebuilt from scratch, only using gitops and cheap external cloud storage, all from the bootstrap script (with a restore option)

The system should be a self-containing bootstrap script, only starting from a github login (or API token) and a Digital Ocean API token. The script would:

- Provision the Digital Ocean droplet
- Initialize a new github repo or restore from an an existing repo
- Provision Storage Volume

Tech stack:
  - K8S
  - ArgoCD

The system should have an option to scale up (to a larger droplet) and out (add Droplets) using the restore from snapshot feature