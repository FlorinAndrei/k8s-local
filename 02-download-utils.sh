#!/usr/bin/env bash

wget https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64
mv cfssl_1.6.4_linux_amd64 cfssl
chmod 755 cfssl
wget https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64
mv cfssljson_1.6.4_linux_amd64 cfssljson
chmod 755 cfssljson
wget https://storage.googleapis.com/kubernetes-release/release/v1.29.0/bin/linux/amd64/kubectl
chmod 755 kubectl

echo "Move cfssl, cfssljson, and kubectl to a directory in the PATH."
