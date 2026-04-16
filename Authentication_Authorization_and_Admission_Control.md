# Authentication & Authorization — Kubernetes

---

## 1. Kubeconfig

Le fichier de configuration de `kubectl` se trouve à `$HOME/.kube/config`.  
Il contient les **clusters**, **users** et **contexts**.

> Un **context** = mapping `cluster` + `user` + `namespace`.

```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /Users/bmuschko/.minikube/ca.crt  # CA du cluster
    server: https://127.0.0.1:63709                           # endpoint API server
  name: minikube
contexts:
- context:
    cluster: minikube
    user: bmuschko
  name: bmuschko
- context:
    cluster: minikube
    namespace: default
    user: minikube
  name: minikube
current-context: minikube                                     # context actif
users:
- name: bmuschko
  user:
    client-key-data: <REDACTED>
- name: minikube
  user:
    client-certificate: /Users/bmuschko/.minikube/profiles/minikube/client.crt
    client-key: /Users/bmuschko/.minikube/profiles/minikube/client.key
```

### Commandes essentielles

```bash
# Affiche le contenu fusionné du kubeconfig
kubectl config view

# Affiche le context actuellement actif
kubectl config current-context

# Change le context actif (change de cluster/user)
kubectl config use-context bmuschko

# Ajoute un user avec ses certificats dans le kubeconfig
kubectl config set-credentials myuser \
  --client-key=myuser.key \
  --client-certificate=myuser.crt \
  --embed-certs=true          # intègre les certs dans le fichier (pas de chemin externe)
```

---

## 1.bis Kubeconfig sur un cluster kubeadm

Sur kubeadm, le CA se trouve dans `/etc/kubernetes/pki/` (et non `~/.minikube/`).  
Le port par défaut de l'API server est `6443`.

### Étape 1 — Générer les certificats pour l'user

```bash
# 1. Générer la clé privée
openssl genrsa -out bmuschko.key 2048

# 2. Créer la CSR (CN = username reconnu par Kubernetes, O = group)
openssl req -new -key bmuschko.key \
  -out bmuschko.csr \
  -subj "/CN=bmuschko/O=dev-team"

# 3. Signer avec le CA kubeadm (sudo requis car ca.key appartient à root)
sudo openssl x509 -req -in bmuschko.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out bmuschko.crt \
  -days 365

# 4. Vérifier le certificat généré
openssl x509 -in bmuschko.crt -noout -subject
# → subject=CN = bmuschko, O = dev-team
```

### Étape 2 — Construire le kubeconfig

```bash
# Récupérer l'IP du control plane
kubectl cluster-info | grep "control plane"
# → https://192.168.56.10:6443

# Ajouter le cluster
kubectl config set-cluster kubeadm-cluster \
  --server=https://<IP_CONTROL_PLANE>:6443 \
  --certificate-authority=/etc/kubernetes/pki/ca.crt \
  --embed-certs=true \
  --kubeconfig=bmuschko.kubeconfig

# Ajouter l'user avec ses certs
kubectl config set-credentials bmuschko \
  --client-certificate=bmuschko.crt \
  --client-key=bmuschko.key \
  --embed-certs=true \
  --kubeconfig=bmuschko.kubeconfig

# Créer le context
kubectl config set-context bmuschko-context \
  --cluster=kubeadm-cluster \
  --user=bmuschko \
  --namespace=default \
  --kubeconfig=bmuschku.kubeconfig

# Activer le context
kubectl config use-context bmuschko-context \
  --kubeconfig=bmuschko.kubeconfig
```

### Étape 3 — Tester l'authentification

```bash
# Forbidden = normal : l'user est authentifié mais n'a pas encore de RBAC
kubectl get pods --kubeconfig=bmuschko.kubeconfig
# → Error from server (Forbidden): pods is forbidden: User "bmuschko" cannot list resource "pods"...
```

> Utiliser `--kubeconfig=bmuschko.kubeconfig` en flag ne touche pas à `~/.kube/config`.  
> Le context admin reste actif par défaut.

### Étape 4 — Fusionner dans le kubeconfig principal (optionnel)

```bash
# Fusion des deux fichiers
KUBECONFIG=~/.kube/config:bmuschko.kubeconfig kubectl config view --flatten > /tmp/merged.kubeconfig
mv /tmp/merged.kubeconfig ~/.kube/config

# Lister tous les contexts disponibles
kubectl config get-contexts

# Switcher vers bmuschko
kubectl config use-context bmuschko-context

# Revenir à l'admin kubeadm
kubectl config use-context kubernetes-admin@kubernetes
```

---

## 2. RBAC

| Ressource | Périmètre |
|---|---|
| `Role` + `RoleBinding` | Namespace uniquement |
| `ClusterRole` + `ClusterRoleBinding` | Cluster entier |

- **Role** = ce qu'on peut faire (verbs) sur quelles ressources, dans un namespace.
- **RoleBinding** = qui (user / group / serviceaccount) a ce Role.

```bash
# Affiche toutes les ressources API + leurs verbs supportés
kubectl api-resources -o wide
```

### Role

```bash
# Crée un Role "read-only" qui autorise list/get/watch sur pods, deployments, services
kubectl create role read-only \
  --verb=list,get,watch \
  --resource=pods,deployments,services

kubectl get roles
kubectl describe role read-only
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: read-only
rules:
- apiGroups: [""]           # "" = core API group (pods, services...)
  resources: ["pods", "services"]
  verbs: ["list", "get", "watch"]
- apiGroups: ["apps"]       # apps = API group des deployments, replicasets...
  resources: ["deployments"]
  verbs: ["list", "get", "watch"]
```

