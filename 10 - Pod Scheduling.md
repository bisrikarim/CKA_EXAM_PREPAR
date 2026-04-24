> Le **scheduler** assigne les Pods aux nodes. Il filtre les nodes compatibles puis les classe par score.  
> Algorithme : **Filtering** (nodes compatibles) → **Scoring** (meilleur node) → **Assignation**.

---

## 0. Commandes de base

```bash
# Vérifier que le scheduler tourne bien sur le control-plane
kubectl get pods -n kube-system | grep scheduler

# Voir sur quel node tourne un pod (3 façons)
kubectl get pod nginx -o wide
kubectl get pod nginx -o yaml | grep nodeName:
kubectl describe pod nginx | grep Node:
```

---

## 1. Node Selector — hard requirement

> Contrainte **stricte** : le pod ne se schedule QUE sur les nodes avec le label exact.

```bash
# Ajouter un label sur un node
kubectl label node multi-node-m03 disk=ssd

# Vérifier les labels de tous les nodes
kubectl get nodes --show-labels
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  nodeSelector:      # hard requirement : node doit avoir ce label exactement
    disk: ssd        # key=value exact
  containers:
  - name: nginx
    image: nginx:1.27.1
```

---

## 2. Node Affinity — hard ou soft requirement

> Plus flexible que nodeSelector. Supporte des **opérateurs logiques** (In, NotIn, Exists...).  
> `requiredDuringScheduling` = **hard** (obligatoire).  
> `preferredDuringScheduling` = **soft** (préférence, pas garantie).  
> `IgnoredDuringExecution` = les règles ne s'appliquent qu'au scheduling, pas après.

### Types de Node Affinity

| Type | Description |
|------|-------------|
| `requiredDuringSchedulingIgnoredDuringExecution` | Hard : règles obligatoires au scheduling, ignorées après |
| `preferredDuringSchedulingIgnoredDuringExecution` | Soft : préférences au scheduling, ignorées après |

### Opérateurs disponibles

| Opérateur | Comportement |
|-----------|-------------|
| `In` | La valeur du label est dans la liste |
| `NotIn` | La valeur du label n'est PAS dans la liste |
| `Exists` | Le label key existe (peu importe la valeur) |
| `DoesNotExist` | Le label key n'existe pas |
| `Gt` | Valeur du label numériquement supérieure |
| `Lt` | Valeur du label numériquement inférieure |

```yaml
# Hard requirement : le node doit avoir disk=ssd OU disk=hdd
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:  # hard
        nodeSelectorTerms:
        - matchExpressions:
          - key: disk
            operator: In        # le node doit avoir une de ces valeurs
            values:
            - ssd
            - hdd
  containers:
  - name: nginx
    image: nginx:1.27.1
```

---

## 3. Node Anti-Affinity

> Même syntaxe que node affinity mais avec les opérateurs **négatifs** (`NotIn`, `DoesNotExist`).  
> Utilisé pour **éloigner** les pods de certains nodes (haute dispo, séparation de workloads).

```yaml
# Anti-affinity : éviter les nodes avec disk=ssd ou disk=ebs
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disk
            operator: NotIn     # exclut les nodes ayant ces valeurs
            values:
            - ssd
            - ebs
  containers:
  - name: nginx
    image: nginx:1.27.1
```

---

## 4. Taints & Tolerations

> **Taint** sur un node = "personne ne vient ici sauf autorisation explicite".  
> **Toleration** sur un pod = "j'accepte ce taint, je peux aller sur ce node".  
> Différence avec anti-affinity : les taints **repoussent** les pods, l'affinity les **attire**.

### Taint effects

| Effect | Comportement |
|--------|-------------|
| `NoSchedule` | Hard block : aucun pod sans toleration ne se schedule |
| `PreferNoSchedule` | Soft : évite de scheduler mais pas garanti |
| `NoExecute` | Block + **évicte** les pods déjà en cours d'exécution |

```bash
# Ajouter un taint sur un node
kubectl taint node multi-node-m02 special=true:NoSchedule

# Vérifier les taints d'un node
kubectl get node multi-node-m02 -o yaml | grep -C 3 taints:

# Supprimer un taint (ajouter - à la fin)
kubectl taint node multi-node-m02 special=true:NoSchedule-
```

```yaml
# Toleration sur un pod pour accepter le taint special=true:NoSchedule
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  tolerations:
  - key: "special"        # doit correspondre exactement au key du taint
    operator: "Equal"     # Equal = key + value doivent matcher
    value: "true"         # doit correspondre exactement à la value du taint
    effect: "NoSchedule"  # doit correspondre exactement à l'effect du taint
  containers:
  - name: nginx
    image: nginx:1.27.1
```

---

## 5. Pod Topology Spread Constraints

> Répartit les pods **uniformément** sur des topologies (zones, nodes...).  
> S'applique uniquement aux **nouveaux pods** (ne rééquilibre pas les pods existants).  
> Contraintes trop strictes → pods en **Pending**.

