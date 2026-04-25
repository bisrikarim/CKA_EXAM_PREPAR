> Le **Gateway API** = successeur de l'Ingress. Plus expressif, extensible, et role-oriented.  
> Avantages vs Ingress : pas d'annotations propriétaires, meilleur modèle de permissions, multi-protocoles.  
> ⚠️ Nécessite l'installation des **CRDs** + un **Gateway Controller**.

---

## 1. Ressources Gateway API

| Ressource | Rôle | Géré par |
|-----------|------|----------|
| `GatewayClass` | Décrit le type de controller Gateway | Platform provider (cloud) |
| `Gateway` | Instance du load balancer, définit les listeners | Admin cluster |
| `HTTPRoute` / `GRPCRoute` | Règles de routing HTTP/GRPC vers les Services | Développeur |
| `ReferenceGrant` | Autorise les références cross-namespace | Admin cluster |

> Relation : `GatewayClass` → `Gateway` → `HTTPRoute` → `Service`

---

## 2. Installer les CRDs Gateway API

```bash
# Installer les CRDs Gateway API v1.3.0
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml

# Vérifier que les CRDs sont installés
kubectl get crds | grep gateway.networking.k8s.io
# → gatewayclasses.gateway.networking.k8s.io
# → gateways.gateway.networking.k8s.io
# → grpcroutes.gateway.networking.k8s.io
# → httproutes.gateway.networking.k8s.io
# → referencegrants.gateway.networking.k8s.io
```

---

## 3. Installer un Gateway Controller (Envoy)

```bash
# Installer Envoy Gateway via Helm
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.4.2 \
  -n envoy-gateway-system --create-namespace

# Attendre que le controller soit disponible
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway \
  --for=condition=Available
```

---

## 4. Créer une GatewayClass

> La GatewayClass référence le controller installé.  
> Peut être déjà présente dans les environnements cloud — vérifier avant de créer.

```bash
# Vérifier les GatewayClasses existantes
kubectl get gatewayclasses
```

```yaml
# gateway-class.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller   # nom du controller Envoy
```

```bash
# Créer la GatewayClass
kubectl apply -f gateway-class.yaml

# Vérifier (ACCEPTED doit être True)
kubectl get gatewayclasses
# → NAME    CONTROLLER                                      ACCEPTED   AGE
# → envoy   gateway.envoyproxy.io/gatewayclass-controller   True       31s
```

---

## 5. Créer un Gateway

> Le Gateway définit le point d'entrée réseau (listener = protocole + port).

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: hello-world-gateway
spec:
  gatewayClassName: envoy       # référence la GatewayClass par nom
  listeners:
  - name: http
    protocol: HTTP              # protocole du listener
    port: 80                    # port d'écoute
```

```bash
# Créer le Gateway
kubectl apply -f gateway.yaml

# Vérifier (PROGRAMMED doit passer à True)
kubectl get gateways
# → NAME                  CLASS   ADDRESS   PROGRAMMED   AGE
# → hello-world-gateway   envoy             False        16s
```

---

## 6. Créer un HTTPRoute

> L'HTTPRoute définit les règles de routing vers les Services backends.  
> `parentRefs` = Gateway auquel cette route est attachée.  
> `weight` = proportion du trafic vers ce backend (utile pour le canary).

```yaml
# httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hello-world-httproute
spec:
  parentRefs:
  - name: hello-world-gateway       # Gateway auquel cette route est attachée
  hostnames:
  - "hello-world.exposed"           # hostname sur lequel le routing s'applique
  rules:
  - backendRefs:
    - group: ""                     # "" = core API group (Services standards)
      kind: Service
      name: web                     # nom du Service cible
      port: 3000                    # port du Service
      weight: 1                     # proportion du trafic (canary : ex. 80/20)
    matches:
    - path:
        type: PathPrefix            # PathPrefix ou Exact
        value: /                    # path de matching
```

```bash
# Créer l'HTTPRoute
kubectl apply -f httproute.yaml

# Vérifier
kubectl get httproutes
# → NAME                    HOSTNAMES                 AGE
# → hello-world-httproute   ["hello-world.exposed"]   64s
```

---

## 7. Accéder au Gateway (sans load balancer externe)

```bash
# Récupérer le nom du Service Envoy créé par le Gateway
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,\
  gateway.envoyproxy.io/owning-gateway-name=hello-world-gateway \
  -o jsonpath='{.items[0].metadata.name}')

# Port-forward vers le Service Envoy
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8889:80 &

