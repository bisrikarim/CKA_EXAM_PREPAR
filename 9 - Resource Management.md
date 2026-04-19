## 1. Concepts fondamentaux
 
| Primitive | Périmètre | Rôle |
|---|---|---|
| **requests/limits** | Container | Définit le minimum et maximum de ressources d'un container |
| **ResourceQuota** | Namespace | Plafond agrégé de ressources pour tout un namespace |
| **LimitRange** | Objet individuel (Pod, PVC...) | Contraintes et valeurs par défaut par objet |
 
### Unités de mesure
 
| Ressource | Unité | Exemples |
|---|---|---|
| CPU | millicores (m) | `500m` = 0.5 CPU, `"1"` = 1000m |
| Mémoire | bytes | `64Mi` = 64 mebibytes, `1Gi` = 1 gibibyte |
 
---
 
## 2. Resource Requests & Limits
 
### 2.1 Requests (minimum garanti)
 
Le scheduler utilise les **requests** pour choisir un nœud capable d'accueillir le Pod.  
Le nœud doit avoir au moins la somme des requests de tous les containers du Pod.
 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rate-limiter
spec:
  containers:
  - name: business-app
    image: bmuschko/nodejs-business-app:1.0.0
    ports:
    - containerPort: 8080
    resources:
      requests:
        memory: "256Mi"   # minimum mémoire garanti
        cpu: "1"          # minimum CPU garanti (= 1000m)
  - name: ambassador
    image: bmuschko/nodejs-ambassador:1.0.0
    ports:
    - containerPort: 8081
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
# → Le nœud doit avoir au minimum : 320Mi RAM + 1250m CPU disponibles
```
 
> Si les ressources sont insuffisantes sur tous les nœuds, le Pod reste en `Pending` avec les events `PodExceedsFreeCPU` ou `PodExceedsFreeMemory`.
 
### 2.2 Limits (maximum autorisé)
 
Les **limits** empêchent un container de consommer plus que le quota alloué.  
Si dépassé : le process est tué (mémoire) ou throttlé (CPU).
 
```yaml
resources:
  limits:
    memory: "256Mi"   # le container ne peut pas dépasser 256Mi
    cpu: "500m"       # le container est throttlé au-delà de 500m
```
 
### 2.3 Requests + Limits combinés (recommandé)
 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rate-limiter
spec:
  containers:
  - name: business-app
    image: bmuschko/nodejs-business-app:1.0.0
    resources:
      requests:
        memory: "256Mi"
        cpu: "1"
      limits:
        memory: "256Mi"   # bonne pratique : request = limit pour la mémoire
  - name: ambassador
    image: bmuschko/nodejs-ambassador:1.0.0
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "64Mi"
```
 
### 2.4 Bonnes pratiques
 
| Règle | Raison |
|---|---|
| Toujours définir `requests.memory` | Base pour le scheduling |
| Toujours définir `limits.memory` | Évite les OOM kills en cascade |
| `requests.memory` = `limits.memory` | Garantit la classe QoS `Guaranteed` |
| Toujours définir `requests.cpu` | Base pour le scheduling |
| Ne pas définir `limits.cpu` | Évite le throttling inutile |
 
### 2.5 Tableau des attributs disponibles
 
| Attribut | Description | Exemple |
|---|---|---|
| `resources.requests.cpu` | CPU minimum garanti | `500m` |
| `resources.requests.memory` | Mémoire minimum garantie | `64Mi` |
| `resources.requests.ephemeral-storage` | Stockage éphémère minimum | `4Gi` |
| `resources.limits.cpu` | CPU maximum autorisé | `500m` |
| `resources.limits.memory` | Mémoire maximum autorisée | `64Mi` |
| `resources.limits.ephemeral-storage` | Stockage éphémère maximum | `4Gi` |
 
---
 
## 3. ResourceQuota
 
La ResourceQuota définit un **plafond agrégé** de ressources pour un namespace entier.
 
### 3.1 Créer une ResourceQuota
 
```bash
kubectl create namespace team-awesome
```
 
```yaml
# awesome-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: awesome-quota
  namespace: team-awesome
spec:
  hard:
    pods: 2                  # max 2 Pods dans le namespace
    requests.cpu: "1"        # somme des CPU requests ≤ 1
    requests.memory: 1024Mi  # somme des memory requests ≤ 1024Mi
    limits.cpu: "4"          # somme des CPU limits ≤ 4
    limits.memory: 4096Mi    # somme des memory limits ≤ 4096Mi
```
 
```bash
kubectl apply -f awesome-quota.yaml
```
 
### 3.2 Inspecter une ResourceQuota
 
```bash
kubectl describe resourcequota awesome-quota -n team-awesome
# Resource          Used   Hard
# limits.cpu        2      4
# limits.memory     2Gi    4Gi
# pods              2      2
# requests.cpu      1      1
# requests.memory   1Gi    1Gi
```
 
### 3.3 Comportement à l'exécution
 
Quand une ResourceQuota est active, **tout Pod doit déclarer ses requests et limits** — sinon il est rejeté :
 
