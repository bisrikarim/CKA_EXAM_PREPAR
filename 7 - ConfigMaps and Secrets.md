## 1. Concepts fondamentaux
 
Kubernetes propose deux primitives pour centraliser la configuration :
 
| Primitive | Type de données | Usage typique |
|---|---|---|
| **ConfigMap** | Plain-text | URLs, flags, fichiers JSON/YAML, propriétés |
| **Secret** | Base64-encodé | Mots de passe, clés API, certificats SSL, clés SSH |
 
Les deux sont **découplés du cycle de vie du Pod** — on peut modifier la config sans redéployer le Pod.
 
![Schéma des deux modes de consommation ConfigMap et Secret depuis un Pod](captues/configmap-secret-consumption.png)
 
> **Important** : Base64 est un **encodage**, pas un **chiffrement**. N'importe qui ayant accès au Secret peut décoder la valeur. Pour du vrai chiffrement en production : utiliser **Bitnami Sealed Secrets** ou un gestionnaire externe (HashiCorp Vault, AWS Secrets Manager).
 
---
 
## 2. ConfigMaps
 
### 2.1 Créer un ConfigMap
 
Quatre sources possibles :
 
| Option | Exemple | Description |
|---|---|---|
| `--from-literal` | `--from-literal=DB_HOST=mysql` | Paires clé-valeur en ligne de commande |
| `--from-env-file` | `--from-env-file=config.env` | Fichier de variables d'env (`KEY=value` par ligne) |
| `--from-file` | `--from-file=app-config.json` | Fichier à contenu arbitraire (JSON, XML, YAML...) |
| `--from-file` | `--from-file=config-dir/` | Répertoire contenant plusieurs fichiers |
 
> `--from-env-file` attend un fichier de variables d'env style `.env`.  
> `--from-file` est fait pour des fichiers de config structurés (JSON, properties...).
 
```bash
# Depuis des literals
kubectl create configmap db-config \
  --from-literal=DB_HOST=mysql-service \
  --from-literal=DB_USER=backend
 
# Depuis un fichier JSON
kubectl create configmap db-config --from-file=db.json
 
# Depuis un répertoire
kubectl create configmap db-config --from-file=config-dir/
```
 
```yaml
# Résultat YAML (depuis literals)
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-config
data:                        # pas de section spec — juste data
  DB_HOST: mysql-service
  DB_USER: backend
```
 
```yaml
# Résultat YAML (depuis un fichier JSON)
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-config
data:
  db.json: |-               # le nom du fichier devient la clé
    {
      "db": {
        "host": "mysql-service",
        "user": "backend"
      }
    }
```
 
---
 
### 2.2 Consommer un ConfigMap comme variables d'environnement
 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - image: bmuschko/web-app:1.0.1
    name: backend
    envFrom:
    - configMapRef:
        name: db-config     # injecte TOUTES les clés du ConfigMap comme env vars
```
 
```bash
# Vérifier les variables injectées
kubectl exec backend -- env
# → DB_HOST=mysql-service
# → DB_USER=backend
```
 
---
 
### 2.3 Monter un ConfigMap comme volume
 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - image: bmuschko/web-app:1.0.1
    name: backend
    volumeMounts:
    - name: db-config-volume
      mountPath: /etc/config    # chaque clé = un fichier dans ce répertoire
  volumes:
  - name: db-config-volume
    configMap:
      name: db-config           # référence le ConfigMap par son nom
```
 
```bash
# Vérifier le contenu monté
kubectl exec -it backend -- /bin/sh
# ls -1 /etc/config
# → db.json
# cat /etc/config/db.json
# → { "db": { "host": "mysql-service", "user": "backend" } }
```
 
---
 
## 3. Secrets
 
### 3.1 Types de Secrets
 
| CLI option | Description | Type interne |
|---|---|---|
| `generic` | Depuis fichier, répertoire ou literal | `Opaque` |
| `docker-registry` | Pour pull d'images depuis un registry privé | `kubernetes.io/dockercfg` |
| `tls` | Certificat TLS | `kubernetes.io/tls` |
 
Types spécialisés courants :
 