# Tester l'accès (avec /etc/hosts configuré : <IP> hello-world.exposed)
curl hello-world.exposed:8889
```

---

## 8. ReferenceGrant — Cross-namespace

> Autorise un HTTPRoute dans un namespace à référencer un Service dans un autre namespace.  
> Sans ReferenceGrant, les références cross-namespace sont **refusées**.

```yaml
# reference-grant.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-production-gateway
  namespace: staging              # namespace du Service cible
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: production         # namespace de l'HTTPRoute source
  to:
  - group: ""
    kind: Service                 # autorise les références vers les Services du namespace staging
```

---

## Exercices & Solutions

---

### Exercice 1 — Gateway API basic (NGINX Gateway Fabric)

**Énoncé :**  
Namespace `default`. Deployments `web-app` (nginx:1.21, 2 replicas) et `api-app` (httpd:2.4, 2 replicas).  
Services ClusterIP port 80.  
Gateway `main-gateway` HTTP port 80, hostname `example.local`.  
HTTPRoute `app-routes` : `/web` → web-app, `/api` → api-app. PathPrefix matching.

---

**Solution**

```bash
# Installer NGINX Gateway Fabric (CRDs + controller)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml

helm install ngf oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
  --create-namespace -n nginx-gateway

# Attendre que le controller soit prêt
kubectl wait --timeout=5m -n nginx-gateway deployment/ngf-nginx-gateway-fabric \
  --for=condition=Available
```

```yaml
# deployments-services.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:1.21
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-app
  template:
    metadata:
      labels:
        app: api-app
    spec:
      containers:
      - name: api
        image: httpd:2.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-app
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api-app
spec:
  selector:
    app: api-app
  ports:
  - port: 80
    targetPort: 80
```

```yaml
# main-gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: default
spec:
  gatewayClassName: nginx           # GatewayClass NGINX Gateway Fabric
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: "example.local"       # hostname sur lequel le Gateway écoute
```

```yaml
# app-routes.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-routes
  namespace: default
spec:
  parentRefs:
  - name: main-gateway              # attaché au Gateway main-gateway
  hostnames:
  - "example.local"
  rules:
  - matches:
    - path:
        type: PathPrefix            # PathPrefix : /web matche /web, /web/, /web/anything
        value: /web
    backendRefs:
    - name: web-app                 # Service web-app
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-app                 # Service api-app
      port: 80
```

```bash
# Appliquer tous les manifests
kubectl apply -f deployments-services.yaml
kubectl apply -f main-gateway.yaml
kubectl apply -f app-routes.yaml

# Vérifier le Gateway (PROGRAMMED = True)
kubectl get gateway main-gateway

# Vérifier l'HTTPRoute (ACCEPTED = True, PARENTREF = main-gateway)
kubectl get httproute app-routes

# Récupérer l'IP du Gateway
kubectl get gateway main-gateway -o jsonpath='{.status.addresses[0].value}'

# Ajouter dans /etc/hosts
# → <IP>   example.local

# Tester (avec rewrite-target si 404)
curl http://example.local/web
curl http://example.local/api
```

---

### Exercice 2 — Cross-namespace Gateway (NGINX Gateway Fabric)

**Énoncé :**  
Namespaces `production` et `staging`.  
`prod-web` (nginx:1.22, 3 replicas) dans `production`. `staging-web` (nginx:1.21, 2 replicas) dans `staging`.  
Gateway `gateway` dans `production`, HTTP port 80, hostname `example.com`.  
HTTPRoute `prod-route` dans `production` : `/app` Exact → prod-web.  
HTTPRoute `staging-route` dans `staging` : `/staging` Prefix → staging-web (cross-namespace).  
ReferenceGrant pour autoriser le cross-namespace. Headers d'identification.

---

**Solution**

```bash
# Créer les namespaces
kubectl create namespace production
kubectl create namespace staging
```

```yaml
# prod-setup.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-web
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: prod-web
  template:
    metadata:
      labels:
        app: prod-web
    spec:
      containers:
      - name: web
        image: nginx:1.22
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: prod-web
  namespace: production
spec:
  selector:
    app: prod-web
  ports:
  - port: 80
    targetPort: 80
```

```yaml
# staging-setup.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: staging-web
  namespace: staging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: staging-web
  template:
    metadata:
      labels:
        app: staging-web
    spec:
      containers:
      - name: web
        image: nginx:1.21
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: staging-web
  namespace: staging
spec:
  selector:
    app: staging-web
  ports:
  - port: 80
    targetPort: 80
