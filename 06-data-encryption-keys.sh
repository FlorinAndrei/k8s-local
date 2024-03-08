#!/usr/bin/env bash

. ./variables.sh

echo
echo "Generate an encryption key:"

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

echo
echo "Create the encryption-config.yaml encryption config file:"

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

echo
echo "Copy the encryption-config.yaml encryption config file to each controller instance:"

for instance in ${controllers}; do
  echo
  echo $instance
  echo
  scp $ssh_opts encryption-config.yaml $username@${node_ip[$instance]}:
done
