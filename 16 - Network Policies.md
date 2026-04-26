# 1. Concepts Fondamentaux

### Comportement par défaut de Kubernetes

- Par défaut, **tout Pod peut communiquer avec tout autre Pod**, peu importe le namespace.
- Les IPs des Pods sont uniques dans tout le cluster (gérées par le plugin CNI).
- Ce comportement expose une **surface d'attaque importante** → une NetworkPolicy remédie à cela.

### Qu'est-ce qu'une Network Policy ?

Une **NetworkPolicy** est l'équivalent d'un firewall pour les Pods. Elle définit :
- **Quels Pods** elle cible (`podSelector`)
- **Quel trafic** est autorisé : entrant (`ingress`) et/ou sortant (`egress`)
- **Depuis/vers quels Pods, namespaces ou IPs**
- **Sur quels ports**

> ⚠️ **Important :** Les Network Policies ne s'appliquent pas aux Services, uniquement aux Pods.

---

## 2. Prérequis : Le Network Policy Controller

Une NetworkPolicy **sans controller = aucun effet**. Le controller évalue et applique les règles.

| CNI | Support Network Policies |
|-----|--------------------------|
| **Flannel / kindnet** | ❌ Non — accepte les objets mais ne les applique pas |
| **Calico** | ✅ Oui — stable, recommandé pour labs minikube |
| **Cilium** | ✅ Oui — avancé, complexe à installer sur minikube |
| **Weave** | ✅ Oui |

### ✅ Setup recommandé pour le lab CKA (minikube + Calico)

```bash
# Supprimer le cluster existant si besoin
minikube delete -p multi-node

# Recréer avec Calico comme CNI
minikube start \
  --driver=docker \
  --kubernetes-version=v1.33.5 \
  --nodes=4 \
  -p multi-node \
  --cpus=2 \
  --memory=2048 \
  --cni=calico

# Vérifier que Calico est bien actif
kubectl get pods -n kube-system | grep calico
# Doit afficher : calico-node-xxxx (Running) + calico-kube-controllers-xxxx (Running)
```

---

## 3. Anatomie d'une NetworkPolicy

### Attributs principaux (`spec`)

| Attribut | Description |
|----------|-------------|
| `podSelector` | Sélectionne les Pods cibles de la policy (par labels) |
| `policyTypes` | Types de trafic concernés : `Ingress`, `Egress`, ou les deux |
| `ingress` | Règles pour le trafic entrant (sections `from` + `ports`) |
| `egress` | Règles pour le trafic sortant (sections `to` + `ports`) |

### Sélecteurs dans `from` / `to`

| Sélecteur | Effet |
|-----------|-------|
| `podSelector` | Filtre par labels de Pods dans le **même namespace** |
| `namespaceSelector` | Filtre tous les Pods d'un ou plusieurs **namespaces** par label |
| `namespaceSelector` + `podSelector` | Filtre des Pods spécifiques dans des namespaces spécifiques |

---

## 4. Commandes kubectl Essentielles

```bash
# Lister toutes les network policies du namespace courant
kubectl get networkpolicy
kubectl get netpol                               # forme courte

# Lister les network policies d'un namespace spécifique
kubectl get netpol -n <namespace>

# Détailler une network policy (voir les règles ingress/egress)
kubectl describe networkpolicy <nom>
kubectl describe netpol <nom> -n <namespace>

# Appliquer une network policy depuis un fichier YAML
kubectl apply -f <fichier.yaml>

# Récupérer l'IP d'un Pod (méthode 1 — template)
kubectl get pod <pod-name> -n <namespace> --template '{{.status.podIP}}'

# Récupérer l'IP d'un Pod (méthode 2 — wide, plus lisible)
kubectl get pod <pod-name> -n <namespace> -o wide

# Tester la connectivité entre Pods
kubectl exec <pod-source> -n <namespace> -it -- wget --spider --timeout=1 <IP-pod-cible>
kubectl exec <pod-source> -n <namespace> -it -- wget --spider --timeout=1 <IP-pod-cible>:<port>
```

