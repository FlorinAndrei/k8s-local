#!/usr/bin/env bash

wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
qemu-img info jammy-server-cloudimg-amd64.img
sudo mkdir /var/lib/libvirt/images/base
sudo mv jammy-server-cloudimg-amd64.img /var/lib/libvirt/images/base/ubuntu-22.04.qcow2
