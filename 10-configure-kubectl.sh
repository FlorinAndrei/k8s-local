#!/usr/bin/env bash

. ./variables.sh

KUBERNETES_PUBLIC_ADDRESS="$main_host_ip"

kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

kubectl config set-credentials admin-k8s-local \
    --embed-certs=true \
    --client-certificate=ca/admin.pem \
    --client-key=ca/admin-key.pem

kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin-k8s-local

kubectl config use-context kubernetes-the-hard-way

echo
kubectl version
echo
kubectl get nodes -o wide
