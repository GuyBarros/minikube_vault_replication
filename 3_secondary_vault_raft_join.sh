VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" ${WORKDIR}/vault_secondary-cluster-keys.json)


#Unseal Raft join vault-1 and vault-2
kubectl exec -ti  -n $VAULT_K8S_NAMESPACE vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti  -n $VAULT_K8S_NAMESPACE vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -ti -n $VAULT_K8S_NAMESPACE vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -ti -n $VAULT_K8S_NAMESPACE vault-2 -- vault operator raft join http://vault-0.vault-internal:8200


# minikube dashboard -p cluster-2
# minikube service -p cluster-2 vault-ui --url --https  -n $VAULT_K8S_NAMESPACE 