| Type | Clés attendues | Usage |
|---|---|---|
| `kubernetes.io/basic-auth` | `username`, `password` | Authentification basique |
| `kubernetes.io/ssh-auth` | `ssh-privatekey` | Clé SSH privée |
| `kubernetes.io/tls` | `tls.crt`, `tls.key` | Certificat TLS |
 
---
 
### 3.2 Créer un Secret
 
```bash
# Depuis des literals (Base64-encodé automatiquement)
kubectl create secret generic db-creds \
  --from-literal=pwd=s3cre!
 
# Depuis un fichier SSH
cp ~/.ssh/id_rsa ssh-privatekey
kubectl create secret generic secret-ssh-auth \
  --from-file=ssh-privatekey \
  --type=kubernetes.io/ssh-auth
```
 
```yaml
# Résultat YAML — valeur automatiquement Base64-encodée
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
data:
  pwd: czNjcmUh              # Base64 de "s3cre!"
```
 
#### Encoder / décoder manuellement
 
```bash
# Encoder en Base64
echo -n 's3cre!' | base64
# → czNjcmUh
 
# Décoder
echo -n 'czNjcmUh' | base64 --decode
# → s3cre!
```
 
#### Utiliser `stringData` (plain-text dans le manifest)
 
```yaml
# Manifest avec stringData — Kubernetes encode automatiquement au moment de la création
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
stringData:
  pwd: s3cre!               # plain-text dans le manifest
```
 
> Le live object (`kubectl get secret db-creds -o yaml`) utilisera toujours `data` avec la valeur Base64-encodée, même si tu as utilisé `stringData` dans le manifest.
 
#### Secret avec type spécialisé
 
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: secret-basic-auth
type: kubernetes.io/basic-auth
stringData:
  username: bmuschko        # clés imposées par le type
  password: secret
```
 
---
 
### 3.3 Consommer un Secret comme variables d'environnement
 
```yaml
# Injection de toutes les clés du Secret
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - image: bmuschko/web-app:1.0.1
    name: backend
    envFrom:
    - secretRef:
        name: secret-basic-auth    # Kubernetes décode automatiquement le Base64
```
 
```bash
kubectl exec backend -- env
# → username=bmuschko
# → password=secret
```
 
---
 
### 3.4 Remapper les clés des variables d'environnement
 
Utile quand les clés du Secret ne respectent pas les conventions des env vars.
 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - image: bmuschko/web-app:1.0.1
    name: backend
    env:
    - name: USER              # nouveau nom de la variable dans le container
      valueFrom:
        secretKeyRef:
          name: secret-basic-auth
          key: username       # clé source dans le Secret
    - name: PWD
      valueFrom:
        secretKeyRef:
          name: secret-basic-auth
          key: password
```
 
```bash
kubectl exec backend -- env
# → USER=bmuschko
# → PWD=secret
```
 
> Le même mécanisme fonctionne pour les ConfigMaps — utiliser `configMapKeyRef` à la place de `secretKeyRef`.
 
---
 
### 3.5 Monter un Secret comme volume
 
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - image: bmuschko/web-app:1.0.1
    name: backend
    volumeMounts:
    - name: ssh-volume
      mountPath: /var/app
      readOnly: true           # les fichiers d'un Secret monté sont en lecture seule
  volumes:
  - name: ssh-volume
    secret:
      secretName: secret-ssh-auth    # attention : secretName (pas name) pour les Secrets
```
 
```bash
kubectl exec -it backend -- /bin/sh
# ls -1 /var/app
# → ssh-privatekey
# cat /var/app/ssh-privatekey
# → -----BEGIN RSA PRIVATE KEY-----
# → ...
# → -----END RSA PRIVATE KEY-----
# (le contenu est automatiquement décodé par Kubernetes)
```
 
> **Piège** : l'attribut est `secretName` pour les Secrets (vs `name` pour les ConfigMaps).
 
---
 
## 4. Tableau comparatif ConfigMap vs Secret
 
| Critère | ConfigMap | Secret |
|---|---|---|
| Type de données | Plain-text | Base64-encodé |
| Section YAML | `data` | `data` ou `stringData` |
| Usage | Config non sensible | Credentials, clés, certificats |
| Référence dans `envFrom` | `configMapRef` | `secretRef` |
| Référence dans `env.valueFrom` | `configMapKeyRef` | `secretKeyRef` |
| Référence dans `volumes` | `configMap.name` | `secret.secretName` |
| Chiffrement au repos | Non (par défaut) | Non (par défaut) |
 
---
 
## 5. Commandes de référence rapide
 
```bash
# ConfigMap
kubectl create configmap <nom> --from-literal=KEY=value
kubectl create configmap <nom> --from-file=fichier.json
kubectl create configmap <nom> --from-env-file=config.env
kubectl get configmap <nom> -o yaml
kubectl describe configmap <nom>
 