```

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway
  namespace: production             # Gateway dans le namespace production
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: "example.com"
    allowedRoutes:
      namespaces:
        from: All                   # autorise les HTTPRoutes de tous les namespaces
```

```yaml
# prod-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: prod-route
  namespace: production
spec:
  parentRefs:
  - name: gateway
    namespace: production           # même namespace que le Gateway
  hostnames:
  - "example.com"
  rules:
  - matches:
    - path:
        type: Exact                 # Exact : /app uniquement, pas /app/
        value: /app
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Environment       # header d'identification de l'environnement
          value: production
    backendRefs:
    - name: prod-web
      port: 80
```

```yaml
# reference-grant.yaml — autorise staging-route à référencer gateway dans production
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-production-gateway
  namespace: production             # namespace du Gateway (cible)
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: staging              # autorise les HTTPRoutes du namespace staging
  to:
  - group: gateway.networking.k8s.io
    kind: Gateway                   # à référencer les Gateways de production
```

```yaml
# staging-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: staging-route
  namespace: staging                # HTTPRoute dans staging
spec:
  parentRefs:
  - name: gateway
    namespace: production           # référence le Gateway dans production (cross-namespace)
  hostnames:
  - "example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix            # Prefix : /staging, /staging/, /staging/anything
        value: /staging
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Environment
          value: staging            # header d'identification
    backendRefs:
    - name: staging-web
      namespace: staging            # Service dans le namespace staging
      port: 80
```

```bash
# Appliquer dans l'ordre (ReferenceGrant avant staging-route)
kubectl apply -f prod-setup.yaml
kubectl apply -f staging-setup.yaml
kubectl apply -f gateway.yaml
kubectl apply -f reference-grant.yaml
kubectl apply -f prod-route.yaml
kubectl apply -f staging-route.yaml

# Vérifier le Gateway
kubectl get gateway gateway -n production

# Vérifier les HTTPRoutes
kubectl get httproute prod-route -n production
kubectl get httproute staging-route -n staging

# Récupérer l'IP et ajouter dans /etc/hosts
kubectl get gateway gateway -n production -o jsonpath='{.status.addresses[0].value}'
# → <IP>   example.com dans /etc/hosts

# Tester
curl http://example.com/app         # → 200 OK (production, Exact match)
curl http://example.com/app/        # → 404 (Exact ne matche pas /app/)
curl http://example.com/staging     # → 200 OK (staging, Prefix match)
curl http://example.com/staging/    # → 200 OK (Prefix matche /staging/)
```

---

## Points clés pour la CKA

| Concept | À retenir |
|---------|-----------|
| Gateway API vs Ingress | Gateway API = successeur. Plus expressif, pas d'annotations propriétaires. |
| Ordre d'installation | CRDs → Controller → GatewayClass → Gateway → HTTPRoute |
| GatewayClass | Vérifier si déjà présente avant de créer (`kubectl get gatewayclasses`) |
| `parentRefs` | Obligatoire dans HTTPRoute — référence le Gateway parent |
| `weight` | Permet le canary/blue-green dans les `backendRefs` |
| `PathPrefix` vs `Exact` | PathPrefix = `/app` matche `/app/`, `/app/x`. Exact = `/app` uniquement. |
| Cross-namespace | Nécessite un `ReferenceGrant` dans le namespace cible |
| `allowedRoutes` | Sur le listener du Gateway — contrôle quels namespaces peuvent attacher des routes |
| Debug Gateway | `kubectl get gateway` → PROGRAMMED=True. `kubectl get httproute` → ACCEPTED=True |
| ingress2gateway | Outil de migration Ingress → Gateway API (hors scope exam) |

---

## Pièges CKA

| Piège | Solution |
|-------|----------|
| CRDs non installés | `kubectl get crds \| grep gateway` → installer si absent |
| GatewayClass ACCEPTED=False | Controller non installé ou `controllerName` incorrect |
| Gateway PROGRAMMED=False | GatewayClass incorrecte ou controller pas prêt |
| HTTPRoute non accepté | `parentRefs` incorrect ou Gateway dans mauvais namespace |
| Cross-namespace sans ReferenceGrant | HTTPRoute refusé — créer le ReferenceGrant dans le namespace cible |
| `allowedRoutes` manquant | Sans `from: All`, seules les routes du même namespace sont acceptées |
| Oublier `namespace` dans `parentRefs` | Obligatoire si Gateway dans un namespace différent de l'HTTPRoute |
| `Exact` avec trailing slash → 404 | Utiliser `PathPrefix` si les URLs peuvent avoir un `/` final |
