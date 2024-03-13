#!/usr/bin/env bash

. ./variables.sh

wget --https-only -nc https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz

for instance in ${controllers}; do

instance_ip=${node_ip[$instance]}
init_cluster_str="controller-0=https://${node_ip[controller-0]}:2380,controller-1=https://${node_ip[controller-1]}:2380,controller-2=https://${node_ip[controller-2]}:2380"

scp $ssh_opts etcd-v3.5.9-linux-amd64.tar.gz $username@${node_ip[$instance]}:
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH
tar -xvf etcd-v3.5.9-linux-amd64.tar.gz
sudo mv etcd-v3.5.9-linux-amd64/etcd* /usr/local/bin/
rm -rf etcd-v3.5.9-linux-amd64
rm -f etcd-v3.5.9-linux-amd64.tar.gz

sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
ENDSSH

cat << EOF | tee etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
	--name ${instance} \\
	--cert-file=/etc/etcd/kubernetes.pem \\
	--key-file=/etc/etcd/kubernetes-key.pem \\
	--peer-cert-file=/etc/etcd/kubernetes.pem \\
	--peer-key-file=/etc/etcd/kubernetes-key.pem \\
	--trusted-ca-file=/etc/etcd/ca.pem \\
	--peer-trusted-ca-file=/etc/etcd/ca.pem \\
	--peer-client-cert-auth \\
	--client-cert-auth \\
	--initial-advertise-peer-urls https://$instance_ip:2380 \\
	--listen-peer-urls https://$instance_ip:2380 \\
	--listen-client-urls https://$instance_ip:2379,https://127.0.0.1:2379 \\
	--advertise-client-urls https://$instance_ip:2379 \\
	--initial-cluster-token etcd-cluster-0 \\
	--initial-cluster $init_cluster_str \\
	--initial-cluster-state new \\
    --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

scp $ssh_opts etcd.service $username@${node_ip[$instance]}:
rm -f etcd.service

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH2
sudo mv etcd.service /etc/systemd/system/etcd.service
sudo systemctl daemon-reload
sudo systemctl enable etcd
ENDSSH2

done

sleep 1

for instance in ${controllers}; do
ssh $ssh_opts $username@${node_ip[$instance]} 'sudo systemctl start etcd' &
sleep 1
done

sleep 1

echo
echo "Check the status of the etcd cluster:"
echo

for instance in ${controllers}; do
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH3
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
ENDSSH3

done

rm -f etcd-v3.5.9-linux-amd64.tar.gz
