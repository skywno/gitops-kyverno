# gitops-kyverno

Kubernetes' policy managed with Argo CD and Kyverno

## Prerequisites

You will need a Kubernetes cluster version 1.21 or newer.
For a quick local test, you can use [Kubernetes kind](https://kind.sigs.k8s.io/docs/user/quick-start/).
Any other Kubernetes setup will work as well though.

In order to follow the guide you'll need a GitHub account and a
[personal access token](https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line)
that can create repositories (check all permissions under `repo`).

Install the Argo CD CLI:

```sh
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

## Repository structure

The Git repository contains the following top directories:

- **apps** dir contains a demo app (podinfo) and its configuration for each environment
- **infrastructure** dir contains common infra tools such as Kyverno and its cluster policies
- **clusters** dir contains the Argo CD configuration per cluster

```
├── apps
│   ├── base
│   ├── production 
│   └── staging
├── infrastructure
│   ├── configs
│   └── controllers
└── clusters
    ├── production
    └── staging
```

## Bootstrap the staging cluster

Create a cluster named staging with kind:

```shell
kind create cluster --name staging
```

Fork this repository on your personal GitHub account and export your GitHub access token, username and repo name:

```sh
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
export REPO_NAME=gitops-kyverno
```

Set the kubectl context to your staging cluster and install Argo CD:

```sh
kubectl config use-context kind-staging

# Install Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

Get the initial admin password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Login to Argo CD (port-forward the server first):

```sh
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd login localhost:8080 --username admin --insecure
```

Bootstrap the root Application for staging:

```sh
argocd app create root-app \
  --repo https://github.com/${GITHUB_USER}/${REPO_NAME}.git \
  --path clusters/staging/argocd \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```

The root Application will automatically create and sync the infrastructure and apps Applications defined in the `clusters/staging` directory.

Wait for Argo CD to sync all applications:

```shell
watch argocd app list
```

## Access the Argo CD UI

To access the Argo CD UI on a cluster, first start port forwarding with:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Navigate to `https://localhost:8080` and login using the username `admin` and the password retrieved earlier.

The Argo CD UI provides insights into your application deployments,
and makes continuous delivery easier to adopt and scale across your teams.
You can easily discover the relationship between Applications and navigate to deeper levels of information as required.

## Mutating deployments with Kyverno

In the `infrastructure/configs` dir there are two Kyverno policies that mutate Kubernetes Deployments to set
a restricted security context and to replace the app container image tag with its digest.

Even if in Git, the podinfo image is set to `ghcr.io/stefanprodan/podinfo:6.2.3`, the actual
deployment image in-cluster is mutated by Kyverno and the tag is replaced with the image digest.
Same thing with the security context, in Git, podinfo has no such fields, but in-cluster the deployment ends up with:

```console
$ kubectl -n podinfo get deployments.apps podinfo -oyaml | yq '.spec.template.spec.containers[0]'
image: ghcr.io/stefanprodan/podinfo@sha256:4a72d3ce7eda670b78baadd8995384db29483dfc76e12f81a24e1fc1256c0a8e
imagePullPolicy: IfNotPresent
name: podinfo
ports:
  - containerPort: 9898
    name: http
    protocol: TCP
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault
```

## Argo CD Application Structure

This repository uses the App of Apps pattern:

- **Root Application** (`clusters/*/argocd/root-app.yaml`) - Manages infrastructure and apps Applications
- **Infrastructure Applications** (`clusters/*/infrastructure.yaml`) - Manages controllers (Kyverno) and configs (policies)
- **Apps Application** (`clusters/*/apps.yaml`) - Manages environment-specific applications

Applications are configured with:
- Automated sync with self-healing
- Automatic pruning of resources removed from Git
- Dependency management between Applications
- Namespace auto-creation

## Validation

Before committing changes, validate the manifests:

```sh
./scripts/validate.sh
```

This script validates:
- All YAML files for syntax errors
- Argo CD Application resources
- Kustomize overlays

## Production Cluster

To bootstrap the production cluster, follow the same steps but use:

```sh
kubectl config use-context <production-context>
# ... install Argo CD ...
argocd app create root-app \
  --repo https://github.com/${GITHUB_USER}/${REPO_NAME}.git \
  --path clusters/production/argocd \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```