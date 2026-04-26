> **Objectif CKA couvert :** _Define and enforce Network Policies_

---

## 1. Concepts Fondamentaux

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
| **Flannel** | ❌ Non — accepte les objets mais ne les applique pas |
| **Cilium** | ✅ Oui — implémente un controller complet |
| **Calico** | ✅ Oui |
| **Weave** | ✅ Oui |

### Vérifier que Cilium est actif

```bash
# Vérifier les Pods Cilium dans kube-system
kubectl get pods -n kube-system
# Doit afficher : cilium-xxxxx (Running) + cilium-operator-xxxxx (Running)
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
kubectl get netpol                          # forme courte

# Lister les network policies d'un namespace spécifique
kubectl get netpol -n <namespace>

# Détailler une network policy (voir les règles ingress/egress)
kubectl describe networkpolicy <nom>
kubectl describe netpol <nom> -n <namespace>

# Appliquer une network policy depuis un fichier YAML
kubectl apply -f <fichier.yaml>

# Récupérer l'IP d'un Pod pour tests
kubectl get pod <pod-name> --template '{{.status.podIP}}'

# Tester la connectivité entre Pods
kubectl exec <pod-source> -it -- wget --spider --timeout=1 <IP-pod-cible>
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
[frontend] --port 80--> [backend] --port 6379--> [database]
    ✗ direct database access
```

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
      port: 6379
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
      port: 6379
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

### Exercice 1 — Contrôle cross-namespace

**Contexte :** Deux équipes dans des namespaces séparés (`team-alpha`, `team-beta`).

**Tâches :**
1. Créer une NetworkPolicy dans `team-alpha` qui autorise `alpha-app` à communiquer **uniquement** vers `team-beta` (+ DNS).
2. Créer une NetworkPolicy dans `team-beta` qui autorise `beta-app` à recevoir du trafic **uniquement** depuis `team-alpha` sur le port 80.
3. Vérifier : `alpha-app` → `beta-app` ✅ | `alpha-app` → internet ❌ | autre source → `beta-app` ❌

**Solution :**

```yaml
# Policy 1 : Egress de alpha-app vers team-beta + DNS
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
---
# Policy 2 : Ingress de beta-app depuis team-alpha sur port 80
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

```bash
# Vérification
kubectl exec alpha-app -n team-alpha -it -- wget --spider --timeout=1 <IP-beta-app>
# → remote file exists ✅

kubectl exec alpha-app -n team-alpha -it -- wget --spider --timeout=1 8.8.8.8
# → download timed out ✅ (externe bloqué)
```

---

### Exercice 2 — Architecture 3-tiers avec accès DB restreint

**Contexte :** Namespace `production` avec Pods `frontend`, `backend`, `database`.

**Règles à implémenter :**
- `frontend` → `backend` sur port 80 ✅
- `backend` → `database` sur port 6379 ✅
- `frontend` → `database` directement ❌
- Deny-all ingress par défaut

**Solution :** _(voir Section 6 complète ci-dessus)_

```bash
# Tests de validation
kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-backend>
# → remote file exists ✅

kubectl exec frontend -n production -it -- wget --spider --timeout=1 <IP-database>
# → download timed out ✅ (bloqué)

kubectl exec backend -n production -it -- wget --spider --timeout=1 <IP-database>
# → remote file exists ✅
```

---

### Exercice 3 — Isoler un namespace complet

**Contexte :** Le namespace `staging` ne doit recevoir aucun trafic depuis d'autres namespaces, mais les Pods dans `staging` peuvent communiquer entre eux.

**Solution :**

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
    - podSelector: {}          # Autorise UNIQUEMENT les Pods du même namespace
    # Note : namespaceSelector absent = même namespace implicitement
```

```bash
# Vérification : Pod depuis default ne peut pas atteindre staging
kubectl exec some-pod -n default -it -- wget --spider --timeout=1 <IP-pod-staging>
# → download timed out ✅

# Pod dans staging peut atteindre un autre Pod dans staging
kubectl exec pod-a -n staging -it -- wget --spider --timeout=1 <IP-pod-b-staging>
# → remote file exists ✅
```