> ⚠️ **`kubectl create networkpolicy` n'existe pas** — toujours utiliser l'approche déclarative (YAML + `kubectl apply`).

---

## 5. Exemples YAML Commentés

### Exemple 1 — Autoriser le trafic entrant depuis un Pod spécifique

**Scénario :** Seul le Pod `coffee-shop` peut accéder au Pod `payment-processor`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
spec:
  podSelector:              # Cible le Pod auquel la règle s'applique
    matchLabels:
      app: payment-processor
      role: api
  ingress:                  # Règles de trafic ENTRANT
  - from:
    - podSelector:          # Autorise uniquement les Pods avec ce label
        matchLabels:
          app: coffee-shop
  # Note : pas de "policyTypes" explicite → Kubernetes infère "Ingress"
  # Note : pas de "ports" → tous les ports sont autorisés pour ce trafic
```

> **Résultat :** `grocery-store` → `payment-processor` = **BLOQUÉ** | `coffee-shop` → `payment-processor` = **AUTORISÉ**

---

### Exemple 2 — Politique "Deny All" par défaut (principe du moindre privilège)

**Scénario :** Bloquer tout le trafic dans un namespace, puis ouvrir sélectivement.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: internal-tools  # S'applique à ce namespace
spec:
  podSelector: {}            # {} = s'applique à TOUS les Pods du namespace
  policyTypes:
  - Ingress                  # Bloque tout trafic entrant
  - Egress                   # Bloque tout trafic sortant
```

> ✅ **Bonne pratique :** Commencer par "deny all", puis ajouter des policies additives pour ouvrir uniquement ce qui est nécessaire.

---

### Exemple 3 — Restriction sur un port spécifique

**Scénario :** N'autoriser l'accès au Pod `api` que sur le port 80, depuis les Pods `consumer`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: port-allow
  namespace: internal-tools
spec:
  podSelector:
    matchLabels:
      app: api              # Cible les Pods "api"
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: consumer     # Depuis les Pods "consumer" uniquement
    ports:                  # Restriction au niveau port
    - protocol: TCP
      port: 80              # Uniquement le port 80
```

---

### Exemple 4 — Sélection multi-namespace

**Scénario :** Autoriser le trafic depuis tous les Pods du namespace `team-alpha`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-team-alpha
  namespace: team-beta
spec:
  podSelector:
    matchLabels:
      app: beta-app
  ingress:
  - from:
    - namespaceSelector:       # Filtre par label de namespace
        matchLabels:
          kubernetes.io/metadata.name: team-alpha  # Label auto-appliqué aux namespaces
    ports:
    - protocol: TCP
      port: 80
```

---

### Exemple 5 — Egress avec DNS (cas courant en exam)

**Scénario :** Autoriser un Pod à aller vers un namespace spécifique ET résoudre le DNS.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-with-dns
  namespace: team-alpha
spec:
  podSelector:
    matchLabels:
      app: alpha-app
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: team-beta  # Vers team-beta uniquement
  - ports:                      # Autoriser DNS (obligatoire si egress restreint)
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

> ⚠️ **Piège exam :** Si tu bloques l'egress et qu'un Pod a besoin de résoudre des noms DNS, tu dois **explicitement autoriser le port 53 UDP/TCP** sinon aucune résolution de nom ne fonctionnera.

---

## 6. Scénario Complet : Architecture 3-Tiers

**Frontend → Backend → Database**

```
[frontend] --port 80--> [backend] --port 80--> [database]
    ✗ direct database access
```

> ⚠️ **Note lab :** En production réelle, la DB écouterait sur le port 6379 (Redis). Dans ce lab, on utilise `nginx:alpine` qui écoute uniquement sur le **port 80**. Les policies sont adaptées en conséquence. Sur l'examen CKA, les images utilisées écouteront bien sur les bons ports.

