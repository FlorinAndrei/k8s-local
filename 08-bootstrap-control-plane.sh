#!/usr/bin/env bash

. ./variables.sh

KUBERNETES_PUBLIC_ADDRESS="$main_host_ip"
etcd_servers="https://${node_ip[controller-0]}:2379,https://${node_ip[controller-1]}:2379,https://${node_ip[controller-2]}:2379"

wget --https-only -nc \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kubectl"

for instance in ${controllers}; do
INTERNAL_IP=${node_ip[$instance]}

scp $ssh_opts kube-apiserver kube-controller-manager kube-scheduler kubectl $username@${node_ip[$instance]}:
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH
sudo mkdir -p /etc/kubernetes/config

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo cp kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

sudo mkdir -p /var/lib/kubernetes/
sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
  service-account-key.pem service-account.pem \
  encryption-config.yaml /var/lib/kubernetes/
ENDSSH

cat << EOF | tee kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=${etcd_servers} \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \\
  --service-cluster-ip-range=${service_cluster_ip_range} \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

scp $ssh_opts kube-apiserver.service $username@${node_ip[$instance]}:
rm -f kube-apiserver.service

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH2
sudo cp kube-apiserver.service /etc/systemd/system/kube-apiserver.service
sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/
ENDSSH2

cat <<EOF | sudo tee kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=${cluster_cidr} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=${service_cluster_ip_range} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

scp $ssh_opts kube-controller-manager.service $username@${node_ip[$instance]}:
rm -f kube-controller-manager.service

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH3
sudo cp kube-controller-manager.service /etc/systemd/system/kube-controller-manager.service
sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/
ENDSSH3

cat <<EOF | sudo tee kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

scp $ssh_opts kube-scheduler.yaml $username@${node_ip[$instance]}:
rm -f kube-scheduler.yaml

cat <<EOF | sudo tee kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

scp $ssh_opts kube-scheduler.service $username@${node_ip[$instance]}:
rm -f kube-scheduler.service

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH4
sudo cp kube-scheduler.yaml /etc/kubernetes/config/
sudo cp kube-scheduler.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
ENDSSH4

sleep 1

cat > kubernetes.default.svc.cluster.local <<EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF
scp $ssh_opts kubernetes.default.svc.cluster.local $username@${node_ip[$instance]}:
rm -f kubernetes.default.svc.cluster.local

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH5
sudo apt-get update
sudo apt-get install -y nginx net-tools
sudo cp kubernetes.default.svc.cluster.local /etc/nginx/sites-available/kubernetes.default.svc.cluster.local
sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
sudo systemctl enable nginx
sudo systemctl restart nginx
ENDSSH5

done

cat > cluster-role-create.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat > cluster-role-bind.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

set -x
scp $ssh_opts cluster-role-create.yaml $username@${node_ip["controller-0"]}:
scp $ssh_opts cluster-role-bind.yaml $username@${node_ip["controller-0"]}:
rm -f cluster-role-create.yaml cluster-role-bind.yaml
set +x

ssh $ssh_opts $username@${node_ip["controller-0"]} << ENDSSH6
kubectl apply --kubeconfig admin.kubeconfig -f cluster-role-create.yaml
kubectl apply --kubeconfig admin.kubeconfig -f cluster-role-bind.yaml
ENDSSH6

cat << EOF > haproxy-tail.cnf
frontend k8s_lb
        mode tcp
        bind :6443
        default_backend k8s_controllers

backend k8s_controllers
        mode tcp
        option httpchk
        http-check connect ssl alpn h2
        http-check send meth GET uri /healthz ver HTTP/2 hdr Host www.test.local
        http-check expect status 200
        balance leastconn
        server controller-0 ${node_ip[controller-0]}:6443 check verify none
        server controller-1 ${node_ip[controller-1]}:6443 check verify none
        server controller-2 ${node_ip[controller-2]}:6443 check verify none
EOF

echo
echo "Examine the file haproxy-tail.cnf which I've just created."
echo "If it looks good, then append it to /etc/haproxy/haproxy.cfg and restart HAProxy."
echo "After that, you can check the control plane and the load balancer by running this command:"
echo
echo "curl --cacert ca/ca.pem https://${KUBERNETES_PUBLIC_ADDRESS}:6443/version"
echo

rm -f kube-apiserver kube-controller-manager kube-scheduler kubectl
