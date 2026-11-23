# Flask CI/CD: GitHub Actions → Jenkins → Docker → Kubernetes

```
git push (main)
   │
   ▼
GitHub Actions  (self-hosted runner on homelab)
   │  curl → Jenkins REST API (buildWithParameters, waits for result)
   ▼
Jenkins pipeline (Jenkinsfile)
   ├─ Checkout commit
   ├─ docker build  → flask-app:<short-sha>
   ├─ Smoke test container (/health)
   ├─ docker push   → Docker Hub
   ├─ kubectl apply → k3s cluster (rolling update, 2 replicas)
   └─ rollout status / auto-rollback on failure
   ▼
App live at http://<homelab-ip>:30080
```

## Repo layout

| Path | Purpose |
|---|---|
| `app/` | Flask app (`/` and `/health`) |
| `Dockerfile` | Gunicorn image, non-root user |
| `Jenkinsfile` | Build → test → push → deploy pipeline |
| `.github/workflows/trigger-jenkins.yml` | Triggers Jenkins on push to `main` |
| `scripts/trigger_jenkins.sh` | Calls Jenkins API, polls until build finishes |
| `k8s/` | Namespace, Deployment, NodePort Service |

---

## Step 1 — Install prerequisites on the homelab (as root)

```bash
# Docker
apt update && apt install -y docker.io jq curl git
systemctl enable --now docker

# Let Jenkins use Docker
usermod -aG docker jenkins
systemctl restart jenkins

# Kubernetes: k3s (lightweight, single node).
# Traefik disabled so it doesn't grab ports 80/443 from Nginx.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
kubectl get nodes        # should show Ready

# kubeconfig for Jenkins (uploaded as a credential in Step 2)
cp /etc/rancher/k3s/k3s.yaml /root/kubeconfig-jenkins.yaml
```

k3s ships `kubectl` at `/usr/local/bin/kubectl`, so Jenkins can call it directly.

## Step 2 — Configure Jenkins

1. **Plugins** (Manage Jenkins → Plugins): *Pipeline*, *Git*, *Credentials Binding*, *Timestamper*.
2. **Credentials** (Manage Jenkins → Credentials → Global → Add):
   - `dockerhub-creds` — *Username with password* (Docker Hub user + access token)
   - `kubeconfig` — *Secret file* → upload `/root/kubeconfig-jenkins.yaml`
3. **API token**: click your user → *Security* → *API Token* → *Add new token*. Copy it.
4. **Job**: New Item → `flask-k8s-pipeline` → *Pipeline*
   - Definition: *Pipeline script from SCM* → Git → your GitHub repo URL, branch `*/main`
   - Script path: `Jenkinsfile`
   - Run it once manually so Jenkins registers the `GIT_SHA` / `GIT_BRANCH` parameters.
5. Edit `DOCKERHUB_USER` at the top of the `Jenkinsfile`.

## Step 3 — GitHub repo, secrets and runner

```bash
cd flask-k8s-cicd
git init && git add . && git commit -m "Initial CI/CD pipeline"
git branch -M main
git remote add origin https://github.com/<you>/flask-k8s-cicd.git
git push -u origin main
```

**Secrets** (repo → Settings → Secrets and variables → Actions):

| Secret | Example |
|---|---|
| `JENKINS_URL` | `http://localhost:<jenkins-port>` |
| `JENKINS_USER` | `admin` |
| `JENKINS_TOKEN` | token from Step 2.3 |
| `JENKINS_JOB` | `flask-k8s-pipeline` |

**Self-hosted runner** (repo → Settings → Actions → Runners → *New self-hosted runner* → Linux).
Run the commands GitHub shows on the homelab as a normal user (not root), then install it as a service:

```bash
sudo ./svc.sh install && sudo ./svc.sh start
```

> Why self-hosted? Jenkins is on your home LAN, so GitHub's cloud runners can't reach it. The runner on the homelab connects *out* to GitHub and calls Jenkins on localhost — no port forwarding needed.

## Step 4 — Test end to end

```bash
# change the message in app/app.py, then:
git commit -am "Change greeting" && git push
```

Watch: **GitHub → Actions** (shows Jenkins console tail) → **Jenkins** → then:

```bash
kubectl -n flask-app get pods
curl http://<homelab-ip>:30080
# {"message": "...", "version": "<short-sha>", "pod": "flask-app-xxxx"}
```

Refresh a few times — the `pod` field alternates between the 2 replicas.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `permission denied ... docker.sock` | `usermod -aG docker jenkins && systemctl restart jenkins` |
| Action fails "Failed to trigger" | Check `JENKINS_URL`/port, token, job name; test with `curl -u user:token $JENKINS_URL/api/json` |
| `ImagePullBackOff` | Image name/tag wrong or repo private on Docker Hub (make it public, or add an `imagePullSecret`) |
| Rollout times out | `kubectl -n flask-app describe pod <pod>` and `kubectl -n flask-app logs <pod>` |
| Port 30080 unreachable | `ufw allow 30080/tcp` |

## Useful commands

```bash
kubectl -n flask-app rollout history deployment/flask-app
kubectl -n flask-app rollout undo deployment/flask-app      # manual rollback
kubectl -n flask-app scale deployment/flask-app --replicas=3
```