# Secret
kubectl create secret generic <nom> --from-literal=KEY=value
kubectl create secret generic <nom> --from-file=fichier
kubectl create secret tls <nom> --cert=cert.crt --key=cert.key
kubectl get secret <nom> -o yaml
kubectl describe secret <nom>
 
# Décoder une valeur de Secret
kubectl get secret <nom> -o jsonpath='{.data.KEY}' | base64 --decode
```
 
---
 
## 6. Exercices
 
### Exercice 1 — ConfigMap depuis un fichier YAML, monté comme volume
 
**Solution :**
 
```bash
# 1. Inspecter le fichier source
# (dans le repo bmuschko/cka-study-guide : app-a/ch10/configmap/application.yaml)
cat application.yaml
```
 
```yaml
# Exemple de contenu de application.yaml
db:
  host: mysql-service
  port: 3306
app:
  environment: production
  debug: false
```
 
```bash
# 2. Créer le ConfigMap depuis le fichier
kubectl create configmap app-config --from-file=application.yaml
 
# Vérifier
kubectl get configmap app-config -o yaml
# → data.application.yaml contient le contenu du fichier
```
 
```yaml
# 3. Créer le Pod qui monte le ConfigMap comme volume
# pod-configmap.yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - name: backend
    image: nginx:1.23.4-alpine
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```
 
```bash
kubectl apply -f pod-configmap.yaml
 
# 4. Inspecter le contenu monté
kubectl exec -it backend -- /bin/sh
# ls -1 /etc/config
# → application.yaml
# cat /etc/config/application.yaml
# → db:
# →   host: mysql-service
# →   port: 3306
# → ...
```
 
---
 
### Exercice 2 — Secret comme variable d'environnement
 
**Solution :**
 
```bash
# 1. Créer le Secret
kubectl create secret generic db-credentials \
  --from-literal=db-password=passwd
 
# Vérifier
kubectl get secret db-credentials -o yaml
# → data.db-password: cGFzc3dk  (Base64 de "passwd")
```
 
```yaml
# 2. Créer le Pod qui injecte le Secret comme env var
# pod-secret.yaml
apiVersion: v1
kind: Pod
metadata:
  name: backend
spec:
  containers:
  - name: backend
    image: nginx:1.23.4-alpine
    env:
    - name: DB_PASSWORD           # nom de la variable dans le container
      valueFrom:
        secretKeyRef:
          name: db-credentials    # nom du Secret
          key: db-password        # clé dans le Secret
```
 
```bash
kubectl apply -f pod-secret.yaml
 
# 3. Vérifier la variable d'environnement dans le container
kubectl exec -it backend -- /bin/sh
# env | grep DB_PASSWORD
# → DB_PASSWORD=passwd
# (Kubernetes décode automatiquement le Base64)
```
 
---
 
## Pièges CKA
 
| Piège | Solution |
|---|---|
| Secret = chiffré | **Faux** — Base64 est un encodage, pas un chiffrement |
| `secretName` vs `name` dans les volumes | Secrets = `secretName`, ConfigMaps = `name` |
| `stringData` vs `data` | `stringData` = plain-text dans le manifest, `data` = Base64. Le live object utilise toujours `data` |
| Modifier un ConfigMap/Secret suffit à recharger le Pod | Pas toujours — dépend si monté comme volume (rechargement automatique) ou env var (nécessite redémarrage du Pod) |
| `--from-env-file` vs `--from-file` | `--from-env-file` = fichier de variables d'env ; `--from-file` = fichier arbitraire (JSON, XML...) |
