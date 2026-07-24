---
title: "Building a Single-Node K3s Homelab on a LattePanda Alpha"
date: 2026-05-14
author: "Looth"
description: "How I turned a LattePanda Alpha into a fully GitOps-managed Kubernetes homelab using K3s, ArgoCD, Prometheus, Grafana, and Cloudflare Tunnel — without opening a single port on my router."
tags: ["kubernetes", "k3s", "homelab", "gitops", "argocd", "prometheus", "grafana", "cloudflare", "devops"]
categories: ["DevOps", "Homelab", "Kubernetes"]
draft: false
---

# Building a Single-Node K3s Homelab on a LattePanda Alpha

![LattePanda Alpha Hardware](/img/lattepanda-alpha-hardware.jpg)

After spending a good amount of time running my services on a Docker-based production lab, I wanted to take the next step and get serious about Kubernetes — not just play with `minikube` on my laptop, but actually run a real cluster at home that I could break, fix, and learn from. The catch: I didn't want to spend a fortune on hardware or pay a cloud bill every month just to study k8s.

That's how this project was born. In this post, I'll walk you through how I turned a tiny **LattePanda Alpha** sitting on my desk into a fully **GitOps-managed Kubernetes homelab**, complete with monitoring, secure public exposure via Cloudflare Tunnel, and zero ports opened on my router.

If you've been on the fence about building a homelab Kubernetes cluster, this post is the blueprint I wish I'd had when I started.

## Why K3s, and Why a LattePanda?

When you say "Kubernetes at home," most people picture a stack of Raspberry Pis or a beefy mini-PC running a full control plane. I went a different route for a few reasons:

- **K3s is lightweight.** Rancher's K3s is a CNCF-certified Kubernetes distribution stripped down to a single ~70MB binary. It runs the entire control plane and worker on the same node without breaking a sweat.
- **The LattePanda Alpha is surprisingly capable.** It has an Intel Core m3-8100Y, 8GB of RAM, and 64GB of eMMC storage in a board roughly the size of a Raspberry Pi. That's enough horsepower to comfortably run a real cluster.
- **One node is fine for learning.** Multi-node clusters are great, but 90% of what you need to learn about Kubernetes — manifests, controllers, networking, RBAC, GitOps — works exactly the same on a single node.

## Hardware & Platform Overview

Here's the spec sheet for the box doing all the heavy lifting:

| Component | Details |
|-----------|---------|
| **Board** | LattePanda Alpha (Intel Core m3-8100Y) |
| **RAM** | 8GB |
| **Storage** | 64GB eMMC |
| **OS** | Ubuntu Server 24.04.3 LTS |
| **Kubernetes** | K3s (lightweight Kubernetes) |
| **Static IP** | 192.168.100.53 |
| **Timezone** | Indian Ocean / Maldives (MVT +5) |

I gave it a static IP on my LAN so DNS and tunnels always know where to find it, and a clean install of Ubuntu Server 24.04.3 LTS as the base OS.

![Ubuntu Server Install](/img/ubuntu-server-install.jpg)

## The Cluster Architecture

Here's how everything fits together inside the box:

![K3s Homelab Architecture](/img/k3s-homelab-architecture.png)

Three application namespaces sit on top of the K3s built-ins (Traefik, CoreDNS, metrics-server, local-path-provisioner, ServiceLB). ArgoCD watches a private GitHub repo and reconciles state. Cloudflared maintains an outbound tunnel so I can expose services publicly without touching my router.

## The Core Stack

### ArgoCD — The GitOps Brain

ArgoCD is the single most important piece of this setup. It's a continuous delivery tool that watches a Git repo and makes sure the cluster always matches whatever's defined there.

- **Version:** v3.3.0
- **Namespace:** `argocd`
- **Role:** Manages every other application deployment in the cluster

Once ArgoCD is in, I never `kubectl apply` an application manifest manually again. I just edit YAML, push to `main`, and the cluster catches up on its own.

### Monitoring Stack — kube-prometheus-stack

For observability I went with the well-known **kube-prometheus-stack** Helm chart. It bundles everything you need in one go:

| Component | Purpose |
|-----------|---------|
| **Prometheus** | Metrics collection and storage (14d retention) |
| **Grafana** | Dashboards and visualization |
| **Alertmanager** | Alert routing and notifications |
| **Kube State Metrics** | Kubernetes object metrics |
| **Node Exporter** | Host-level metrics |
| **Prometheus Operator** | Manages Prometheus lifecycle |

A few K3s-specific notes:

- Chart version: `kube-prometheus-stack v72.6.2`
- Components disabled (not available on K3s): `kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, `kubeProxy`
- SQLite WAL mode enabled for Grafana to keep it snappy on eMMC storage
- Grafana exposed at **grafana.looth.xyz** through Cloudflare Tunnel

### Cloudflared — Public Access Without Open Ports

This is honestly my favorite part of the setup. Instead of port-forwarding 80/443 on my home router and exposing the LattePanda's IP to the internet (no thanks), I use a **Cloudflare Tunnel**.

- **Image:** `cloudflare/cloudflared:latest`
- **Namespace:** `cloudflared`
- **Public domain:** `looth.xyz`
- **Auth:** Tunnel token stored as a Kubernetes Secret (never in Git)

The tunnel makes an outbound connection from inside my LAN to Cloudflare's edge. Public traffic to `*.looth.xyz` hits Cloudflare first, then gets routed back down through the tunnel to the right service in my cluster. The result: **zero open ports, no public IP exposure, free TLS**.

### Remote Access

For day-to-day cluster admin (SSH, `kubectl`, etc.) I use **Tailscale**. Public-facing web services like Grafana and ArgoCD go through Cloudflare Tunnel.

| Method | Purpose |
|--------|---------|
| **Tailscale** | Secure SSH and `kubectl` access to the cluster |
| **Cloudflare Tunnel** | Public access to web services (Grafana, ArgoCD) via looth.xyz |

## Repository Structure

The whole cluster is described by one Git repo (`homelab-k3s`), and the layout looks like this:

```
homelab-k3s/
├── apps/                              # ArgoCD Application manifests
│   ├── monitoring.yaml                #   → Helm: kube-prometheus-stack
│   └── cloudflared.yaml               #   → Raw manifests
├── values/                            # Helm values files
│   └── monitoring-values.yaml         #   → Prometheus, Grafana, Alertmanager config
├── manifests/                         # Raw Kubernetes manifests
│   └── cloudflared/
│       ├── namespace.yaml             #   → Namespace definition
│       └── deployment.yaml            #   → Deployment with tunnel token reference
├── .gitignore
└── README.md
```

Three directories, three responsibilities:

- **`apps/`** — ArgoCD Application definitions. Each file tells ArgoCD *what* to deploy and *where* to find the configuration. This is the control plane of the GitOps setup.
- **`values/`** — Helm chart value overrides. Used by Helm-based ArgoCD Applications. Edits here trigger automatic redeployment.
- **`manifests/`** — Raw Kubernetes YAML for apps that don't ship a Helm chart (like cloudflared). Each app gets its own subdirectory.

## The GitOps Workflow

This is where it all clicks. Once the cluster is bootstrapped, my entire deployment workflow boils down to one diagram:

```
  Local PC                    GitHub                     K3s Cluster
  ────────                    ──────                     ───────────
                                                         ArgoCD polls
  Edit YAML ──► git push ──► Repository ◄──────────────  every 3 min
                                         │
                                         │  Detects change
                                         ▼
                                    ArgoCD syncs
                                         │
                                         ▼
                                  Kubernetes applies
                                   new state
```

In practice:

1. **Edit** a YAML file locally (values, manifests, or application specs).
2. **Commit and push** to the `main` branch.
3. **ArgoCD detects** the change (it polls every ~3 minutes).
4. **ArgoCD syncs** the desired state to the cluster automatically.
5. **Kubernetes** rolls out the changes — rolling updates, pod restarts, etc.

No SSH. No `kubectl apply`. No "what did I deploy on this cluster six months ago?" Git is the source of truth, full stop.

### Example: Bumping Prometheus Retention

Say I want Prometheus to keep metrics for 14 days instead of the default 10:

```bash
# Edit the values file
vim values/monitoring-values.yaml
# Change: retention: 14d

# Commit and push
git add .
git commit -m "Increase Prometheus retention to 14d"
git push origin main

