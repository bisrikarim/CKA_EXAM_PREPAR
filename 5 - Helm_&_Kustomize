## 1. Contexte
 
Kubernetes permet de créer des objets via des commandes `kubectl` impératives ou via des **manifests YAML** déclaratifs. Pour gérer un stack applicatif complet (Deployment + ConfigMap + Service...), gérer chaque manifest individuellement n'est pas pratique.
 
Deux outils open source répondent à ce besoin :
 
| Outil | Rôle principal |
|---|---|
| **Helm** | Package manager + templating engine |
| **Kustomize** | Configuration management + composition de manifests |
 
---
 
## 2. Helm
 
### 2.1 Concepts clés
 
- **Chart** = archive TAR contenant les manifests, valeurs par défaut et métadonnées d'une application.
- **Repository** = serveur hébergeant des charts.
- **Release** = instance installée d'un chart sur un cluster.
- **Artifact Hub** = interface web pour découvrir des charts publics.
> L'exam CKA ne demande **pas** de créer ou publier des charts — seulement de **consommer** des charts existants.
 
### 2.2 Workflow complet
 
#### Étape 1 — Identifier un chart
 
Recherche sur [Artifact Hub](https://artifacthub.io) par mot-clé (ex: `jenkins`).
 
![Résultats de recherche Jenkins sur Artifact Hub](artifacthub-search-jenkins.png)
 
Cliquer sur un résultat affiche la description, le repository source et les valeurs configurables.
 
![Page de détail du chart Jenkins sur Artifact Hub](artifacthub-jenkins-detail.png)
 
#### Étape 2 — Ajouter le repository
 
```bash
# Lister les repositories enregistrés (vide par défaut)
helm repo list
# → Error: no repositories to show
 
# Ajouter le repository Jenkins
helm repo add jenkinsci https://charts.jenkins.io/
# → "jenkinsci" has been added to your repositories
 
# Vérifier
helm repo list
# NAME       URL
# jenkinsci  https://charts.jenkins.io/
```
 
#### Étape 3 — Rechercher les versions disponibles
 
```bash
helm search repo jenkinsci
# NAME               CHART VERSION   APP VERSION   DESCRIPTION
# jenkinsci/jenkins  5.8.26          2.492.2       ...
 
# Lister toutes les versions disponibles
helm search repo jenkinsci --versions
```
 
#### Étape 4 — Installer un chart
 
```bash
# Installation basique (version spécifique, namespace default)
helm install my-jenkins jenkinsci/jenkins --version 5.8.25
 
# Installation avec valeurs personnalisées + namespace dédié
helm install my-jenkins jenkinsci/jenkins --version 5.8.25 \
  --set controller.adminUser=boss \
  --set controller.adminPassword=password \
  -n jenkins --create-namespace
```
 
> Deux façons de passer des valeurs custom :
> - `--set key=value` → directement en ligne de commande
> - `--values fichier.yaml` → via un fichier YAML d'overrides
 
```bash
# Inspecter les valeurs par défaut d'un chart
helm show values jenkinsci/jenkins
 
# Vérifier les objets créés par le chart
kubectl get all
```
 
#### Étape 5 — Lister les charts installés
 
```bash
# Namespace courant
helm list
 
# Tous les namespaces
helm list --all-namespaces
# NAME        NAMESPACE   REVISION   STATUS     CHART
# my-jenkins  default     1          deployed   jenkins-5.8.25
```
 
#### Étape 6 — Mettre à jour un chart
 
```bash
# Récupérer les dernières versions disponibles dans les repositories
helm repo update
 
# Upgrader vers une nouvelle version
helm upgrade my-jenkins jenkinsci/jenkins --version 5.8.26
# → Release "my-jenkins" has been upgraded. Happy Helming!
```
 
#### Étape 7 — Désinstaller un chart
 
```bash
# Supprime tous les objets Kubernetes gérés par le chart
helm uninstall my-jenkins
 
# Si installé dans un namespace spécifique
helm uninstall my-jenkins -n jenkins
```
 
> La commande peut prendre jusqu'à 30 secondes (attente du grace period des workloads).
 
---
 
## 3. Kustomize
 
Kustomize est **intégré nativement à kubectl** depuis Kubernetes 1.14. Il supporte trois cas d'usage principaux :
 
| Use case | Description |
|---|---|
| **Générer** des manifests | Ex: créer un ConfigMap depuis un fichier `.properties` |
| **Ajouter** une config commune | Ex: même namespace et labels sur plusieurs manifests |
| **Patcher** des manifests | Ex: ajouter un securityContext à un Deployment |
 
Le fichier central est toujours nommé **`kustomization.yaml`** (nom imposé, non modifiable).
 
### Deux modes d'exécution
 
```bash
# Mode 1 : affiche le résultat transformé (dry-run)
kubectl kustomize <target>
 
# Mode 2 : applique les ressources dans le cluster
kubectl apply -k <target>
```
 
---
 
### 3.1 Composer des manifests
 
Combiner plusieurs manifests en un seul fichier YAML.
 
**Structure :**
```
.
├── kustomization.yaml
├── web-app-deployment.yaml
└── web-app-service.yaml
```
 
**`kustomization.yaml` :**
```yaml
resources:
- web-app-deployment.yaml
- web-app-service.yaml
```
 
```bash
# Affiche les deux manifests combinés séparés par "---"
kubectl kustomize ./
```
 
---
 
### 3.2 Générer des manifests depuis d'autres sources
 
Générer automatiquement ConfigMap et Secret depuis des fichiers `.properties`.
 
**Structure :**
```
.
├── config
│   ├── db-config.properties
│   └── db-secret.properties
├── kustomization.yaml
└── web-app-pod.yaml
```
 
**`kustomization.yaml` :**
```yaml
configMapGenerator:
- name: db-config
  files:
  - config/db-config.properties
 
secretGenerator:
- name: db-creds
  files:
  - config/db-secret.properties
 
resources:
- web-app-pod.yaml
```
 
```bash
# Kustomize ajoute automatiquement un suffix de hash au nom (ex: db-config-t4c79h4mtt)
kubectl apply -k ./
# configmap/db-config-t4c79h4mtt unchanged
# secret/db-creds-4t9dmgtf9h unchanged
# pod/web-app created
 
# Afficher le résultat sans créer les objets
kubectl kustomize ./
```
 
> Le suffix de hash garantit que les Pods redémarrent automatiquement si la config change.  
> Ce comportement est configurable via `generatorOptions` dans le kustomization file.
 
---
 
### 3.3 Ajouter une configuration commune à plusieurs manifests
 
Appliquer le même namespace et les mêmes labels sur tous les manifests référencés.
 
**`kustomization.yaml` :**
```yaml
namespace: persistence
commonLabels:
  team: helix
resources:
- web-app-deployment.yaml
- web-app-service.yaml
```
 
```bash
# Créer le namespace d'abord
kubectl create namespace persistence
 
# Appliquer — les objets sont créés dans le namespace "persistence" avec le label "team: helix"
kubectl apply -k ./
```
 
---
 
### 3.4 Patcher une collection de manifests
 
Fusionner un manifest existant avec un patch YAML (ex: ajouter un securityContext).
 
**`kustomization.yaml` :**
```yaml
resources:
- nginx-deployment.yaml
patchesStrategicMerge:
- security-context.yaml
```
 
**`security-context.yaml` (le patch) :**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  template:
    spec:
      containers:
      - name: nginx
        securityContext:
          runAsUser: 1000
          runAsGroup: 3000
          fsGroup: 2000
```
 
```bash
# Vérifier le résultat du patch
kubectl kustomize ./
# → Le Deployment nginx contient désormais le securityContext injecté
```
 
---
 
## 4. Helm vs Kustomize — Comparaison
 
| Critère | Helm | Kustomize |
|---|---|---|
| **Installation** | Exécutable séparé à installer | Intégré à `kubectl` |
| **Courbe d'apprentissage** | Plus élevée (templating, workflow) | Faible (YAML standard) |
| **Packaging** | Chart TAR + Chart.yaml + values.yaml | YAML + kustomization.yaml dans Git |
| **Versioning** | Version sémantique dans Chart.yaml | Git commit/tag |
| **Usage principal** | Distribution et packaging | Configuration et composition |
 
> Ces outils sont **complémentaires**, pas exclusifs. La plupart des outils GitOps (Argo CD, Flux) supportent les deux.
 
---
 
## 5. Points clés pour la CKA
 
- Les exécutables Helm et Kustomize sont **préinstallés** sur les nœuds de l'exam — inutile de mémoriser les instructions d'installation.
- L'URL d'Artifact Hub ne sera probablement **pas accessible** pendant l'exam — l'URL du repository sera fournie dans l'énoncé.
- Maîtriser : `helm repo add`, `helm search repo`, `helm install`, `helm upgrade`, `helm uninstall`.
- Maîtriser : `kubectl kustomize`, `kubectl apply -k`.
---
 
## 6. Exercices
 
### Exercice 1 — Helm : installer Prometheus
 
Installer la stack de monitoring Prometheus via le chart `kube-prometheus-stack`.
 
**Solution :**
 
```bash
# 1. Rechercher le chart sur Artifact Hub → repository : prometheus-community
#    URL : https://prometheus-community.github.io/helm-charts
 
# 2. Ajouter le repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
 
# 3. Mettre à jour les informations des repositories
helm repo update
 
# 4. Lister les versions disponibles du chart
helm search repo prometheus-community/kube-prometheus-stack --versions
 
# 5. Installer le chart (dernière version)
helm install prometheus prometheus-community/kube-prometheus-stack
 
# 6. Vérifier le chart installé
helm list
# NAME        NAMESPACE   REVISION   STATUS     CHART
# prometheus  default     1          deployed   kube-prometheus-stack-x.x.x
 
# 7. Vérifier le Service créé
kubectl get service prometheus-operated
# NAME                  TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
# prometheus-operated   ClusterIP   None         <none>        9090/TCP
 
# 8. Port-forward vers le dashboard Prometheus
kubectl port-forward service/prometheus-operated 8080:9090
# → Ouvrir http://localhost:8080 dans le navigateur
 
# 9. Arrêter le port-forward (Ctrl+C) puis désinstaller
helm uninstall prometheus
```
 
---
 
### Exercice 2 — Kustomize : composer, modifier et patcher des manifests
 
#### Partie A — Créer et gérer deux manifests avec Kustomize
 
```bash
# 1. Créer le répertoire
mkdir manifests && cd manifests
```
 
**`pod.yaml` :**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.21.1
```
 
**`configmap.yaml` :**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logs-config
data:
  dir: /etc/logs/traffic.log
```
 
**`kustomization.yaml` :**
```yaml
resources:
- pod.yaml
- configmap.yaml
```
 
```bash
# 2. Créer les deux objets en une seule commande déclarative
kubectl apply -k ./
# configmap/logs-config created
# pod/nginx created
 
# 3. Modifier la valeur dans configmap.yaml
#    Changer : dir=/etc/logs/traffic.log
#    En :      dir=/etc/logs/traffic-log.txt
# (éditer le fichier manuellement)
 
# 4. Appliquer la modification
kubectl apply -k ./
# configmap/logs-config configured
 
# 5. Supprimer les deux objets en une seule commande
kubectl delete -k ./
# configmap/logs-config deleted
# pod/nginx deleted
```
 
#### Partie B — Appliquer un namespace commun avec Kustomize
 
**Structure :**
```
.
├── kustomization.yaml
└── pod.yaml
```
 
**`pod.yaml` :**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.21.1
```
 
**`kustomization.yaml` :**
```yaml
namespace: t012
resources:
- pod.yaml
```
 
```bash
# Afficher le manifest transformé avec le namespace injecté (sans créer l'objet)
kubectl kustomize ./
```
 
```yaml
# Résultat attendu :
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: t012   # ← injecté par Kustomize
spec:
  containers:
  - name: nginx
    image: nginx:1.21.1
```
