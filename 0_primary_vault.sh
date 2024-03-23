#!/bin/bash
#script to set up Vault with TLS on Minikube, mostly copied from here: https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-tls#install-the-vault-helm-chart
#Start Minikube
minikube start --cpus=8 --memory 16G --disk-size 20G  -p cluster-1
minikube -p cluster-1 addons enable metrics-server

#Export the working directory location and the naming variables.
export VAULT_K8S_NAMESPACE="vault" \
export VAULT_HELM_RELEASE_NAME="vault" \
export VAULT_SERVICE_NAME="vault-internal" \
export K8S_CLUSTER_NAME="cluster.local" \
export WORKDIR=$(pwd)
export VAULT_LICENSE_PATH="/Users/guybarros/Hashicorp/vault.hclic"
#Create Vault Namespace
kubectl create ns $VAULT_K8S_NAMESPACE

#Create the consul ent license k8s secret
kubectl create secret generic vault-ent-license --namespace $VAULT_K8S_NAMESPACE --from-file=license=$VAULT_LICENSE_PATH


#Generate the private key
openssl genrsa -out ${WORKDIR}/vault_primary.key 2048

#Create the CSR configuration file
cat > ${WORKDIR}/vault-csr_primary.conf <<EOF
[req]
default_bits = 2048
prompt = no
encrypt_key = yes
default_md = sha256
distinguished_name = kubelet_serving
req_extensions = v3_req
[ kubelet_serving ]
O = system:nodes
CN = system:node:*.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.${VAULT_SERVICE_NAME}
DNS.2 = *.${VAULT_SERVICE_NAME}.${VAULT_K8S_NAMESPACE}.svc.${K8S_CLUSTER_NAME}
DNS.3 = *.${VAULT_K8S_NAMESPACE}
IP.1 = 127.0.0.1
EOF

#Generate the CSR
openssl req -new -key ${WORKDIR}/vault_primary.key -out ${WORKDIR}/vault_primary.csr -config ${WORKDIR}/vault-csr_primary.conf

#Create the csr yaml file to send it to Kubernetes.
cat > ${WORKDIR}/csr_vault_primary.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
   name: vault.svc
spec:
   signerName: kubernetes.io/kubelet-serving
   expirationSeconds: 8640000
   request: $(cat ${WORKDIR}/vault_primary.csr|base64|tr -d '\n')
   usages:
   - digital signature
   - key encipherment
   - server auth
EOF

#deploy CSR to Kubernetes
kubectl create -f ${WORKDIR}/csr_vault_primary.yaml

#Approve the CSR in Kubernetes.
kubectl certificate approve vault.svc

#Confirm the certificate was issued
kubectl get csr vault.svc
kubectl wait --for=condition=Issued csr vault.svc

sleep 5 
#Retrieve the certificate
kubectl get csr vault.svc -o jsonpath='{.status.certificate}' | openssl base64 -d -A -out ${WORKDIR}/vault_primary.crt

#Retrieve Kubernetes CA certificate
kubectl config view \
--raw \
--minify \
--flatten \
-o jsonpath='{.clusters[].cluster.certificate-authority-data}' \
| base64 -d > ${WORKDIR}/vault_primary.ca

#Create the TLS secret
kubectl create secret generic vault-ha-tls \
   -n $VAULT_K8S_NAMESPACE \
   --from-file=vault.key=${WORKDIR}/vault_primary.key \
   --from-file=vault.crt=${WORKDIR}/vault_primary.crt \
   --from-file=vault.ca=${WORKDIR}/vault_primary.ca

#Install Vault using the helm vaules file
# helm install --dry-run -n $VAULT_K8S_NAMESPACE $VAULT_HELM_RELEASE_NAME hashicorp/vault -f ${WORKDIR}/overrides.yaml   
helm install -n $VAULT_K8S_NAMESPACE $VAULT_HELM_RELEASE_NAME hashicorp/vault -f ${WORKDIR}/vault_primary.yaml   
sleep 3
#Check Pods
#kubectl wait --for=condition=Running -n $VAULT_K8S_NAMESPACE pod -l app.kubernetes.io/name=vault 
 kubectl -n $VAULT_K8S_NAMESPACE get pods

#When all three Vault nodes are running , Initialize Vault.
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- vault operator init \
    -key-shares=1 \
    -key-threshold=1 \
    -format=json > ${WORKDIR}/vault_primary-cluster-keys.json

#Create a variable named VAULT_UNSEAL_KEY to capture the Vault unseal key.
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" ${WORKDIR}/vault_primary-cluster-keys.json)

#Unseal Vault running on the vault-0 pod.
kubectl exec -n $VAULT_K8S_NAMESPACE vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY

# minikube service vault --url --https  -n $VAULT_K8S_NAMESPACE -p cluster-1