# ArgoCD auto-syncs — no kubectl needed
```

That's the entire deployment process. The next time ArgoCD wakes up, it spots the diff, applies it, and Prometheus gets recreated with the new retention.

## Adding a New Application

When I want to add something new to the cluster, the steps depend on whether the app has a Helm chart or just raw manifests.

### Option A: Helm-based App

```yaml
# apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: https://charts.example.com
      targetRevision: 1.0.0
      chart: my-app
      helm:
        valueFiles:
          - $values/values/my-app-values.yaml
    - repoURL: https://github.com/imluth/homelab-k3s.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Drop the values file in `values/`, the application in `apps/`, push, and bootstrap it once:

```bash
ssh luth@home-k3s-prod
cd ~/homelab-k3s && git pull
kubectl apply -f apps/my-app.yaml
```

### Option B: Raw Manifests

For apps without a Helm chart, I create `manifests/my-app/` with the namespace, deployment, service, etc., and point an ArgoCD Application at that path:

```yaml
# apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/imluth/homelab-k3s.git
    targetRevision: main
    path: manifests/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

After this one-time `kubectl apply`, every future change flows through Git. The bootstrap is the only manual step.

## Handling Secrets

There's one rule I'm strict about: **secrets never go in Git**. Not even encrypted, for now. The current approach:

- Secrets are created manually on the cluster with `kubectl create secret`.
- Manifests in Git just **reference** the secret by name (e.g., `cloudflared-token`).
- ArgoCD manages deployments but doesn't touch manually-created secrets.

The secrets living in the cluster today:

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `cloudflared-token` | cloudflared | Cloudflare Tunnel authentication token |
| `repo-homelab-k3s` | argocd | GitHub PAT for private repo access |
| `argocd-initial-admin-secret` | argocd | ArgoCD admin password |

Down the road I'd like to move to **Sealed Secrets** or **External Secrets Operator** so secrets can live encrypted in Git too — but for a single-node homelab the manual approach is honestly fine.

## A Few Hard-Won Tips

If you're building something similar, here are a few things I picked up the hard way:

- **K3s really is "just Kubernetes."** Almost every tutorial, Helm chart, and StackOverflow answer works as-is. The only gotchas are the components K3s replaces (no separate `kube-proxy`, etc.), which mostly matters when you install monitoring.
- **Use Server-Side Apply for big CRDs.** The kube-prometheus-stack CRDs are huge. If a sync fails with "request too large," add `ServerSideApply=true` to your `syncOptions`.
- **Enable Grafana's SQLite WAL mode on eMMC.** Without it, you'll occasionally see "database is locked" errors on slow storage. One line in `monitoring-values.yaml`:
  ```yaml
  grafana.ini:
    database:
      wal: true
  ```
- **Skip `initChownData` on the Grafana chart.** It can CrashLoopBackOff on permission issues. Disable it and use `fsGroup` in the security context instead.

## Useful Day-to-Day Commands

```bash
# Check all ArgoCD applications
kubectl get applications -n argocd

# View pods in a namespace
kubectl get pods -n <namespace>

# Check resource usage
kubectl top nodes
kubectl top pods -n <namespace>

# View application logs
kubectl logs -n <namespace> <pod-name> -c <container>

# Force ArgoCD to refresh from Git
kubectl annotate application <app-name> -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

## Wrapping Up

What I love about this setup is how **boring** it is in the best possible way. Once it's running, there's no clicking around dashboards, no SSH'ing in to fix things, no wondering "wait, what did I change last week?" — everything is in Git, ArgoCD keeps the cluster honest, and Cloudflare Tunnel keeps the whole thing reachable without exposing my home network.

It's also a fantastic learning platform. Every concept that matters in real-world Kubernetes — manifests, controllers, RBAC, Helm, GitOps, observability, ingress, TLS — is in here, in a small enough form that you can fully understand every piece.

If you're sitting on a spare mini-PC and you've been meaning to "really learn Kubernetes," I can't recommend this setup enough. Grab a LattePanda (or a NUC, or a Pi), throw K3s on it, point ArgoCD at a Git repo, and start shipping.

The cluster will be running while you sleep. And when you wake up, it'll still be exactly the way Git said it should be.

---

*If you found this article helpful, please share it with others who might benefit from it!*
