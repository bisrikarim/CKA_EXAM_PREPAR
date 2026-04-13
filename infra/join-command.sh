# -*- mode: ruby -*-
# vi: set ft=ruby :
# ============================================================
# CKA Lab — 1 Master + 2 Workers
# Provider : VMware Workstation / VMware Desktop
# Kubernetes : 1.28.x (upgradable to 1.29)
# ============================================================

MASTER_IP    = "192.168.56.10"
WORKER_IPS   = ["192.168.56.11", "192.168.56.12"]
POD_CIDR     = "10.244.0.0/16"   # Flannel
K8S_VERSION  = "1.28.0-00"

Vagrant.configure("2") do |config|

  config.vm.box = "bento/ubuntu-22.04"

  # ── MASTER ──────────────────────────────────────────────
  config.vm.define "master" do |master|
    master.vm.hostname = "master"
    master.vm.network "private_network", ip: MASTER_IP

    master.vm.provider "vmware_desktop" do |v|
      v.vmx["memsize"]  = "2048"
      v.vmx["numvcpus"] = "2"
      v.gui = false
    end

    master.vm.provision "shell", path: "scripts/common.sh"
    master.vm.provision "shell", path: "scripts/master.sh",
      env: {
        "MASTER_IP"   => MASTER_IP,
        "POD_CIDR"    => POD_CIDR,
        "K8S_VERSION" => K8S_VERSION
      }
  end

  # ── WORKERS ─────────────────────────────────────────────
  WORKER_IPS.each_with_index do |ip, i|
    config.vm.define "worker#{i+1}" do |worker|
      worker.vm.hostname = "worker#{i+1}"
      worker.vm.network "private_network", ip: ip

      worker.vm.provider "vmware_desktop" do |v|
        v.vmx["memsize"]  = "2048"
        v.vmx["numvcpus"] = "2"
        v.gui = false
      end

      worker.vm.provision "shell", path: "scripts/common.sh"
      worker.vm.provision "shell", path: "scripts/worker.sh",
        env: {
          "MASTER_IP"   => MASTER_IP,
          "K8S_VERSION" => K8S_VERSION
        }
    end
  end

end
