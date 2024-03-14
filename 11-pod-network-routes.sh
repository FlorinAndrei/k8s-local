#!/usr/bin/env bash

. ./variables.sh

echo "Setting pod network routes..."
sudo ip route add ${cluster_cidr_worker[worker-0]} via ${node_ip[worker-0]}
sudo ip route add ${cluster_cidr_worker[worker-1]} via ${node_ip[worker-1]}
sudo ip route add ${cluster_cidr_worker[worker-2]} via ${node_ip[worker-2]}

echo
echo "Current routes:"
echo

sudo ip route
