# Azure VM deployment - preparation and notes

This document explains how to prepare the Azure VM and repository secrets required by the GitHub Actions workflow .github/workflows/ci-cd-azure-vm.yml.

## 1) Create an Azure VM and prepare a user
- Create an Ubuntu VM (20.04 / 22.04 recommended).
- Create a non-root user, e.g. `deploy` and allow SSH.
- Add the public key for this user (the corresponding private key will be added to GitHub secrets as AZURE_VM_SSH_KEY).

## 2) Install Docker and Docker Compose on the VM
Run (on the VM):
```bash
# install docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# allow non-root user to run docker
sudo usermod -aG docker $USER

# install docker-compose plugin (optional) or docker-compose binary
# Option A: docker compose (plugin)
sudo apt-get install -y docker-compose-plugin

# Option B: install standalone docker-compose (if you prefer)
# sudo curl -L "https://github.com/docker/compose/releases/download/v2.17.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
# sudo chmod +x /usr/local/bin/docker-compose
```

After installing, either log out and log back in to activate docker group membership, or reboot.

## 3) Create target deploy directory
Decide on a deploy path, e.g. `/opt/consultant-tracker`. Create it and set ownership:
```bash
sudo mkdir -p /opt/consultant-tracker
sudo chown deploy:deploy /opt/consultant-tracker
```

## 4) Prepare docker-compose.prod.yml on the repo
The workflow copies docker-compose.prod.yml (if present) into the deploy path. Ensure your docker-compose.prod.yml:

- mounts persistent volumes (if needed)
- reads environment from `.env` in the same directory (we create a `.env` with MONGODB_URL and REACT_APP_API_URL)
- includes services for backend (likely FastAPI uvicorn/gunicorn) and either serves frontend as static files (nginx) or uses a separate static server.

If you don't have docker-compose.prod.yml, create one that suits your usage. Example minimal:
```yaml
version: "3.8"
services:
  backend:
    build: ./backend
    env_file: .env
    ports:
      - "8000:8000"
    restart: always

  frontend:
    image: nginx:alpine
    volumes:
      - ./frontend_build:/usr/share/nginx/html:ro
    ports:
      - "80:80"
    restart: always
```

## 5) Add GitHub repository secrets
Go to your repository -> Settings -> Secrets and variables -> Actions -> New repository secret.

Add the following secrets (names expected by the workflow):
- AZURE_VM_HOST — VM public IP or DNS name
- AZURE_VM_USER — SSH username (e.g., deploy)
- AZURE_VM_SSH_KEY — PRIVATE SSH key for AZURE_VM_USER
- AZURE_VM_SSH_PORT — optional (defaults to 22)
- AZURE_VM_DEPLOY_PATH — e.g., /opt/consultant-tracker
- MONGODB_URL — your production MongoDB connection string (MongoDB Atlas or other)
- REACT_APP_API_URL — your public api base url (e.g., https://api.example.com/api)

Note: For added security you can create a dedicated deploy-only SSH key and restrict it (e.g., via authorized_keys options). Keep secrets private.

## 6) First deploy
- Ensure the VM is reachable via SSH and `AZURE_VM_USER` can write to `AZURE_VM_DEPLOY_PATH`.
- Push to main (or the branch configured in the workflow) to trigger the workflow.

The workflow will:
- build the frontend
- package backend + frontend/build + deploy script
- copy the package to the VM
- extract files into the deploy path
- write a `.env` file with MONGODB_URL and REACT_APP_API_URL
- run docker-compose -f docker-compose.prod.yml up -d --build

## 7) Logs and troubleshooting
- Check Actions logs on GitHub for build/deploy step outputs.
- On the VM, check docker logs:
  - docker-compose -f docker-compose.prod.yml logs -f
  - docker ps to see running containers
- If network or ssh issues occur, ensure firewall rules and NSG on Azure allow SSH from GitHub's actions runner IP ranges or open SSH port (22) appropriately (consider limiting to GitHub Actions IP ranges / use a bastion).

## 8) Optional improvements
- Use an image registry (GHCR / Docker Hub) to push built images and pull on VM instead of building on VM.
- Use zero-downtime deploy techniques (rolling update or blue/green).
- Use systemd to run docker-compose on boot or a docker swarm/Kubernetes setup for scaling.
