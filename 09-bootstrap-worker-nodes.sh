#!/usr/bin/env bash

. ./variables.sh

for instance in ${workers}; do
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH
sudo apt-get update
sudo apt-get -y install socat conntrack ipset
ENDSSH
done

echo
echo "Swap should be disabled on the workers. But let's check it anyway."
echo "If you see any swap amount listed here, you need to disable it."
echo

for instance in ${workers}; do
echo $instance
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH2
sudo swapon --show
ENDSSH2
done

wget --https-only -nc \
  https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.25.0/crictl-v1.25.0-linux-amd64.tar.gz \
  https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64 \
  https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz \
  https://github.com/containerd/containerd/releases/download/v1.6.24/containerd-1.6.24-linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.28.3/bin/linux/amd64/kubelet

for instance in ${workers}; do
POD_CIDR=${cluster_cidr_worker[$instance]}
scp $ssh_opts crictl-v1.25.0-linux-amd64.tar.gz runc.amd64 cni-plugins-linux-amd64-v1.3.0.tgz containerd-1.6.24-linux-amd64.tar.gz kubectl kube-proxy kubelet $username@${node_ip[$instance]}:
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH3
sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

mkdir containerd
tar -xvf crictl-v1.25.0-linux-amd64.tar.gz
tar -xvf containerd-1.6.24-linux-amd64.tar.gz -C containerd
sudo tar -xvf cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin/
sudo mv runc.amd64 runc
chmod +x crictl kubectl kube-proxy kubelet runc 
sudo mv crictl kubectl kube-proxy kubelet runc /usr/local/bin/
sudo mv containerd/bin/* /bin/
ENDSSH3

# alternative:
# "cniVersion": "0.3.1"
cat << EOF > 10-bridge.conf
{
    "cniVersion": "0.4.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

# alternative:
# "cniVersion": "1.0.0"
cat << EOF > 99-loopback.conf
{
    "cniVersion": "0.4.0",
    "name": "lo",
    "type": "loopback"
}
EOF

scp $ssh_opts 10-bridge.conf 99-loopback.conf $username@${node_ip[$instance]}:
rm -f 10-bridge.conf 99-loopback.conf

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH4
sudo cp 10-bridge.conf /etc/cni/net.d/
sudo cp 99-loopback.conf /etc/cni/net.d/
ENDSSH4

#cat << EOF > config.toml
#[plugins]
#  [plugins.cri.containerd]
#    snapshotter = "overlayfs"
#    [plugins.cri.containerd.default_runtime]
#      runtime_type = "io.containerd.runtime.v1.linux"
#      runtime_engine = "/usr/local/bin/runc"
#      runtime_root = ""
#EOF

cat << EOF > config.toml
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"
oom_score = 0
# imports

[grpc]
  address = "/run/containerd/containerd.sock"
  uid = 0
  gid = 0
  max_recv_message_size = 16777216
  max_send_message_size = 16777216

[debug]
  address = ""
  uid = 0
  gid = 0
  level = ""

[metrics]
  address = ""
  grpc_histogram = false

[cgroup]
  path = ""

[plugins]
  [plugins."io.containerd.monitor.v1.cgroups"]
    no_prometheus = false
  [plugins."io.containerd.grpc.v1.cri"]
    stream_server_address = ""
    stream_server_port = "10010"
    enable_selinux = false
    sandbox_image = "registry.k8s.io/pause:3.9"
    stats_collect_period = 10
    enable_tls_streaming = false
    max_container_log_line_size = 16384
    restrict_oom_score_adj = false

    [plugins."io.containerd.grpc.v1.cri".containerd]
      discard_unpacked_layers = true
      snapshotter = "overlayfs"
      default_runtime_name = "runc"
      [plugins."io.containerd.grpc.v1.cri".containerd.untrusted_workload_runtime]
        runtime_type = ""
        runtime_engine = ""
        runtime_root = ""
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true

    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"
      conf_template = ""
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"

  [plugins."io.containerd.service.v1.diff-service"]
    default = ["walking"]
  [plugins."io.containerd.gc.v1.scheduler"]
    pause_threshold = 0.02
    deletion_threshold = 0
    mutation_threshold = 100
    schedule_delay = "0s"
    startup_delay = "100ms"
EOF

cat << EOF > hosts.toml
server = "https://registry-1.docker.io"
EOF

cat << EOF > containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

scp $ssh_opts config.toml containerd.service hosts.toml $username@${node_ip[$instance]}:
rm -f config.toml containerd.service hosts.toml

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH5
sudo mkdir -p /etc/containerd/certs.d/docker.io/
sudo mkdir -p /var/lib/containerd/
sudo mkdir -p /run/containerd/
sudo cp config.toml /etc/containerd/
sudo cp hosts.toml /etc/containerd/certs.d/docker.io/
sudo cp containerd.service /etc/systemd/system/

sudo mv ${instance}-key.pem ${instance}.pem /var/lib/kubelet/
sudo mv ${instance}.kubeconfig /var/lib/kubelet/kubeconfig
sudo mv ca.pem /var/lib/kubernetes/
ENDSSH5

cat << EOF > kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "${POD_CIDR}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${instance}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${instance}-key.pem"
EOF

cat << EOF > kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "$cluster_cidr"
EOF

cat << EOF > kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

scp $ssh_opts kubelet-config.yaml kubelet.service kube-proxy-config.yaml kube-proxy.service $username@${node_ip[$instance]}:
rm -f kubelet-config.yaml kubelet.service kube-proxy-config.yaml kube-proxy.service

ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH6
sudo cp kubelet-config.yaml /var/lib/kubelet/
sudo cp kubelet.service /etc/systemd/system/
sudo cp kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
sudo cp kube-proxy-config.yaml /var/lib/kube-proxy/
sudo cp kube-proxy.service /etc/systemd/system/
ENDSSH6
done

for instance in ${workers}; do
ssh $ssh_opts $username@${node_ip[$instance]} << ENDSSH7
sudo systemctl daemon-reload
sudo systemctl enable containerd kubelet kube-proxy
sudo systemctl start containerd kubelet kube-proxy
ENDSSH7
done

rm -f crictl-v1.25.0-linux-amd64.tar.gz runc.amd64 cni-plugins-linux-amd64-v1.3.0.tgz containerd-1.6.24-linux-amd64.tar.gz kubectl kube-proxy kubelet

sleep 10

ssh $ssh_opts $username@${node_ip["controller-0"]} << ENDSSH8
kubectl get nodes --kubeconfig admin.kubeconfig
ENDSSH8
