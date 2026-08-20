# CloudNotes (Infrastructure & DevSecOps)

This repository contains the infrastructure configuration, local deployment scripts, Kubernetes manifests (Kustomize overlays), and environment presets for **CloudNotes**.

The application source code lives in the application repository: **[cloudnotes-app-demo](https://github.com/NeoRaz/cloudnotes-app-demo)**. This repo keeps a Git Submodule for release pinning and production-style revision control, but local development can point directly at a sibling `cloudnotes-app-demo` checkout.

---

## Repository Structure

```text
cloudnotes-infra/
├── k8s/                # Kubernetes manifests and Kustomize overlays
│   ├── base/           # Base deployments, services, configmaps
│   └── overlays/       # Environment specific overlays (local, prod)
├── deployment/         # Environment files and build/deploy scripts
│   ├── envs/           # Config presets (.env files)
│   └── scripts/        # Orchestrator bash scripts (01-setup to 05-deploy)
└── src/                # Git Submodule pinned for deployment revisions
```

---

## Local Development Quickstart

To run the entire multi-pod application stack locally inside a Kubernetes cluster (Minikube):

### 1. Prepare the App Checkout
For local development, keep `cloudnotes-app-demo` checked out as a sibling directory next to `cloudnotes-infra-demo`. The local environment preset points at that checkout through `APP_REPO_ROOT`.

If you also want the infra repo to carry a pinned application revision for deployment comparison or release prep, initialize the submodule as well:
```bash
git submodule update --init --recursive
```

### 2. Deploy Backend Stack (Step 1)
Builds the server and AI images inside the Minikube daemon, and deploys databases, caches, and Laravel backend API:
```bash
cd deployment/scripts
bash deploy-first-step.sh local
```

### 3. Deploy Frontend & Passport (Step 2)
Generates Laravel Passport OAuth client keys, injects them into the frontend build environment variables, builds the Vite/React application, and deploys the Nginx proxy, Client, and Ingress routing rules:
```bash
bash deploy-second-step.sh local
```

### 4. Enable Ingress Routing
Start the Minikube tunnel in a separate terminal to route host traffic to the minikube IP:
```bash
minikube tunnel
```

### 5. Access the Application
Open your browser and navigate to:
**[http://cloudnotes.127.0.0.1.nip.io](http://cloudnotes.127.0.0.1.nip.io)**

---

## Script Manifest

* **`00-reset.sh`**: Deletes and purges your existing local Minikube cluster for a completely clean slate.
* **`01-setup-minikube.sh`**: Installs ingress and ingress-dns on Minikube and verifies the daemon is up.
* **`02-build-server.sh`**: Builds server and AI docker images and applies the backend overlay.
* **`03-passport-generation.sh`**: Generates and extracts Passport keys from the running server pod to configure client authentication.
* **`04-build-client.sh`**: Builds client static files with proper environment vars.
* **`05-deploy-final.sh`**: Applies the client/ingress ingress overlay, waits for all pods to be healthy.

---

## Troubleshooting

* **OAuth / Login Fails:** Ensure step 2 completed fully and the `REACT_APP_CLIENT_ID` / `REACT_APP_CLIENT_SECRET` have been updated inside your `deployment/envs/local.env` file.
* **Ingress Connection Timeout:** Verify that `minikube tunnel` is actively running and you are targeting the exact domain `cloudnotes.127.0.0.1.nip.io`.
