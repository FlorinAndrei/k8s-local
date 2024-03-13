# VM params
root_disk_size="8G"
n_cpus="2"
ram_size="8192"
username="ubuntu"

# ssh key to access k8s nodes
pub_key_file="$HOME/.ssh/id_rsa.pub"
pub_key=$(cat ${pub_key_file})

known_hosts="known_hosts"
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=$known_hosts -o ForwardX11=no -o ForwardX11Trusted=no"

# the IP of the host machine running all VMs
main_host_ip="192.168.1.20"
# the main virtual network within the host
private_net="192.168.122.0/24"
# the IP range internal to Kubernetes (pod IPs)
cluster_cidr_prefix="10.200"
cluster_cidr="${cluster_cidr_prefix}.0.0/16"
# IPs for internal cluster services
service_cluster_ip_prefix="10.32.0"
service_cluster_ip_range="${service_cluster_ip_prefix}.0/24"

controllers="controller-0 controller-1 controller-2"
workers="worker-0 worker-1 worker-2"
nodes="${controllers} ${workers}"

# bash maps must be declared with -A
declare -A cluster_cidr_worker
cluster_cidr_worker[worker-0]="${cluster_cidr_prefix}.0.0/24"
cluster_cidr_worker[worker-1]="${cluster_cidr_prefix}.1.0/24"
cluster_cidr_worker[worker-2]="${cluster_cidr_prefix}.2.0/24"

declare -A node_ip
node_ip[controller-0]="192.168.122.100"
node_ip[controller-1]="192.168.122.101"
node_ip[controller-2]="192.168.122.102"
node_ip[worker-0]="192.168.122.200"
node_ip[worker-1]="192.168.122.201"
node_ip[worker-2]="192.168.122.202"

declare -A node_mac
node_mac[controller-0]="52:54:00:00:00:00"
node_mac[controller-1]="52:54:00:00:00:01"
node_mac[controller-2]="52:54:00:00:00:02"
node_mac[worker-0]="52:54:00:00:01:00"
node_mac[worker-1]="52:54:00:00:01:01"
node_mac[worker-2]="52:54:00:00:01:02"