### Policy 1 : Database — n'accepte que le backend

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: database
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 80              # 80 car nginx:alpine — serait 6379 avec une vraie image Redis
```

### Policy 2 : Backend — accepte frontend, peut accéder à la DB

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:                          # Vers la base de données
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 80              # 80 car nginx:alpine — serait 6379 avec une vraie image Redis
  - ports:                       # DNS toujours autorisé
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

### Policy 3 : Deny-all par défaut pour le namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

---

## 7. Vérification et Debug

```bash
# Tester la connectivité (timeout = échec = policy active)
kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-database>
# → "wget: download timed out" = bloqué ✅

kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-backend>
# → "remote file exists" = autorisé ✅

# Voir toutes les policies et leurs Pod selectors
kubectl get netpol -n production

# Inspecter les règles détaillées
kubectl describe netpol database-policy -n production
```

> 💡 **Outil visuel :** [networkpolicy.io](https://networkpolicy.io) — éditeur graphique pour valider ses règles avant de les appliquer.

---

## 8. Exercices Pratiques

> 💡 **Workflow type pour chaque exercice :**
> 1. **Setup** — créer les namespaces et les Pods
> 2. **Tester AVANT** — vérifier que tout communique librement
> 3. **Créer les fichiers YAML** — nommer clairement les fichiers
> 4. **Appliquer** — `kubectl apply -f`
> 5. **Tester APRÈS** — valider que les règles sont bien actives

---

### Exercice 1 — Contrôle cross-namespace

**Contexte :** Deux équipes dans des namespaces séparés (`team-alpha`, `team-beta`).

**Objectifs :**
- `alpha-app` peut joindre `beta-app` sur port 80 ✅
- `alpha-app` ne peut pas joindre internet ❌
- Aucune autre source ne peut joindre `beta-app` ❌

#### Étape 1 — Setup : créer les namespaces et les Pods

```bash
# Créer les namespaces
kubectl create namespace team-alpha
kubectl create namespace team-beta

# Créer les Pods
kubectl run alpha-app --image=nginx:alpine -n team-alpha -l app=alpha-app --port=80
kubectl run beta-app  --image=nginx:alpine -n team-beta  -l app=beta-app  --port=80

# Vérifier que les Pods sont Running
kubectl get pods -n team-alpha
kubectl get pods -n team-beta
```

#### Étape 2 — Récupérer les IPs

```bash
# Méthode recommandée : affiche IP + Node en une seule commande
kubectl get pod beta-app -n team-beta -o wide

# Ou directement l'IP :
kubectl get pod beta-app -n team-beta --template '{{.status.podIP}}'
# Exemple de résultat : 10.244.2.5
```

#### Étape 3 — Tester AVANT (tout doit passer)

```bash
kubectl exec alpha-app -n team-alpha -it -- wget --spider --timeout=1 <IP-beta-app>
# → remote file exists  (normal, pas encore de policy)
```

#### Étape 4 — Créer les fichiers YAML

**Fichier : `netpol-alpha-egress.yaml`**

```yaml
# Egress de alpha-app : uniquement vers team-beta + DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: alpha-egress-policy
  namespace: team-alpha
spec:
  podSelector:
    matchLabels:
      app: alpha-app
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: team-beta
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

**Fichier : `netpol-beta-ingress.yaml`**

```yaml
# Ingress de beta-app : uniquement depuis team-alpha sur port 80
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: beta-ingress-policy
  namespace: team-beta
spec:
  podSelector:
    matchLabels:
      app: beta-app
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: team-alpha
    ports:
    - protocol: TCP
      port: 80
```

#### Étape 5 — Appliquer les policies

```bash
kubectl apply -f netpol-alpha-egress.yaml
kubectl apply -f netpol-beta-ingress.yaml

# Vérifier
kubectl get netpol -n team-alpha
kubectl get netpol -n team-beta
```

#### Étape 6 — Vérifier APRÈS

```bash
# ✅ alpha-app → beta-app : doit passer
kubectl exec alpha-app -n team-alpha -it -- wget --spider --timeout=1 <IP-beta-app>
# → remote file exists

# ❌ alpha-app → internet : doit être bloqué
kubectl exec alpha-app -n team-alpha -it -- wget --spider --timeout=1 8.8.8.8
# → download timed out
```

