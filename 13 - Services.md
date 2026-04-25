# Services

> Un **Service** = interface réseau stable devant un ensemble de Pods sélectionnés par labels.  
> Problème résolu : l'IP d'un Pod change à chaque restart → le Service fournit une IP fixe (ClusterIP).  
> Le Service utilise **CoreDNS** pour être découvrable par hostname.  
> Sélection des Pods : via **labels** (comme un Deployment).

---

## 1. Types de Services

| Type | Accessible depuis | Description |
|------|-------------------|-------------|
| `ClusterIP` | Intérieur du cluster uniquement | **Défaut**. IP interne fixe. Load balancing round-robin entre Pods. |
| `NodePort` | Extérieur du cluster | Expose un port statique (30000-32767) sur chaque node. Hérite de ClusterIP. |
| `LoadBalancer` | Extérieur du cluster | Load balancer cloud externe. Hérite de NodePort + ClusterIP. |

> ⚠️ Les types **s'héritent** : LoadBalancer ⊃ NodePort ⊃ ClusterIP.

---

## 2. Port Mapping

> `port` = port d'entrée du Service.  
> `targetPort` = port du container dans le Pod (doit correspondre à `containerPort`).  
> `nodePort` = port exposé sur le node (NodePort/LoadBalancer uniquement, range 30000-32767).

---

## 3. Créer un Service

### Méthodes impératives

```bash
# Pod seul + Service séparé
kubectl run echoserver --image=k8s.gcr.io/echoserver:1.10 --restart=Never \
  --port=8080 -l app=echoserver

kubectl create service clusterip echoserver --tcp=80:8080
# --tcp=<port>:<targetPort>

# Pod + Service en une seule commande (pratique à l'exam !)
kubectl run echoserver --image=k8s.gcr.io/echoserver:1.10 --restart=Never \
  --port=8080 --expose

# Deployment + Service via expose
kubectl create deployment echoserver --image=hashicorp/http-echo:1.0.0 --replicas=5
kubectl expose deployment echoserver --port=80 --target-port=8080
# expose crée automatiquement le Service avec le bon label selector
```

### YAML — Service ClusterIP

```yaml
apiVersion: v1
kind: Service
metadata:
  name: echoserver
spec:
  # type: ClusterIP  ← valeur par défaut si omis
  selector:
    run: echoserver       # sélectionne les Pods avec ce label
  ports:
  - port: 80              # port d'entrée du Service
    targetPort: 8080      # port du container dans le Pod
```

---

## 4. ClusterIP

> Accessible **uniquement depuis l'intérieur du cluster**.  
> IP interne fixe assignée automatiquement.

```bash
# Créer Pod + Service ClusterIP
kubectl run echoserver --image=k8s.gcr.io/echoserver:1.10 --restart=Never \
  --port=8080 -l app=echoserver
kubectl create service clusterip echoserver --tcp=5005:8080

# Lister le Service (voir ClusterIP + port)
kubectl get service echoserver

# Accéder depuis un Pod temporaire dans le cluster
kubectl run tmp --image=busybox:1.36.1 --restart=Never -it --rm \
  -- wget 10.96.254.0:5005
# OU par hostname (CoreDNS)
kubectl run tmp --image=busybox:1.36.1 --restart=Never -it --rm \
  -- wget echoserver:5005
```

```yaml
# ClusterIP à runtime
apiVersion: v1
kind: Service
metadata:
  name: echoserver
spec:
  type: ClusterIP
  clusterIP: 10.96.254.0    # assigné automatiquement par Kubernetes
  selector:
    app: echoserver
  ports:
  - port: 5005
    targetPort: 8080
    protocol: TCP
```

---

## 5. NodePort

