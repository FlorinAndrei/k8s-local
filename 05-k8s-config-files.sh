#!/usr/bin/env bash

. ./variables.sh

KUBERNETES_PUBLIC_ADDRESS="$main_host_ip"

echo
echo "Delete old *.kubeconfig files:"
rm -f *.kubeconfig

echo
echo "Generate a kubeconfig file for each worker node:"
echo

for instance in $workers; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=ca/${instance}.pem \
    --client-key=ca/${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done

echo
echo "Generate a kubeconfig file for the kube-proxy service:"
echo

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca/ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-credentials system:kube-proxy \
  --client-certificate=ca/kube-proxy.pem \
  --client-key=ca/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig

kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

echo
echo "Generate a kubeconfig file for the kube-controller-manager service:"
echo

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=ca/kube-controller-manager.pem \
  --client-key=ca/kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig

kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig

echo
echo "Generate a kubeconfig file for the kube-scheduler service:"
echo

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=ca/kube-scheduler.pem \
  --client-key=ca/kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig

kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig

echo
echo "Generate a kubeconfig file for the admin user:"
echo

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=ca/admin.pem \
  --client-key=ca/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default --kubeconfig=admin.kubeconfig

echo
echo "Copy the appropriate kubelet and kube-proxy kubeconfig files to each worker instance:"

for instance in ${workers}; do
  echo
  echo $instance
  echo
  scp $ssh_opts ${instance}.kubeconfig kube-proxy.kubeconfig $username@${node_ip[$instance]}:
done

echo
echo "Copy the appropriate kube-controller-manager and kube-scheduler kubeconfig files to each controller instance:"

for instance in ${controllers}; do
  echo
  echo $instance
  echo
  scp $ssh_opts admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig $username@${node_ip[$instance]}:
done
