#Create a variable named VAULT_UNSEAL_KEY to capture the Vault unseal key.
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" ${WORKDIR}/vault_primary-cluster-keys.json)

#Unseal Raft join vault-1 and vault-2
kubectl exec -ti  -n $VAULT_K8S_NAMESPACE vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti  -n $VAULT_K8S_NAMESPACE vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti -n $VAULT_K8S_NAMESPACE vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti -n $VAULT_K8S_NAMESPACE vault-2 -- vault operator raft join http://vault-0.vault-internal:8200

# minikube dashboard -p cluster-1
# minikube service -p cluster-1 vault-ui --url --https  -n $VAULT_K8S_NAMESPACE 