```yaml
# Deployment avec 6 replicas répartis équitablement sur les zones
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 6
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      topologySpreadConstraints:
      - maxSkew: 1                                  # écart max de pods entre zones = 1
        topologyKey: topology.kubernetes.io/zone    # répartir par zone (label réservé)
        whenUnsatisfiable: DoNotSchedule            # si impossible → pod reste Pending
        labelSelector:
          matchLabels:
            app: web                                # s'applique uniquement à ces pods
      containers:
      - name: nginx
        image: nginx:1.27.1
```

---

## Exercices & Solutions

---

### Exercice 1 — NodeSelector + Node Affinity

**Énoncé :**  
Inspecter les nodes et leurs labels. Labeler un node `color=green` et un autre `color=red`.  
Créer un pod `nginx:1.27.1` avec nodeSelector `color=green`. Vérifier le node.  
Modifier le pod pour accepter `color=green` OU `color=red` via node affinity.

---

**Solution étape 1 — NodeSelector**

```bash
# Lister les nodes et leurs labels
kubectl get nodes --show-labels

# Labeler node 1 avec color=green
kubectl label node multi-node-m02 color=green

# Labeler node 2 avec color=red
kubectl label node multi-node-m03 color=red
```

```yaml
# pod.yaml — nodeSelector color=green (hard requirement exact)
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  nodeSelector:
    color: green          # le pod ne peut aller QUE sur le node avec color=green
  containers:
  - name: nginx
    image: nginx:1.27.1
```

```bash
# Créer le pod
kubectl apply -f pod.yaml

# Vérifier sur quel node il tourne (doit être multi-node-m02)
kubectl get pod app -o wide
```

---

**Solution étape 2 — Node Affinity color=green OU color=red**

```yaml
# pod.yaml — node affinity : color=green OU color=red
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: color
            operator: In        # accepte green OU red
            values:
            - green
            - red
  containers:
  - name: nginx
    image: nginx:1.27.1
```

```bash
# Supprimer l'ancien pod et recréer
kubectl delete pod app
kubectl apply -f pod.yaml

# Vérifier le node (doit être multi-node-m02 ou multi-node-m03)
kubectl get pod app -o wide
```

---

### Exercice 2 — Taints & Tolerations

**Énoncé :**  
Créer un pod `nginx:1.27.1`. Vérifier sur quel node il tourne.  
Ajouter un taint `exclusive=yes:NoExecute` sur ce node.  
Modifier le pod pour ajouter la toleration correspondante.  
Observer le comportement. Supprimer le taint. Le pod continue-t-il de tourner ?

---

**Solution**

```bash
# Créer le pod
kubectl run app --image=nginx:1.27.1 --dry-run=client -o yaml > pod.yaml
kubectl apply -f pod.yaml

# Vérifier sur quel node il tourne
kubectl get pod app -o wide

# Ajouter un taint NoExecute sur ce node (remplacer <node> par le node trouvé)
kubectl taint node <node> exclusive=yes:NoExecute
# NoExecute : le pod est immédiatement évicté car il n'a pas de toleration

# Observer : le pod est évicté → Pending ou reschedule sur un autre node
kubectl get pod app -o wide
```

```yaml
# pod.yaml — avec toleration pour exclusive=yes:NoExecute
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  tolerations:
  - key: "exclusive"      # correspond au key du taint
    operator: "Equal"     # key + value doivent matcher exactement
    value: "yes"          # correspond à la value du taint
    effect: "NoExecute"   # correspond à l'effect du taint
  containers:
  - name: nginx
    image: nginx:1.27.1
```

```bash
# Recréer le pod avec la toleration
kubectl delete pod app
kubectl apply -f pod.yaml

# Le pod peut maintenant se scheduler sur le node tainté
# Sur cluster multi-nodes : le pod peut aller sur n'importe quel node toléré
kubectl get pod app -o wide

# Supprimer le taint
kubectl taint node <node> exclusive=yes:NoExecute-

# Après suppression du taint : le pod CONTINUE de tourner sur le même node
# La suppression du taint ne force pas de rescheduling
kubectl get pod app -o wide
```

---

## Pièges CKA

| Piège | Solution |
|-------|----------|
| nodeSelector vs nodeAffinity | nodeSelector = exact match uniquement, nodeAffinity = opérateurs logiques |
| `requiredDuring` vs `preferredDuring` | required = hard (pod Pending si pas de node), preferred = soft (best effort) |
| Oublier `effect` dans une toleration | Sans effect, la toleration ne matche aucun taint |
| `NoExecute` vs `NoSchedule` | NoExecute évicte les pods déjà en cours, NoSchedule bloque seulement les nouveaux |
| topologySpreadConstraints | Ne rééquilibre PAS les pods existants, seulement les nouveaux |
| Supprimer un taint | Ajouter `-` à la fin : `kubectl taint node <node> key=value:effect-` |
| `operator: Exists` dans toleration | Ne nécessite pas de `value`, tolère tous les taints avec ce key |
