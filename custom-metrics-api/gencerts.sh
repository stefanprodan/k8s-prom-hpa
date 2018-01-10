#!/usr/bin/env bash

go get -u github.com/cloudflare/cfssl/cmd/...

export PURPOSE=metrics
openssl req -x509 -sha256 -new -nodes -days 365 -newkey rsa:2048 -keyout ${PURPOSE}-ca.key -out ${PURPOSE}-ca.crt -subj "/CN=ca"
echo '{"signing":{"default":{"expiry":"43800h","usages":["signing","key encipherment","'${PURPOSE}'"]}}}' > "${PURPOSE}-ca-config.json"

export SERVICE_NAME=custom-metrics-apiserver
export ALT_NAMES='"custom-metrics-apiserver.monitoring","custom-metrics-apiserver.monitoring.svc"'
echo '{"CN":"'${SERVICE_NAME}'","hosts":['${ALT_NAMES}'],"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=metrics-ca.crt -ca-key=metrics-ca.key -config=metrics-ca-config.json - | cfssljson -bare apiserver

cat <<-EOF > cm-adapter-serving-certs.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cm-adapter-serving-certs
  namespace: monitoring
data:
  serving.crt: $(cat apiserver.pem | base64)
  serving.key: $(cat apiserver-key.pem | base64)
EOF

rm -f apiserver-key.pem
rm -f apiserver.csr
rm -f apiserver.pem
rm -f metrics-ca-config.json
rm -f metrics-ca.crt
rm -f metrics-ca.key
