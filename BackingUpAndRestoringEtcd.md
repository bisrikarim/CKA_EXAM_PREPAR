# Backup & Restore etcd

> **Règle CKA** : etcd stocke tout l'état du cluster.  
> `etcdctl` = faire le snapshot. `etcdutl` = restaurer le snapshot.  
> Les versions de `etcdctl` et `etcdutl` doivent être **identiques** à celle d'etcd dans le cluster.  
> Toujours préciser les **certs TLS** sinon les commandes échouent.

---

## 0. Trouver les infos etcd

```bash
# Affiche les chemins des certs et l'endpoint depuis le manifest du pod static etcd
sudo cat /etc/kubernetes/manifests/etcd.yaml | grep -E "listen-client|cert-file|key-file|trusted-ca"
```

---

## 1. Vérifier la version etcd du cluster

```bash
# Exécute etcdctl dans le container etcd pour connaitre la version exacte
# Nécessaire pour télécharger le bon binaire
sudo crictl exec -it $(sudo crictl ps | grep etcd | awk '{print $1}') etcdctl version
```

---

## 2. Installer etcdctl et etcdutl à la bonne version

```bash
# Définir la version trouvée à l'étape précédente
ETCD_VER=v3.5.15

# Télécharger l'archive officielle
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
  -o /tmp/etcd.tar.gz

# Extraire l'archive
tar xzvf /tmp/etcd.tar.gz -C /tmp

# Copier etcdctl et etcdutl dans le PATH
# ⚠️ Les deux doivent venir du même package pour éviter les erreurs de checksum
sudo cp /tmp/etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
sudo cp /tmp/etcd-${ETCD_VER}-linux-amd64/etcdutl /usr/local/bin/

# Vérifier les versions
etcdctl version
etcdutl version
```

---

## 3. BACKUP — Créer un snapshot

```bash
# Sauvegarde l'état complet du cluster dans /opt/etcd-backup.db
# ETCDCTL_API=3 : force l'API v3 (obligatoire)
# --endpoints : adresse du serveur etcd
# --cacert/--cert/--key : certs TLS obligatoires pour s'authentifier
sudo ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

```bash
# Vérifie que le snapshot est valide : hash, révision, nb de clés, taille
# Toujours vérifier avant de lancer un restore
sudo ETCDCTL_API=3 etcdutl snapshot status /opt/etcd-backup.db --write-out=table
```

---

## 4. RESTORE — Restaurer le snapshot

```bash
# Supprime le dossier cible s'il existe déjà (sinon restore échoue)
sudo rm -rf /var/lib/etcd-restore

# Restaure le snapshot dans un nouveau data-dir /var/lib/etcd-restore
# etcdutl (pas etcdctl) est la commande correcte depuis etcd 3.5+
sudo ETCDCTL_API=3 etcdutl snapshot restore /opt/etcd-backup.db \
  --data-dir=/var/lib/etcd-restore
```

---

## 5. Pointer etcd vers le nouveau data-dir

```bash
# Modifie le manifest du pod static etcd pour utiliser /var/lib/etcd-restore
# Kubernetes détecte le changement et redémarre automatiquement le pod etcd
sudo sed -i 's|/var/lib/etcd|/var/lib/etcd-restore|g' /etc/kubernetes/manifests/etcd.yaml
```

---

## 6. Vérification finale

```bash
# Vérifie que le container etcd tourne (attendre 30-60 secondes après l'étape 5)
sudo crictl exec -it $(sudo crictl ps | grep etcd | awk '{print $1}') etcdctl version

# Vérifie que le cluster répond correctement
kubectl get nodes
```

---

## Pièges fréquents à l'examen

| Piège | Solution |
|-------|----------|
| `etcdctl` et `etcdutl` de versions différentes | Toujours prendre les deux du **même package** |
| Utiliser `etcdctl` pour restaurer | Utiliser **`etcdutl`** pour le restore (etcd 3.5+) |
| Oublier les certs TLS dans le backup | Les 3 flags `--cacert` `--cert` `--key` sont obligatoires |
| Le dossier `--data-dir` existe déjà | Faire `rm -rf` avant le restore |
| Oublier de modifier `etcd.yaml` après le restore | Sans cette étape etcd continue sur l'ancien data-dir |
| `ETCDCTL_API=3` non défini | Sans ça, etcdctl utilise l'API v2 par défaut |