---

### Exercice 4 — Monitoring : autoriser Prometheus à scraper tous les namespaces

**Contexte :** Prometheus tourne dans le namespace `monitoring`, doit pouvoir scraper les métriques (port 9090) depuis **tous** les namespaces.

**Solution :**

```yaml
# Autoriser le trafic entrant depuis le namespace monitoring sur port 9090
# À appliquer dans chaque namespace applicatif (ou en boucle)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: production        # Répéter pour chaque namespace cible
spec:
  podSelector: {}              # Tous les Pods exposant des métriques
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring  # Namespace Prometheus
    ports:
    - protocol: TCP
      port: 9090               # Port métriques Prometheus
```

```bash
# Labeliser le namespace monitoring si ce n'est pas fait
kubectl label namespace monitoring kubernetes.io/metadata.name=monitoring

# Vérifier
kubectl exec prometheus-pod -n monitoring -it -- wget --spider --timeout=1 <IP-app-pod>:9090
# → remote file exists ✅
```

---

### Exercice 5 — Deny-all + ouverture progressive

**Contexte :** Namespace `secure-app`. Partir de zéro : tout bloquer, puis autoriser uniquement `app-client` → `app-server` sur port 8080.

**Solution :**

```yaml
# Étape 1 : Deny all ingress + egress
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
---
# Étape 2 : Ouvrir sélectivement
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-server
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      app: app-server           # Cible : le serveur
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: app-client        # Source : le client uniquement
    ports:
    - protocol: TCP
      port: 8080
---
# Étape 3 : Autoriser l'egress du client vers le serveur (+ DNS)
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
  - ports:                       # DNS
    - protocol: UDP
      port: 53
```

```bash
# Vérification complète
kubectl exec app-client -n secure-app -it -- wget --spider --timeout=1 <IP-app-server>:8080
# → remote file exists ✅

# Un tiers ne peut pas atteindre le serveur
kubectl exec some-other-pod -n secure-app -it -- wget --spider --timeout=1 <IP-app-server>:8080
# → download timed out ✅
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

### Checklist de création d'une NetworkPolicy

1. ✅ Identifier le Pod **cible** (`podSelector`)
2. ✅ Définir la **direction** (`Ingress`, `Egress`, ou les deux)
3. ✅ Spécifier la **source/destination** (podSelector, namespaceSelector, ou IP block)
4. ✅ Préciser les **ports** si nécessaire
5. ✅ Ne pas oublier le **port 53** si l'egress est restreint

---

## 10. Pièges Fréquents à l'Examen ⚠️

- **Flannel ne supporte pas les NetworkPolicy** → vérifier le CNI avant de tester
- **`podSelector: {}` ne veut pas dire "aucun Pod"**, cela signifie **"tous les Pods"**
- **Oublier le port DNS (53)** quand l'egress est restreint → les Pods ne résolvent plus les noms
- **`namespaceSelector` seul** sélectionne tous les Pods du namespace, pas juste certains
- **`from:` avec `-podSelector` ET `-namespaceSelector` séparés** = OR logique (deux règles)
- **`from:` avec `namespaceSelector` ET `podSelector` au même niveau** = AND logique (un Pod dans un namespace spécifique)
- **Les Network Policies sont namespace-scoped** → elles ne peuvent pas cibler des Pods dans d'autres namespaces comme cible (`podSelector`) mais peuvent les utiliser comme source/destination
- **`kubectl get netpol`** n'affiche pas les règles détaillées → toujours utiliser `kubectl describe`

### Différence critique : OR vs AND dans les sélecteurs

```yaml
# OR : deux sources distinctes (pod OU namespace)
ingress:
- from:
  - podSelector:
      matchLabels:
        role: frontend
  - namespaceSelector:
      matchLabels:
        env: prod

# AND : pods spécifiques DANS un namespace spécifique
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: prod
    podSelector:          # Même niveau = AND (pas de tiret supplémentaire)
      matchLabels:
        role: frontend
```

---

> 📚 **Ressource complémentaire :** [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes) — scénarios visuels pratiques pour s'entraîner avant l'examen.
