# Upgrade d'un cluster Kubernetes

> **Règle CKA** : On upgrade toujours **minor version par minor version** (ex: 1.28 → 1.29, pas 1.28 → 1.30).  
> Ordre obligatoire : **master en premier**, puis **chaque worker**.  
> `kubectl drain` = depuis le **master uniquement**.

---

## 1. Vérifier l'état du cluster

```bash
kubectl get nodes          # voir les versions actuelles
```

---

## 2. MASTER — Upgrade

```bash
# Changer le repo apt vers la nouvelle version cible
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update

# Voir les versions disponibles
sudo apt-cache madison kubeadm

# Débloquer, installer, rebloquer kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.29.0-1.1
sudo apt-mark hold kubeadm

# Vérifier le plan d'upgrade (composants affectés + versions)
sudo kubeadm upgrade plan

# Lancer l'upgrade du control-plane (api-server, scheduler, controller-manager, etcd)
sudo kubeadm upgrade apply v1.29.0

# Évacuer les pods du master (depuis le master lui-même)
kubectl drain master --ignore-daemonsets --delete-emptydir-data

# Débloquer, installer, rebloquer kubelet et kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.29.0-1.1 kubectl=1.29.0-1.1
sudo apt-mark hold kubelet kubectl

# Recharger systemd et redémarrer kubelet
sudo systemctl daemon-reload && sudo systemctl restart kubelet

# Remettre le master en service
kubectl uncordon master
```

---

## 3. WORKER — Upgrade (répéter pour chaque worker)

```bash
# Sur le worker : changer le repo apt
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update

# Débloquer, installer, rebloquer kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get install -y kubeadm=1.29.0-1.1
sudo apt-mark hold kubeadm

# Mettre à jour la config kubelet du worker (pas le control-plane)
sudo kubeadm upgrade node

# ⚠️ Depuis le MASTER : évacuer les pods du worker
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data

# Sur le worker : débloquer, installer, rebloquer kubelet et kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.29.0-1.1 kubectl=1.29.0-1.1
sudo apt-mark hold kubelet kubectl

# Recharger systemd et redémarrer kubelet
sudo systemctl daemon-reload && sudo systemctl restart kubelet

# ⚠️ Depuis le MASTER : remettre le worker en service
kubectl uncordon worker1
```

---

## 4. Vérification finale

```bash
kubectl get nodes    # tous les noeuds doivent être Ready + v1.29.x
```

---

## Pièges fréquents à l'examen

| Piège | Solution |
|-------|----------|
| `kubectl drain` depuis un worker | Toujours depuis le **master** |
| Sauter une minor version | Interdit — upgrade une version à la fois |
| Oublier `apt-get update` après le changement de repo | Le package ne sera pas trouvé |
| Oublier `systemctl daemon-reload` | kubelet ne prend pas la nouvelle version |
| `kubeadm upgrade apply` sur un worker | Utiliser `kubeadm upgrade node` sur les workers |