---

### Exercice 2 — Architecture 3-tiers avec accès DB restreint

**Contexte :** Namespace `production` avec Pods `frontend`, `backend`, `database`.

**Objectifs :**
- `frontend` → `backend` sur port 80 ✅
- `backend` → `database` sur port 6379 ✅
- `frontend` → `database` directement ❌
- Deny-all ingress par défaut

#### Étape 1 — Setup

```bash
kubectl create namespace production

kubectl run frontend -n production --image=nginx:alpine -l tier=frontend --port=80
kubectl run backend  -n production --image=nginx:alpine -l tier=backend  --port=80
kubectl run database -n production --image=nginx:alpine -l tier=database --port=6379

# Voir tous les Pods + leurs IPs en une commande
kubectl get pods -n production -o wide
```

#### Étape 2 — Récupérer les IPs

```bash
kubectl get pod frontend -n production --template '{{.status.podIP}}'
kubectl get pod backend  -n production --template '{{.status.podIP}}'
kubectl get pod database -n production --template '{{.status.podIP}}'
```

#### Étape 3 — Tester AVANT

```bash
# Tout doit passer avant les policies
kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-database>
# → remote file exists (normal)
```

#### Étape 4 — Créer les fichiers YAML

**Fichier : `netpol-deny-all.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

**Fichier : `netpol-database.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: database
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 80              # 80 car nginx:alpine — serait 6379 avec une vraie image Redis
```

**Fichier : `netpol-backend.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 80              # 80 car nginx:alpine — serait 6379 avec une vraie image Redis
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

#### Étape 5 — Appliquer

```bash
kubectl apply -f netpol-deny-all.yaml
kubectl apply -f netpol-database.yaml
kubectl apply -f netpol-backend.yaml

kubectl get netpol -n production
```

#### Étape 6 — Vérifier APRÈS

```bash
# ✅ frontend → backend : doit passer
kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-backend>
# → remote file exists

# ❌ frontend → database : doit être bloqué
kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-database>
# → download timed out

# ✅ backend → database : doit passer (port 80 car nginx:alpine)
kubectl exec backend -n production -it -- wget --spider --timeout=1 <IP-database>:80
# → remote file exists
```

---

### Exercice 3 — Isoler un namespace complet

**Contexte :** Le namespace `staging` ne doit recevoir aucun trafic depuis d'autres namespaces, mais les Pods dans `staging` peuvent communiquer entre eux.

#### Étape 1 — Setup

```bash
kubectl create namespace staging

kubectl run pod-a --image=nginx:alpine -n staging --port=80
kubectl run pod-b --image=nginx:alpine -n staging --port=80
kubectl run pod-c --image=nginx:alpine              --port=80  # dans le namespace default

kubectl get pods -n staging -o wide
kubectl get pods -o wide  # default
```

#### Étape 2 — Récupérer les IPs

```bash
kubectl get pod pod-a -n staging --template '{{.status.podIP}}'
kubectl get pod pod-b -n staging --template '{{.status.podIP}}'
```

#### Étape 3 — Tester AVANT

```bash
# Pod depuis default → staging : doit passer avant la policy
kubectl exec pod-c -it -- wget --spider --timeout=1 <IP-pod-a>
# → remote file exists (normal)
```

#### Étape 4 — Créer le fichier YAML

**Fichier : `netpol-isolate-staging.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: isolate-namespace
  namespace: staging
spec:
  podSelector: {}              # Tous les Pods du namespace
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}          # Autorise UNIQUEMENT les Pods du même namespace (staging)
    # Pas de namespaceSelector → implicitement : même namespace
```

#### Étape 5 — Appliquer

```bash
kubectl apply -f netpol-isolate-staging.yaml
kubectl get netpol -n staging
```

#### Étape 6 — Vérifier APRÈS