> Accessible depuis **l'extérieur du cluster** via `<NodeIP>:<nodePort>`.  
> Port statique automatiquement assigné dans la range **30000-32767**.  
> Hérite du comportement ClusterIP (accessible aussi depuis l'intérieur).

```bash
# Créer un Service NodePort
kubectl create service nodeport echoserver --tcp=5005:8080

# Lister (voir le nodePort dans PORT(S))
kubectl get service echoserver
# → 5005:30158/TCP  (30158 = nodePort assigné automatiquement)

# Récupérer l'IP du node
kubectl get nodes -o jsonpath='{ $.items[*].status.addresses[?(@.type=="InternalIP")].address }'

# Accéder depuis l'extérieur
wget 192.168.64.15:30158

# Accéder depuis l'intérieur (comme ClusterIP)
kubectl run tmp --image=busybox:1.36.1 --restart=Never -it --rm \
  -- wget 10.101.184.152:5005
```

```yaml
# NodePort à runtime
apiVersion: v1
kind: Service
metadata:
  name: echoserver
spec:
  type: NodePort
  clusterIP: 10.96.254.0
  selector:
    app: echoserver
  ports:
  - port: 5005
    nodePort: 30158         # port exposé sur chaque node (auto-assigné)
    targetPort: 8080
    protocol: TCP
```

---

## 6. LoadBalancer

> Accessible depuis **l'extérieur** via une IP externe fournie par le cloud provider.  
> Distribue le trafic sur plusieurs nodes.  
> Hérite de NodePort + ClusterIP.  
> ⚠️ Pas disponible sur clusters on-premises sans solution tierce (ex: MetalLB).

```bash
# Créer un Service LoadBalancer
kubectl create service loadbalancer echoserver --tcp=5005:8080

# Lister (voir EXTERNAL-IP)
kubectl get service echoserver
# → EXTERNAL-IP = 10.109.76.157

# Accéder depuis l'extérieur
wget 10.109.76.157:5005
```

```yaml
# LoadBalancer à runtime
apiVersion: v1
kind: Service
metadata:
  name: echoserver
spec:
  type: LoadBalancer
  clusterIP: 10.96.254.0
  loadBalancerIP: 10.109.76.157   # IP externe assignée par le cloud provider
  selector:
    app: echoserver
  ports:
  - port: 5005
    targetPort: 8080
    nodePort: 30158               # hérite du NodePort
    protocol: TCP
```

---

## 7. CoreDNS — Découverte par hostname

> CoreDNS enregistre chaque Service par son nom comme hostname.  
> Pas besoin de connaître l'IP du Service → utiliser le hostname.

```bash
# Même namespace → hostname seul
kubectl run tmp --image=busybox:1.36.1 --restart=Never -it --rm \
  -- wget echoserver:5005

# Namespace différent → hostname.namespace
kubectl run tmp --image=busybox:1.36.1 --restart=Never -it --rm \
  -n other -- wget echoserver.default:5005

# Nom complet (FQDN)
# echoserver.default.svc.cluster.local
# format : <service>.<namespace>.svc.cluster.local
```

---

## 8. Découverte par variables d'environnement

> Le kubelet injecte les infos du Service comme variables d'env dans chaque Pod.  
> ⚠️ Le Service **doit être créé avant** le Pod, sinon les variables ne sont pas disponibles.  
> Convention : `<SERVICE_NAME>_SERVICE_HOST` et `<SERVICE_NAME>_SERVICE_PORT`.  
> Les `-` dans le nom du Service sont remplacés par `_`.

```bash
# Voir les variables d'environnement injectées dans un container
kubectl exec -it echoserver -- env | grep ECHOSERVER
# → ECHOSERVER_SERVICE_HOST=10.96.254.0
# → ECHOSERVER_SERVICE_PORT=8080
```

---

## 9. Inspecter et déboguer un Service

```bash
# Lister tous les Services
kubectl get services

# Détails d'un Service (selector, IP, port, targetPort, endpoints)
kubectl describe service echoserver

# Lister les EndpointSlices (Pods ciblés par le Service)
kubectl get endpointslices -l app=echoserver

# Détails des endpoints (IP + port de chaque Pod)
kubectl describe endpointslice echoserver-js2xj
```

> ⚠️ Si `Endpoints: <none>` dans `describe service` → problème de label selector ou de port.

---

## Exercices & Solutions

---

### Exercice 1 — NodePort multi-ports

**Énoncé :**  
Créer un Deployment `webapp` avec 3 replicas (`nginxdemos/hello:0.4-plain-text`).  
Créer un Service `webapp-service` NodePort : port 80 (name: `web`, nodePort: 30080) + port 9090 (name: `metrics`).  
Vérifier l'accès via ClusterIP.

---

**Solution**

```bash
# Créer le Deployment
kubectl create deployment webapp --image=nginxdemos/hello:0.4-plain-text --replicas=3
```

```yaml
# webapp-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp-service
spec:
  type: NodePort
  selector:
    app: webapp               # correspond au label du Deployment
  ports:
  - name: web                 # nom du port (obligatoire si multi-ports)
    port: 80
    targetPort: 80
    nodePort: 30080           # nodePort fixe imposé par l'exercice
  - name: metrics             # second port
    port: 9090
    targetPort: 9090
    # nodePort auto-assigné
```

```bash
# Créer le Service
kubectl apply -f webapp-service.yaml

# Vérifier le Service
kubectl get service webapp-service

# Récupérer la ClusterIP
kubectl get service webapp-service -o jsonpath='{.spec.clusterIP}'

# Vérifier l'accès via ClusterIP depuis un Pod temporaire
kubectl run tmp --image=busybox:1.36.1 --restart=Never -it --rm \
  -- wget <ClusterIP>:80
```

---

### Exercice 2 — ClusterIP + découverte DNS entre Pods

**Énoncé :**  
Créer un Deployment `database` (1 replica, `mysql:9.4.0`) avec les env `MYSQL_ROOT_PASSWORD=secretpass` et `MYSQL_DATABASE=myapp`.  
Créer un Service ClusterIP `database-service` exposant le port 3306.  
Créer un Deployment `frontend` (2 replicas, `busybox:1.35`) qui teste en boucle la connexion à `database-service:3306`.  
Vérifier que le frontend peut résoudre et se connecter au Service.

---

**Solution**

```yaml
# database-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: mysql
        image: mysql:9.4.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "secretpass"       # mot de passe root MySQL
        - name: MYSQL_DATABASE
          value: "myapp"            # base de données créée au démarrage
```

```yaml
# database-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: database-service
spec:
  type: ClusterIP               # accessible uniquement depuis l'intérieur du cluster
  selector:
    app: database               # cible les Pods du Deployment database
  ports:
  - port: 3306                  # port MySQL standard
    targetPort: 3306
```

```yaml
# frontend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: busybox:1.35
        command:
        - sh
        - -c
        # teste la connexion TCP à database-service:3306 toutes les 5 secondes
        # utilise le hostname CoreDNS du Service (pas besoin de l'IP)
        - "while true; do nc -zv database-service 3306; sleep 5; done"
```

```bash
# Créer les objets dans l'ordre (Service avant Pods pour les env vars)
kubectl apply -f database-service.yaml
kubectl apply -f database-deployment.yaml
kubectl apply -f frontend-deployment.yaml

# Vérifier que tous les Pods sont Running
kubectl get pods

# Vérifier les logs du frontend (doit voir "open" si connexion OK)
kubectl logs -l app=frontend

# Vérifier les endpoints du Service database-service
kubectl get endpointslices -l app=database

# Vérifier la résolution DNS depuis un Pod frontend
kubectl exec -it <frontend-pod> -- nslookup database-service
```

---

## Points clés pour la CKA

| Concept | À retenir |
|---------|-----------|
| ClusterIP | Défaut. Interne uniquement. IP fixe + round-robin. |
| NodePort | Externe via `<NodeIP>:<nodePort>`. Range 30000-32767. Hérite ClusterIP. |
| LoadBalancer | Externe via IP cloud. Hérite NodePort + ClusterIP. |
| Port mapping | `port` (Service) → `targetPort` (container) |
| CoreDNS | Hostname = nom du Service. Cross-namespace : `<service>.<namespace>` |
| FQDN | `<service>.<namespace>.svc.cluster.local` |
| Env vars | `<SERVICE>_SERVICE_HOST` et `<SERVICE>_SERVICE_PORT` — Service doit exister avant le Pod |
| Debug | `kubectl describe service` → vérifier Selector + Endpoints |
| EndpointSlice | `kubectl get endpointslices -l <label>` → liste les Pods ciblés |
| `--expose` | Crée Pod + Service en une commande (utile à l'exam) |

---

## Pièges CKA

| Piège | Solution |
|-------|----------|
| `Endpoints: <none>` | Vérifier que le label du Pod matche le `selector` du Service |
| targetPort ≠ containerPort | Le trafic n'arrive pas au Pod — vérifier la cohérence des ports |
| Service créé après le Pod | Les variables d'env ne seront pas disponibles dans le Pod |
| NodePort hors range | Utiliser uniquement 30000-32767 ou laisser Kubernetes assigner |
| ClusterIP accessible depuis l'extérieur | Impossible — utiliser NodePort ou LoadBalancer |
| Multi-ports sans `name` | Obligatoire de nommer les ports si plusieurs ports dans un Service |
| Namespace différent sans suffixe | Utiliser `<service>.<namespace>` pour cross-namespace |