```bash
kubectl apply -f nginx-pod.yaml
# Error: pods "nginx" is forbidden: failed quota: awesome-quota:
# must specify limits.cpu, limits.memory, requests.cpu, requests.memory
```
 
Pod conforme à la quota :
 
```yaml
resources:
  requests:
    cpu: "0.5"
    memory: "512Mi"
  limits:
    cpu: "1"
    memory: "1024Mi"
```
 
Dépassement de la quota :
 
```bash
kubectl apply -f nginx-pod3.yaml
# Error: pods "nginx3" is forbidden: exceeded quota: awesome-quota,
# requested: pods=1,requests.cpu=500m,requests.memory=512Mi,
# used: pods=2,requests.cpu=1,requests.memory=1Gi,
# limited: pods=2,requests.cpu=1,requests.memory=1Gi
```
 
---
 
## 4. LimitRange
 
La LimitRange contraignit ou fixe des valeurs par défaut de ressources pour des **objets individuels** (Pod, container, PVC).
 
> **Règle** : ne créer qu'**un seul LimitRange par namespace** — plusieurs LimitRanges produisent un comportement non déterministe.
 
### 4.1 Ce qu'une LimitRange peut faire
 
- Imposer un min/max de CPU et mémoire par container ou Pod
- Imposer un min/max de stockage par PVC
- Définir des valeurs par défaut de requests/limits (injectées automatiquement)
- Imposer un ratio request/limit
### 4.2 Créer une LimitRange
 
```yaml
# cpu-resource-constraint.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-resource-constraint
spec:
  limits:
  - type: Container          # s'applique à chaque container
    defaultRequest:
      cpu: 200m              # request par défaut si non définie
    default:
      cpu: 200m              # limit par défaut si non définie
    min:
      cpu: 100m              # request/limit minimum autorisée
    max:
      cpu: "2"               # request/limit maximum autorisée
```
 
```bash
kubectl apply -f cpu-resource-constraint.yaml
```
 
### 4.3 Inspecter une LimitRange
 
```bash
kubectl describe limitrange cpu-resource-constraint
# Type        Resource   Min    Max   Default Request   Default Limit
# Container   cpu        100m   2     200m              200m
 
# Lister toutes les LimitRanges d'un namespace
kubectl get limitranges -n <namespace>
```
 
### 4.4 Comportements à l'exécution
 
#### Injection automatique des valeurs par défaut
 
Pod sans resource requirements → LimitRange injecte les valeurs par défaut :
 
```bash
kubectl describe pod nginx-without-resource-requirements
# Annotations: kubernetes.io/limit-ranger: LimitRanger plugin set:
#              cpu request for container nginx; cpu limit for container nginx
# Limits:
#   cpu: 200m
# Requests:
#   cpu: 200m
```
 
#### Rejet si hors des contraintes
 
```yaml
resources:
  requests:
    cpu: "50m"    # ← trop bas : min est 100m
  limits:
    cpu: "3"      # ← trop haut : max est 2
```
 
```bash
kubectl apply -f nginx-with-resource-requirements.yaml
# Error: pods "nginx-with-resource-requirements" is forbidden:
# minimum cpu usage per Container is 100m, but request is 50m,
# maximum cpu usage per Container is 2, but limit is 3
```
 
> Le message d'erreur **ne mentionne pas** le nom de la LimitRange — toujours vérifier avec `kubectl get limitranges` en cas d'erreur de création.
 
---
 
## 5. ResourceQuota vs LimitRange
 
| Critère | ResourceQuota | LimitRange |
|---|---|---|
| Périmètre | Namespace entier (agrégat) | Objet individuel |
| Contrôle | Somme totale des ressources | Min/max/défaut par objet |
| Effet | Bloque si quota dépassé | Injecte des défauts ou bloque si hors limites |
| Appliquer à | Pods, PVC, Secrets, ConfigMaps... | Container, Pod, PVC |
| Nombre par namespace | Plusieurs possibles | **Un seul recommandé** |
 
---
 
## 6. Commandes de référence rapide
 
```bash
# Requests/limits
kubectl describe pod <nom>            # voir les resources assignées
kubectl describe node <nom>           # voir la capacité et l'allocation du nœud
 
# ResourceQuota
kubectl create quota <nom> --hard=pods=2,requests.cpu=1 -n <ns>
kubectl get resourcequota -n <ns>
kubectl describe resourcequota <nom> -n <ns>
 
# LimitRange
kubectl get limitranges -n <ns>
kubectl describe limitrange <nom> -n <ns>
```
 
---
 
## 7. Exercices
 
### Exercice 1 — Pod avec resource requests et limits
 
**Solution :**
 
```yaml
# hello-world-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-world
spec:
  containers:
  - name: hello-world
    image: bmuschko/nodejs-hello-world:1.0.0
    ports:
    - containerPort: 3000
    resources:
      requests:
        cpu: "100m"
        memory: "500Mi"
        ephemeral-storage: "1Gi"
      limits:
        memory: "500Mi"
        ephemeral-storage: "2Gi"
    volumeMounts:
    - name: log-volume
      mountPath: /var/log
  volumes:
  - name: log-volume
    emptyDir: {}
```
 
