# Volumes

> Un volume = répertoire **partageable** entre containers d'un même Pod.  
> Contrairement au filesystem temporaire d'un container, un volume **survit aux restarts** du container.  
> Deux étapes obligatoires : **déclarer** le volume (`spec.volumes[]`) + **monter** le volume (`spec.containers[].volumeMounts[]`).

---

## 1. Types de volumes

| Type | Description |
|------|-------------|
| `emptyDir` | Répertoire vide, créé au démarrage du Pod. Détruit quand le Pod est supprimé. Idéal pour partage de données entre containers ou cache. |
| `hostPath` | Fichier ou répertoire du filesystem du node hôte. |
| `configMap` | Injecte des données de configuration comme volume. |
| `secret` | Injecte des secrets comme volume. |
| `nfs` | Partage NFS existant. Données persistées après restart du Pod. |
| `persistentVolumeClaim` | Réclame un PersistentVolume (voir chapitre PVC). |

---

## 2. Créer et monter un volume — emptyDir

> `emptyDir` = volume partagé entre containers du même Pod.  
> Détruit quand le **Pod** est supprimé (pas juste le container).  
> `{}` = pas de config supplémentaire (pas de size limit).

```yaml
# pod-with-volume.yaml
# Deux containers qui partagent le même volume emptyDir
apiVersion: v1
kind: Pod
metadata:
  name: business-app
spec:
  volumes:
  - name: shared-data      # nom du volume, référencé dans volumeMounts
    emptyDir: {}           # type emptyDir, pas de config supplémentaire
  containers:
  - name: nginx
    image: nginx:1.27.1
    volumeMounts:
    - name: shared-data              # doit correspondre au nom du volume
      mountPath: /usr/share/nginx/html  # chemin dans le container nginx
  - name: sidecar
    image: busybox:1.37.0
    volumeMounts:
    - name: shared-data              # même volume, chemin différent
      mountPath: /data               # chemin dans le container sidecar
```

```bash
# Créer le pod
kubectl apply -f pod-with-volume.yaml

# Vérifier que les 2 containers tournent (READY = 2/2)
kubectl get pod business-app

# Ouvrir un shell dans le container nginx
kubectl exec business-app -it -c nginx -- /bin/sh

# Dans le container nginx
cd /usr/share/nginx/html
ls                    # vide au démarrage (emptyDir)
touch example.html    # créer un fichier
ls                    # example.html visible
exit
```

---

## 3. Volume Mount en Read-Only

> Empêche toute écriture sur le volume depuis ce container.  
> D'autres containers peuvent toujours monter le même volume en read/write.  
> `readOnly: true` = lecture seule pour CE container uniquement.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: business-app
spec:
  volumes:
  - name: shared-data
    emptyDir: {}
  containers:
  - name: nginx
    image: nginx:1.27.1
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html
      readOnly: true           # ce container ne peut pas écrire dans le volume
```

---

## Exercice & Solution

**Énoncé :**  
Créer un Pod avec 2 containers `alpine:3.22.2` qui tournent indéfiniment.  
Définir un volume `emptyDir`. Container 1 monte sur `/etc/a`, Container 2 sur `/etc/b`.  
Depuis Container 1 : créer `/etc/a/data/hello.txt` avec "Hello World".  
Depuis Container 2 : vérifier que `/etc/b/data/hello.txt` contient bien "Hello World".

---

**Solution**

```yaml
# pod-with-volume.yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-pod
spec:
  volumes:
  - name: shared-data    # volume partagé entre les deux containers
    emptyDir: {}
  containers:
  - name: container1
    image: alpine:3.22.2
    command: ["sh", "-c", "sleep infinity"]   # garde le container en vie indéfiniment
    volumeMounts:
    - name: shared-data
      mountPath: /etc/a                       # container1 voit le volume sous /etc/a
  - name: container2
    image: alpine:3.22.2
    command: ["sh", "-c", "sleep infinity"]   # garde le container en vie indéfiniment
    volumeMounts:
    - name: shared-data
      mountPath: /etc/b                       # container2 voit le même volume sous /etc/b
```

```bash
# Créer le pod
kubectl apply -f pod-with-volume.yaml

# Vérifier que les 2 containers tournent (READY = 2/2)
kubectl get pod shared-pod

# Ouvrir un shell dans container1
kubectl exec shared-pod -it -c container1 -- sh

# Dans container1 : créer le répertoire data et le fichier hello.txt
mkdir /etc/a/data
echo "Hello World" > /etc/a/data/hello.txt
exit

# Ouvrir un shell dans container2
kubectl exec shared-pod -it -c container2 -- sh

# Dans container2 : vérifier que le fichier est visible via /etc/b
# (même volume, chemin différent)
cat /etc/b/data/hello.txt    # doit afficher : Hello World
exit
```

---

## Pièges CKA

| Piège | Solution |
|-------|----------|
| `name` dans `volumeMounts` ≠ `name` dans `volumes` | Les deux noms doivent être **identiques** |
| `emptyDir` vs `hostPath` | emptyDir = détruit avec le Pod, hostPath = persiste sur le node |
| `readOnly: true` bloque tous les containers | Non — `readOnly` est par container, les autres peuvent écrire |
| Oublier `mountPath` | Sans mountPath, le volume n'est pas accessible dans le container |
| `emptyDir` survit aux restarts du container | Oui — mais pas à la **suppression du Pod** |