```bash
# ❌ Pod depuis default → staging : doit être bloqué
kubectl exec pod-c -it -- wget --spider --timeout=1 <IP-pod-a>
# → download timed out

# ✅ Pod dans staging → autre Pod dans staging : doit passer
kubectl exec pod-a -n staging -it -- wget --spider --timeout=1 <IP-pod-b>
# → remote file exists
```

---

### Exercice 4 — Monitoring : autoriser Prometheus à scraper tous les namespaces

**Contexte :** Prometheus tourne dans le namespace `monitoring`, doit pouvoir scraper les métriques (port 8080) de Pods dans `production`.

#### Étape 1 — Setup

```bash
kubectl create namespace monitoring
kubectl create namespace production  # si pas déjà créé

kubectl run prometheus  --image=nginx:alpine -n monitoring -l app=prometheus --port=8080
kubectl run app-metrics --image=nginx:alpine -n production -l app=metrics    --port=8080

kubectl get pods -n monitoring -o wide
kubectl get pods -n production -o wide
```

#### Étape 2 — Récupérer les IPs

```bash
kubectl get pod app-metrics -n production --template '{{.status.podIP}}'
```

#### Étape 3 — Tester AVANT

```bash
kubectl exec prometheus -n monitoring -it -- wget --spider --timeout=1 <IP-app-metrics>:8080
# → remote file exists (normal)
```

#### Étape 4 — Créer le fichier YAML

**Fichier : `netpol-allow-prometheus.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: metrics             # Cible les Pods exposant des métriques
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring  # Depuis le namespace monitoring
    ports:
    - protocol: TCP
      port: 80 # nginx:alpine écoute sur le port 80 uniquement — serait 8080 avec une vraie image d'application
```

#### Étape 5 — Appliquer

```bash
# Vérifier que le label du namespace monitoring est présent (auto-appliqué en général)
kubectl get namespace monitoring --show-labels
# Si le label kubernetes.io/metadata.name est absent :
kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring

kubectl apply -f netpol-allow-prometheus.yaml
kubectl get netpol -n production
```

#### Étape 6 — Vérifier APRÈS

```bash
# ✅ Prometheus → app-metrics : doit passer
kubectl exec prometheus -n monitoring -it -- wget --spider --timeout=1 <IP-app-metrics>:8080
# → remote file exists

# ❌ Un Pod en dehors de monitoring ne peut pas scraper
kubectl exec pod-c -it -- wget --spider --timeout=1 <IP-app-metrics>:8080
# → download timed out
```

---

### Exercice 5 — Deny-all + ouverture progressive

**Contexte :** Namespace `secure-app`. Tout bloquer, puis autoriser uniquement `app-client` → `app-server` sur port 8080.

#### Étape 1 — Setup

```bash
kubectl create namespace secure-app

kubectl run app-server   --image=nginx:alpine -n secure-app -l app=app-server --port=8080
kubectl run app-client   --image=nginx:alpine -n secure-app -l app=app-client --port=8080
kubectl run app-intruder --image=nginx:alpine -n secure-app -l app=intruder   --port=8080

kubectl get pods -n secure-app -o wide
```

#### Étape 2 — Récupérer les IPs

```bash
kubectl get pod app-server -n secure-app --template '{{.status.podIP}}'
```

#### Étape 3 — Tester AVANT

```bash
# Tout le monde peut joindre app-server avant les policies
kubectl exec app-client   -n secure-app -it -- wget --spider --timeout=1 <IP-app-server>:8080
kubectl exec app-intruder -n secure-app -it -- wget --spider --timeout=1 <IP-app-server>:8080
# → remote file exists (normal)
```

#### Étape 4 — Créer les fichiers YAML

**Fichier : `netpol-deny-all-secure.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: secure-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Fichier : `netpol-allow-server-ingress.yaml`**

```yaml
# Ingress sur app-server : uniquement depuis app-client
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-server
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      app: app-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: app-client
    ports:
    - protocol: TCP
      port: 8080
```

**Fichier : `netpol-allow-client-egress.yaml`**

```yaml
# Egress de app-client : vers app-server + DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-egress
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      app: app-client
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: app-server
    ports:
    - protocol: TCP
      port: 8080
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