```bash
kubectl apply -f hello-world-pod.yaml
 
# Inspecter le Pod et identifier le nœud
kubectl get pod hello-world -o wide
# → colonne NODE indique le nœud sélectionné par le scheduler
 
kubectl describe pod hello-world
# → section Containers > Requests/Limits confirme les valeurs
# → section Node indique le nœud
```
 
---
 
### Exercice 2 — ResourceQuota et comportement à l'exécution
 
**Solution :**
 
```yaml
# resourcequota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: app
  namespace: rq-demo
spec:
  hard:
    pods: "2"
    requests.cpu: "2"
    requests.memory: 500Mi
```
 
```bash
# 1. Créer le namespace et la ResourceQuota
kubectl create namespace rq-demo
kubectl apply -f resourcequota.yaml
```
 
```yaml
# pod-exceed.yaml — dépasse la quota mémoire (1Gi > 500Mi)
apiVersion: v1
kind: Pod
metadata:
  name: pod-exceed
  namespace: rq-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.25.3
    resources:
      requests:
        cpu: "0.5"
        memory: "1Gi"    # ← dépasse les 500Mi de la quota
      limits:
        cpu: "0.5"
        memory: "1Gi"
```
 
```bash
kubectl apply -f pod-exceed.yaml
# Error: pods "pod-exceed" is forbidden: exceeded quota: app,
# requested: requests.memory=1Gi,
# used: requests.memory=0,
# limited: requests.memory=500Mi
```
 
```yaml
# pod-valid.yaml — dans les limites de la quota
apiVersion: v1
kind: Pod
metadata:
  name: pod-valid
  namespace: rq-demo
spec:
  containers:
  - name: nginx
    image: nginx:1.25.3
    resources:
      requests:
        cpu: "0.5"
        memory: "200Mi"
      limits:
        cpu: "0.5"
        memory: "200Mi"
```
 
```bash
kubectl apply -f pod-valid.yaml
# → pod/pod-valid created
 
# Vérifier la consommation actuelle vs hard limits
kubectl describe resourcequota app -n rq-demo
# Resource          Used    Hard
# pods              1       2
# requests.cpu      500m    2
# requests.memory   200Mi   500Mi
```
 
---
 
### Exercice 3 — LimitRange : défauts et contraintes
 
**Solution :**
 
```bash
# 1. Créer les objets depuis setup.yaml (namespace d92 + LimitRange)
kubectl apply -f setup.yaml
 
# Inspecter la LimitRange créée
kubectl describe limitrange -n d92
```
 
#### Pod sans resource requirements → valeurs par défaut injectées
 
```bash
kubectl run pod-without-resource-requirements \
  --image=nginx:1.23.4-alpine \
  -n d92
 
kubectl describe pod pod-without-resource-requirements -n d92
# → Annotations: kubernetes.io/limit-ranger: LimitRanger plugin set: ...
# → Requests et Limits automatiquement injectés avec les valeurs default du LimitRange
```
 
#### Pod avec CPU request=400m, limit=1.5 → rejeté si hors limites
 
```yaml
# pod-more-cpu.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-more-cpu-resource-requirements
  namespace: d92
spec:
  containers:
  - name: nginx
    image: nginx:1.23.4-alpine
    resources:
      requests:
        cpu: "400m"
      limits:
        cpu: "1.5"
```
 
```bash
kubectl apply -f pod-more-cpu.yaml
# Comportement attendu : REJETÉ si 400m > max ou 1.5 > max défini dans le LimitRange
# Error: maximum cpu usage per Container is X, but limit is 1.5
```
 
#### Pod avec CPU request=350m, limit=400m → accepté si dans les limites
 
```yaml
# pod-less-cpu.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-less-cpu-resource-requirements
  namespace: d92
spec:
  containers:
  - name: nginx
    image: nginx:1.23.4-alpine
    resources:
      requests:
        cpu: "350m"
      limits:
        cpu: "400m"
```
 
```bash
kubectl apply -f pod-less-cpu.yaml
# Comportement attendu : CRÉÉ si 350m et 400m sont dans les bornes [min, max] du LimitRange
kubectl get pod pod-with-less-cpu-resource-requirements -n d92
# → Running
```
 
---
 
## Pièges CKA
 
| Piège | Solution |
|---|---|
| Pod en `Pending` sans raison évidente | Vérifier `kubectl describe pod` → events `PodExceedsFreeCPU` / `PodExceedsFreeMemory` |
| Pod rejeté par une quota sans message clair | Vérifier `kubectl describe resourcequota -n <ns>` |
| Erreur LimitRange sans nom de l'objet | Toujours vérifier `kubectl get limitranges -n <ns>` en cas d'erreur de création |
| Plusieurs LimitRanges dans un namespace | Comportement non déterministe — **un seul par namespace** |
| LimitRange ne s'applique pas aux Pods existants | Elle ne s'applique qu'aux **nouveaux** objets créés après sa mise en place |
| `requests.memory` oublié avec une ResourceQuota active | La création du Pod sera refusée — toujours définir requests ET limits quand une quota est présente |
