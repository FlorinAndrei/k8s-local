#!/usr/bin/env bash

. ./variables.sh

rm -f $known_hosts

for h in ${nodes}; do
echo
echo "Creating $h"
echo
sudo mkdir /var/lib/libvirt/images/$h
sudo qemu-img create -f qcow2 -F qcow2 \
  -o backing_file=/var/lib/libvirt/images/base/ubuntu-22.04.qcow2 \
  /var/lib/libvirt/images/$h/$h.qcow2
sudo qemu-img resize /var/lib/libvirt/images/$h/$h.qcow2 $root_disk_size

cat >meta-data-$h <<EOF
local-hostname: $h
EOF

cat >user-data-$h <<EOF
#cloud-config
users:
  - name: $username
    ssh-authorized-keys:
      - $pub_key
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
runcmd:
  - echo "AllowUsers $username" >> /etc/ssh/sshd_config
  - systemctl restart sshd
  - apt-get update
  - apt-get install -y apt-transport-https ca-certificates curl gpg gnupg-agent software-properties-common wget
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
  - systemctl enable --now kubelet
  - for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg; done
  - wget --progress=bar:force:noscroll https://download.docker.com/linux/ubuntu/dists/jammy/pool/stable/amd64/containerd.io_1.6.28-2_amd64.deb
  - wget --progress=bar:force:noscroll https://download.docker.com/linux/ubuntu/dists/jammy/pool/stable/amd64/docker-ce_25.0.4-1~ubuntu.22.04~jammy_amd64.deb
  - wget --progress=bar:force:noscroll https://download.docker.com/linux/ubuntu/dists/jammy/pool/stable/amd64/docker-ce-cli_25.0.4-1~ubuntu.22.04~jammy_amd64.deb
  - wget --progress=bar:force:noscroll https://download.docker.com/linux/ubuntu/dists/jammy/pool/stable/amd64/docker-buildx-plugin_0.13.0-1~ubuntu.22.04~jammy_amd64.deb
  - wget --progress=bar:force:noscroll https://download.docker.com/linux/ubuntu/dists/jammy/pool/stable/amd64/docker-compose-plugin_2.24.7-1~ubuntu.22.04~jammy_amd64.deb
  - dpkg -i containerd.io_1.6.28-2_amd64.deb docker-ce_25.0.4-1~ubuntu.22.04~jammy_amd64.deb docker-ce-cli_25.0.4-1~ubuntu.22.04~jammy_amd64.deb docker-buildx-plugin_0.13.0-1~ubuntu.22.04~jammy_amd64.deb docker-compose-plugin_2.24.7-1~ubuntu.22.04~jammy_amd64.deb
  - wget --progress=bar:force:noscroll https://github.com/containernetworking/plugins/releases/download/v1.4.1/cni-plugins-linux-amd64-v1.4.1.tgz
  - mkdir -p /opt/cni/bin
  - tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.4.1.tgz
  - rm -f /*.deb /*.tgz
EOF

sudo cloud-localds -v /var/lib/libvirt/images/$h/$h-seed.qcow2 \
  user-data-$h meta-data-$h

virsh net-update default add-last ip-dhcp-host --live --config \
  --xml "<host mac='${node_mac[$h]}' name='$h' ip='${node_ip[$h]}'/>"

virt-install --connect qemu:///system --virt-type kvm --name $h \
  --ram $ram_size --vcpus=$n_cpus --os-variant ubuntu22.04 \
  --disk path=/var/lib/libvirt/images/$h/$h.qcow2,format=qcow2 \
  --disk /var/lib/libvirt/images/$h/$h-seed.qcow2,device=disk \
  --import --network network=default,mac=${node_mac[$h]} \
  --noautoconsole

done

echo
echo "Wait for VMs to acquire IP addresses..."
echo
for h in ${nodes}; do
echo $h
count="0"
while [ 1 -ne "$count" ]; do
count=`virsh domifaddr $h | grep ipv4 | wc -l`
sleep 1
done
done

echo
echo "Wait for VMs to finish booting up and configuring themselves..."
echo

for h in ${nodes}; do
echo $h
boot_status="no"
cloud_init_status="no"
while [ "running" != "$boot_status" ] && [ "status: done" != "$cloud_init_status" ]; do
boot_status=`ssh $ssh_opts ubuntu@${node_ip[$h]} 'sudo systemctl is-system-running'`
cloud_init_status=`ssh $ssh_opts ubuntu@${node_ip[$h]} 'sudo cloud-init status'`
sleep 1
done
done


echo
echo "Reconfigure containerd, load modules, and configure sysctl:"
echo

for instance in ${nodes}; do
scp $ssh_opts config.toml $username@${node_ip[$instance]}:
scp $ssh_opts k8s.conf-modules $username@${node_ip[$instance]}:
scp $ssh_opts k8s.conf-sysctl $username@${node_ip[$instance]}:

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH
sudo mv /home/$username/config.toml /etc/containerd/config.toml
sudo chown root:root /etc/containerd/config.toml
sudo systemctl restart containerd

sudo mv /home/$username/k8s.conf-modules /etc/modules-load.d/k8s.conf
sudo chown root:root /etc/modules-load.d/k8s.conf
sudo modprobe overlay
sudo modprobe br_netfilter

sudo mv /home/$username/k8s.conf-sysctl /etc/sysctl.d/k8s.conf
sudo chown root:root /etc/sysctl.d/k8s.conf
sudo sysctl --system

ENDSSH
done

echo
echo "Final state:"
echo

virsh net-dumpxml default