### RoleBinding

```bash
# Bind le Role "read-only" à l'user "bmuschko" dans le namespace courant
kubectl create rolebinding read-only-binding \
  --role=read-only \
  --user=bmuschko

kubectl get rolebindings
kubectl describe rolebinding read-only-binding
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-only-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: read-only             # Role à binder
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: bmuschko              # user qui reçoit le Role
```

### Tester les permissions

```bash
# Passe sur le context de l'user bmuschko (permissions limitées)
kubectl config use-context bmuschko-context

# Autorisé : bmuschko a le droit list sur deployments
kubectl get deployments

# Refusé : replicasets n'est pas dans le Role → Forbidden
kubectl get replicasets

# Refusé : delete n'est pas dans les verbs autorisés → Forbidden
kubectl delete deployment myapp

# Liste toutes les permissions de bmuschko
kubectl auth can-i --list --as bmuschko

# Vérifie une permission précise pour bmuschko
kubectl auth can-i list pods --as bmuschko    # → yes
```

---

## 3. ClusterRole Aggregation

Permet de **combiner plusieurs ClusterRoles** via des labels sans dupliquer les règles.

```yaml
# ClusterRole 1 : autorise list sur pods
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: list-pods
  labels:
    rbac-pod-list: "true"       # label utilisé pour l'aggregation
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list"]
---
# ClusterRole 2 : autorise delete sur services
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: delete-services
  labels:
    rbac-service-delete: "true"
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["delete"]
---
# ClusterRole agrégé : combine les deux via leurs labels
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pods-services-aggregation-rules
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac-pod-list: "true"        # sélectionne list-pods
  - matchLabels:
      rbac-service-delete: "true"  # sélectionne delete-services
rules: []                          # vide : les règles viennent des ClusterRoles sélectionnés
```

```bash
# Vérifie que les règles ont bien été agrégées
kubectl describe clusterroles pods-services-aggregation-rules -n rbac-example
```

---

## 4. ServiceAccount

Un **ServiceAccount** permet à un Pod de s'authentifier auprès de l'API server.

- Token monté automatiquement dans le pod : `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Sans RBAC, le serviceaccount = **accès refusé par défaut**.

```bash
kubectl get serviceaccounts
kubectl create serviceaccount cicd-bot
kubectl apply -f setup.yaml

kubectl logs list-objects -c pods -n k97
kubectl logs list-objects -c deployments -n k97

kubectl apply -f role.yaml
kubectl apply -f rolebinding.yaml
```

### `setup.yaml` — namespace + serviceaccount + pod

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: k97
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-api
  namespace: k97
---
apiVersion: v1
kind: Pod
metadata:
  name: list-objects
  namespace: k97
spec:
  serviceAccountName: sa-api   # le pod utilise ce serviceaccount pour s'auth
  containers:
  - name: pods
    image: alpine/curl:3.14
    command: ['sh', '-c', 'while true; do curl -s -k -m 5 -H \
      "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
      https://kubernetes.default.svc.cluster.local/api/v1/namespaces/k97/pods; \
      sleep 10; done']
  - name: deployments
    image: alpine/curl:3.14
    command: ['sh', '-c', 'while true; do curl -s -k -m 5 -H \
      "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
      https://kubernetes.default.svc.cluster.local/apis/apps/v1/namespaces/k97/deployments; \
      sleep 10; done']
```

> `kubernetes.default.svc` = Service interne qui pointe vers l'API server.  
> Le Bearer token est monté automatiquement dans le pod.

### `role.yaml` — autorise `list` sur pods uniquement

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: list-pods-role
  namespace: k97
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list"]     # uniquement list, pas get/watch/delete
```

### `rolebinding.yaml` — bind le Role au serviceaccount `sa-api`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: serviceaccount-pod-rolebinding
  namespace: k97
subjects:
- kind: ServiceAccount
  name: sa-api
roleRef:
  kind: Role
  name: list-pods-role
  apiGroup: rbac.authorization.k8s.io
```

---

## 5. Admission Control

Dernière phase avant qu'une requête soit acceptée par l'API server.  
Géré par l'admin via `/etc/kubernetes/manifests/kube-apiserver.yaml`.

```bash
# Active des plugins d'admission au démarrage de l'API server
kube-apiserver --enable-admission-plugins=NamespaceLifecycle,PodSecurity,LimitRanger
```

| Plugin | Rôle |
|---|---|
| `NamespaceLifecycle` | Empêche la création de ressources dans un namespace en cours de suppression |
| `PodSecurity` | Applique des politiques de sécurité sur les pods |
| `LimitRanger` | Impose des limites de ressources (CPU/RAM) par défaut |

---

## Pièges CKA

| Piège | Solution |
|---|---|
| `Role` vs `ClusterRole` | Role = namespace uniquement, ClusterRole = cluster entier |
| `RoleBinding` peut référencer un `ClusterRole` | Mais l'accès reste limité au namespace du RoleBinding |
| `apiGroups: ""` vs `apiGroups: "apps"` | Pods/Services = `""`, Deployments/ReplicaSets = `"apps"` |
| ServiceAccount sans RBAC = accès refusé | Toujours créer Role + RoleBinding associés |
| Tester les perms sans changer de context | Utiliser `kubectl auth can-i --as <user>` |
