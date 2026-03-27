# k8s

Infrastructure configuration for a self-hosted Kubernetes cluster running on a Hetzner VPS (Ubuntu) with [K3s](https://k3s.io/).

## What's in this repo

| Directory | Description |
|---|---|
| `charts/app/` | Generic Helm chart for all app types (websites, APIs, databases) |
| `cert-manager/` | ClusterIssuer for automatic Let's Encrypt SSL via cert-manager |
| `registry/` | Private Docker registry (in-cluster) with htpasswd auth |
| `deploy/` | Git-push deploy setup — Dokku-like `git push deploy main` experience |
| `monitoring/` | Trivy CronJob for daily image vulnerability scanning |
| `examples/` | Example `helm-values.yaml` files for common app types |

## Stack

- **K3s** — lightweight, CNCF-certified Kubernetes distribution
- **Traefik** — ingress controller (K3s default)
- **cert-manager** — automatic TLS certificates from Let's Encrypt
- **Helm** — single generic chart covers all app types
- **Private registry** — in-cluster container image storage
- **Kaniko** — in-cluster Docker image builds (no Docker daemon required)

## How deployments work

A single Helm chart (`charts/app/`) provides templates for Deployment, Service, Ingress, and PVC. Each app only needs a `helm-values.yaml` to override the defaults — no raw Kubernetes manifests required.

```
my-app/
├── Dockerfile
└── helm-values.yaml    # only K8s-related file needed
```

A minimal `helm-values.yaml` for a website is ~4 lines:

```yaml
name: my-website
ingress:
  hosts:
    - my-website.mysite.com
```

Everything else (port 80, health probe, TLS, resource limits) comes from chart defaults. See `charts/app/values.yaml` for all available options.

### Deploying

First deploy — just push, the hook runs `helm upgrade --install` and creates all resources:

```bash
git remote add deploy deploy@<server-ip>:my-app
git push deploy main
```

Two ways to deploy updates:

1. **Git push** — `git push deploy main` builds on the server, streams logs back (Dokku-like)
2. **GitHub Actions** — CI/CD builds image, pushes to registry, deploys via Helm

See [CLAUDE.md](CLAUDE.md) for full setup instructions, commands, and architecture decisions.

## Initial server setup

After creating a fresh Hetzner VPS with Ubuntu, run through these steps to get the cluster up.

For a guided setup, copy this repo to the server and run `setup.sh` — it prompts for your domain and registry credentials, then runs all the steps below:

```bash
rsync -a --exclude='.git' . root@<server-ip>:/tmp/k8s-setup
ssh root@<server-ip>
bash /tmp/k8s-setup/setup.sh
```

Or follow the steps manually:

First:

1. Point your domain to the server — add a DNS A record for `*.<domain>` to the server IP.
2. Update the registry domain in this repo to match your domain. It appears in:
   - `charts/app/values.yaml` — default image registry
   - `deploy/setup-deploy.sh` — `REGISTRY` variable
   - `registry/registry.yaml` — ingress host and TLS config
   - `examples/github-actions/deploy-ci.yaml` — CI registry URL
   - `examples/github-actions/deploy-environments.yaml` — CI registry URL

```bash
# 1. Install K3s
ssh root@<server-ip>
sudo apt update -y
curl -sfL https://get.k3s.io | sh -

# 2. Security hardening — key-only auth, firewall
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 6443/tcp
ufw enable
apt install fail2ban -y && systemctl enable fail2ban

# 3. Copy this repo to the server
exit  # back to local machine
rsync -a --exclude='.git' . root@<server-ip>:/tmp/k8s-setup

# 4. Install cert-manager + ClusterIssuer
ssh root@<server-ip>
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=available deployment --all -n cert-manager --timeout=120s
kubectl apply -f /tmp/k8s-setup/cert-manager/cluster-issuer.yaml

# 5. Deploy the private registry
kubectl create namespace registry
apt install apache2-utils -y
htpasswd -Bc registry-htpasswd <username>
kubectl create secret generic registry-auth --from-file=htpasswd=registry-htpasswd -n registry
kubectl apply -f /tmp/k8s-setup/registry/registry.yaml

# 6. Create secrets for Kaniko and image pulling
echo '{"auths":{"registry.<domain>":{"username":"<user>","password":"<pass>"}}}' > /tmp/docker-config.json
kubectl create secret generic kaniko-docker-config \
  --from-file=config.json=/tmp/docker-config.json
rm /tmp/docker-config.json
kubectl create secret docker-registry kaniko-registry-creds \
  --docker-server=registry.<domain> --docker-username=<user> --docker-password=<pass>

# 7. Set up git-push deploys (copies Helm chart, creates deploy user, etc.)
bash /tmp/k8s-setup/deploy/setup-deploy.sh "$(cat ~/.ssh/authorized_keys)"
```

Copy the kubeconfig from `/etc/rancher/k3s/k3s.yaml` to your local `~/.kube/config` (replace `127.0.0.1` with the server IP) for remote `kubectl` access.

See [CLAUDE.md](CLAUDE.md) for detailed explanations of each step.

## Examples

The [`examples/`](examples/) directory has ready-to-use `helm-values.yaml` files for common app types — websites, APIs, WebSocket apps, databases, multi-domain setups, per-environment configs, and GitHub Actions workflows.