#### Étape 5 — Appliquer dans l'ordre

```bash
kubectl apply -f netpol-deny-all-secure.yaml
kubectl apply -f netpol-allow-server-ingress.yaml
kubectl apply -f netpol-allow-client-egress.yaml

kubectl get netpol -n secure-app
```

#### Étape 6 — Vérifier APRÈS

```bash
# ✅ app-client → app-server : doit passer
kubectl exec app-client -n secure-app -it -- wget --spider --timeout=1 <IP-app-server>:8080
# → remote file exists

# ❌ app-intruder → app-server : doit être bloqué
kubectl exec app-intruder -n secure-app -it -- wget --spider --timeout=1 <IP-app-server>:8080
# → download timed out
```

---

## 9. Points Clés pour la CKA ✅

### À mémoriser absolument

| Concept | Essentiel |
|---------|-----------|
| **Par défaut** | Tout Pod parle à tout Pod sans restriction |
| **Sans CNI controller** | Les NetworkPolicy objects existent mais **n'ont aucun effet** |
| **`podSelector: {}`** | S'applique à **tous** les Pods du namespace |
| **`policyTypes` absent** | K8s infère le type selon les règles présentes |
| **Policies additives** | Plusieurs policies sur un même Pod = **union** des règles autorisées |
| **DNS port 53** | À autoriser explicitement si l'egress est restreint |
| **Imperatif impossible** | `kubectl create networkpolicy` n'existe **PAS** |
| **Services exclus** | Les NetworkPolicy ne filtrent pas les Services, uniquement les Pods |
| **Calico sur minikube** | `--cni=calico` → CNI recommandé pour pratiquer la CKA |

### Checklist de création d'une NetworkPolicy

1. ✅ Identifier le Pod **cible** (`podSelector`)
2. ✅ Définir la **direction** (`Ingress`, `Egress`, ou les deux)
3. ✅ Spécifier la **source/destination** (podSelector, namespaceSelector, ou IP block)
4. ✅ Préciser les **ports** si nécessaire
5. ✅ Ne pas oublier le **port 53** si l'egress est restreint
6. ✅ Toujours tester **AVANT** et **APRÈS** l'application

---

## 10. Pièges Fréquents à l'Examen ⚠️

- **Flannel/kindnet ne supporte pas les NetworkPolicy** → vérifier le CNI avant de tester
- **`podSelector: {}` ne veut pas dire "aucun Pod"**, cela signifie **"tous les Pods"**
- **Oublier le port DNS (53)** quand l'egress est restreint → les Pods ne résolvent plus les noms
- **`namespaceSelector` seul** sélectionne tous les Pods du namespace, pas juste certains
- **`from:` avec `-podSelector` ET `-namespaceSelector` séparés** = OR logique (deux règles)
- **`from:` avec `namespaceSelector` ET `podSelector` au même niveau** = AND logique (un Pod dans un namespace spécifique)
- **Les Network Policies sont namespace-scoped** → elles ne peuvent pas cibler des Pods dans d'autres namespaces comme cible (`podSelector`) mais peuvent les utiliser comme source/destination
- **`kubectl get netpol`** n'affiche pas les règles détaillées → toujours utiliser `kubectl describe`
- **Tester toujours AVANT et APRÈS** l'application d'une policy pour valider son effet

### Différence critique : OR vs AND dans les sélecteurs

```yaml
# OR : deux sources distinctes (pod OU namespace)
ingress:
- from:
  - podSelector:
      matchLabels:
        role: frontend
  - namespaceSelector:           # tiret = règle séparée = OR
      matchLabels:
        env: prod

# AND : pods spécifiques DANS un namespace spécifique
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: prod
    podSelector:                 # même niveau, pas de tiret = AND
      matchLabels:
        role: frontend
```

---

> 📚 **Ressource complémentaire :** [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes) — scénarios visuels pratiques pour s'entraîner avant l'examen.
