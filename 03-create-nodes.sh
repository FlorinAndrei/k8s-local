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
echo "Final state:"
echo

virsh net-dumpxml default
