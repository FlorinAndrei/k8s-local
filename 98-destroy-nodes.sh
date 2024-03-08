#!/usr/bin/env bash

. variables.sh

for h in controller-0 controller-1 controller-2 worker-0 worker-1 worker-2; do
echo
echo "Delete DHCP record: $h ${node_mac[$h]} ${node_ip[$h]}"
virsh net-update default delete ip-dhcp-host --live --config \
        --xml "<host mac='${node_mac[$h]}' name='$h' ip='${node_ip[$h]}'/>"
done

echo
sleep 1

for h in controller-0 controller-1 controller-2 worker-0 worker-1 worker-2; do
virsh shutdown $h
done

echo
for h in controller-0 controller-1 controller-2 worker-0 worker-1 worker-2; do
echo "Waiting for $h to shut down..."
count="1"
while [ 0 -ne "$count" ]; do
count=`virsh list | awk '{print $2}' | grep $h | wc -l`
sleep 1
done
done

echo
sleep 1

for h in controller-0 controller-1 controller-2 worker-0 worker-1 worker-2; do
echo "Destroying $h"
virsh undefine $h
done
rm -f $known_hosts

echo
sleep 1

for h in controller-0 controller-1 controller-2 worker-0 worker-1 worker-2; do
echo "Deleting $h root disk"
sudo rm -rf /var/lib/libvirt/images/$h
done

sleep 1

echo
echo "Final state:"
echo

virsh net-dumpxml default
