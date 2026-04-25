# Ingresses

> Un **Ingress** = point d'entrée unique pour le trafic HTTP(S) externe vers un ou plusieurs Services.  
> Avantage vs LoadBalancer : **un seul load balancer** pour toute l'application → moins coûteux.  
> Routing basé sur : **hostname** (optionnel) + **URL path** (obligatoire).  
> ⚠️ Nécessite un **Ingress Controller** installé — sans lui, les règles n'ont aucun effet.

---

## 1. Concepts clés

| Concept | Description |
|---------|-------------|
| **Ingress** | Objet Kubernetes qui définit les règles de routing HTTP(S) |
| **Ingress Controller** | Pod qui évalue et applique les règles (ex: NGINX, F5) |
| **IngressClass** | Identifie quel controller utiliser |
| **Backend** | Service ClusterIP cible (nom + port) |
| **Path Type** | `Exact` ou `Prefix` — définit comment le path est évalué |

---

## 2. Installer et vérifier l'Ingress Controller

```bash
# Vérifier que le controller tourne (namespace ingress-nginx)
kubectl get pods -n ingress-nginx
# → ingress-nginx-controller-xxx   1/1   Running

# Lister les IngressClasses disponibles
kubectl get ingressclasses
# → NAME    CONTROLLER             PARAMETERS   AGE
# → nginx   k8s.io/ingress-nginx   <none>       14m
```

> ⚠️ Si plusieurs IngressClasses ont l'annotation `ingressclass.kubernetes.io/is-default-class: "true"` → comportement ambigu. Les Ingress sans `ingressClassName` échoueront.

---

## 3. Règles Ingress

| Élément | Exemple | Description |
|---------|---------|-------------|
| Host (optionnel) | `next.example.com` | Si absent, toutes les requêtes entrantes sont traitées |
| Path | `/app` | Le path doit matcher pour que le trafic soit routé |
| Backend | `app-service:8080` | Nom du Service ClusterIP + port cible |

---

## 4. Path Types

| Type | Règle | Matche | Ne matche pas |
|------|-------|--------|---------------|
| `Exact` | `/app` | `/app` | `/app/`, `/app/test` |
| `Prefix` | `/app` | `/app`, `/app/`, `/application` | `/admin` |

---

## 5. Créer un Ingress

### Méthode impérative

```bash
# Créer un Ingress avec deux règles
# notation : <host>/<path>=<service>:<port>
kubectl create ingress next-app \
  --rule="next.example.com/app=app-service:8080" \
  --rule="next.example.com/metrics=metrics-service:9090"
```

### YAML

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: next-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$1   # annotation NGINX : réécrit l'URL
spec:
  ingressClassName: nginx                              # sélectionne le controller NGINX
  rules:
  - host: next.example.com                            # hostname optionnel
    http:
      paths:
      - path: /app
        pathType: Exact                               # match exact uniquement
        backend:
          service:
            name: app-service                         # Service ClusterIP cible
            port:
              number: 8080
      - path: /metrics
        pathType: Exact
        backend:
          service:
            name: metrics-service
            port:
              number: 9090
```

---

## 6. Inspecter et déboguer un Ingress

```bash
# Lister les Ingresses (voir host, address, ports)
kubectl get ingress

# Détails : règles, backends, events (utile pour debug)
kubectl describe ingress next-app
# → vérifier : Rules → Backends → erreurs "endpoints not found"

# Récupérer l'IP externe du load balancer
kubectl get ingress next-app \
  --output=jsonpath="{.status.loadBalancer.ingress[0]['ip']}"
```

> ⚠️ Si `<error: endpoints "app-service" not found>` → le Service n'existe pas ou le label selector est incorrect.

---

## 7. Accéder à un Ingress (test local)

```bash
# 1. Récupérer l'IP du load balancer
kubectl get ingress next-app -o jsonpath="{.status.loadBalancer.ingress[0]['ip']}"
# → 192.168.66.4

# 2. Ajouter le mapping dans /etc/hosts
sudo vim /etc/hosts
# ajouter : 192.168.66.4   next.example.com

# 3. Tester l'accès
wget next.example.com/app --timeout=5 --tries=1    # → 200 OK (Exact match)
wget next.example.com/app/ --timeout=5 --tries=1   # → 404 (trailing slash, Exact ne matche pas)
```

---

## 8. Créer les backends (Pods + Services)

```bash
# Créer les Pods avec les bons labels
kubectl run app --image=k8s.gcr.io/echoserver:1.10 --port=8080 -l app=app-service
kubectl run metrics --image=k8s.gcr.io/echoserver:1.10 --port=8080 -l app=metrics-service

# Créer les Services ClusterIP correspondants
kubectl create service clusterip app-service --tcp=8080:8080
kubectl create service clusterip metrics-service --tcp=9090:8080
```

---

## Exercices & Solutions

---

### Exercice 1 — Ingress multi-path

**Énoncé :**  
Namespace `webapp`. Déployer `frontend` (nginx:1.29.1-alpine, 2 replicas) et `api` (httpd:2.4.65-alpine, 2 replicas).  
Services ClusterIP sur port 80 pour chacun.  
Ingress `app.example.com` : `/` et `/app` → frontend, `/api` → api. IngressClass `nginx`.

---

**Solution**

```bash
# Créer le namespace
kubectl create namespace webapp
```

```yaml
# frontend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: webapp
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
        image: nginx:1.29.1-alpine
        ports:
        - containerPort: 80
```

```yaml
# api-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: webapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: httpd:2.4.65-alpine
        ports:
        - containerPort: 80
```

```yaml
# services.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: webapp
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: webapp
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 80
```

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
  namespace: webapp
spec:
  ingressClassName: nginx                   # controller NGINX
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix                    # Prefix pour matcher / et /app
        backend:
          service:
            name: frontend-service
            port:
              number: 80
      - path: /app
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
```

```bash
# Appliquer tous les manifests
kubectl apply -f frontend-deployment.yaml
kubectl apply -f api-deployment.yaml
kubectl apply -f services.yaml
kubectl apply -f ingress.yaml

# Vérifier l'Ingress
kubectl describe ingress webapp-ingress -n webapp

# Récupérer l'IP et ajouter dans /etc/hosts
kubectl get ingress webapp-ingress -n webapp \
  -o jsonpath="{.status.loadBalancer.ingress[0]['ip']}"
# → ajouter : <IP>   app.example.com dans /etc/hosts

# Tester
wget app.example.com/app --timeout=5 --tries=1
wget app.example.com/api --timeout=5 --tries=1
```

---

### Exercice 2 — Blue/Green + Canary Ingress

**Énoncé :**  
Namespace `production-apps`. Déployer `app-blue` (nginxdemos/hello:0.3-plain-text, 3 replicas) et `app-green` (nginxdemos/hello:0.4-plain-text, 3 replicas).  
Deux Ingress : un principal vers blue, un canary vers green (20% du trafic).  
Hostname : `app.production.com`.

---

**Solution**

```bash
kubectl create namespace production-apps
```

```yaml
# blue-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
  namespace: production-apps
spec:
  replicas: 3
  selector:
    matchLabels:
      app: app-blue
  template:
    metadata:
      labels:
        app: app-blue
    spec:
      containers:
      - name: app
        image: nginxdemos/hello:0.3-plain-text
        ports:
        - containerPort: 80
---
# green-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
  namespace: production-apps
spec:
  replicas: 3
  selector:
    matchLabels:
      app: app-green
  template:
    metadata:
      labels:
        app: app-green
    spec:
      containers:
      - name: app
        image: nginxdemos/hello:0.4-plain-text
        ports:
        - containerPort: 80
```

```yaml
# services.yaml
apiVersion: v1
kind: Service
metadata:
  name: blue-service
  namespace: production-apps
spec:
  selector:
    app: app-blue
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: green-service
  namespace: production-apps
spec:
  selector:
    app: app-green
  ports:
  - port: 80
    targetPort: 80
```

```yaml
# main-ingress.yaml — trafic principal vers blue (100% par défaut)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
  namespace: production-apps
spec:
  ingressClassName: nginx
  rules:
  - host: app.production.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blue-service
            port:
              number: 80
```

```yaml
# canary-ingress.yaml — 20% du trafic vers green
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: canary-ingress
  namespace: production-apps
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"          # active le mode canary
    nginx.ingress.kubernetes.io/canary-weight: "20"     # 20% du trafic vers green
spec:
  ingressClassName: nginx
  rules:
  - host: app.production.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: green-service
            port:
              number: 80
```

```bash
# Appliquer tous les manifests
kubectl apply -f blue-deployment.yaml
kubectl apply -f services.yaml
kubectl apply -f main-ingress.yaml
kubectl apply -f canary-ingress.yaml

# Récupérer l'IP du load balancer
kubectl get ingress main-ingress -n production-apps \
  -o jsonpath="{.status.loadBalancer.ingress[0]['ip']}"

# Ajouter dans /etc/hosts
sudo vim /etc/hosts
# → <IP>   app.production.com

# Tester la distribution du trafic (lancer plusieurs fois)
for i in $(seq 1 10); do wget -q -O- app.production.com | grep "Server"; done
# → ~80% réponses blue (v0.3), ~20% réponses green (v0.4)
```

---

## Points clés pour la CKA

| Concept | À retenir |
|---------|-----------|
| Ingress vs Service | Ingress = routing HTTP(S) multi-services. Service = routing vers Pods. |
| Ingress Controller | **Obligatoire** avant tout Ingress. Supposé pré-installé à l'exam. |
| IngressClass | `spec.ingressClassName: nginx` pour sélectionner le controller |
| Backend | Toujours un **Service ClusterIP** (pas NodePort, pas LoadBalancer) |
| `Exact` vs `Prefix` | Exact = match strict sans `/` final. Prefix = match avec suffixes. |
| Debug | `kubectl describe ingress` → vérifier backends + events |
| Test local | IP dans `/etc/hosts` → `<IP>   <hostname>` |
| Canary | Annotation `nginx.ingress.kubernetes.io/canary: "true"` + `canary-weight` |
| TLS | **Hors scope CKA** (couvert par CKS) |

---

## Pièges CKA

| Piège | Solution |
|-------|----------|
| Ingress sans controller | Règles ignorées — vérifier `kubectl get pods -n ingress-nginx` |
| Backend Service inexistant | `describe ingress` → `error: endpoints not found` — créer le Service |
| `Exact` avec trailing slash | Utiliser `Prefix` si les URLs peuvent avoir un `/` final |
| Plusieurs IngressClass par défaut | Une seule doit avoir `is-default-class: "true"` |
| Oublier `ingressClassName` | Sans ça, dépend de la classe par défaut — peut être ambigu |
| Backend = NodePort ou LoadBalancer | Non — le backend doit être un **ClusterIP** |
| DNS non configuré | Ajouter manuellement dans `/etc/hosts` pour les tests locaux |
