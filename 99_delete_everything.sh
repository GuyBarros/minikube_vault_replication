minikube stop cluster-1
minikube delete --profile cluster-1
rm csr_vault_primary.yaml vault_primary.csr vault_primary.key vault_primary.crt vault_primary.ca vault_primary-cluster-keys.json vault-csr_primary.conf
minikube stop cluster-2
minikube delete --profile cluster-2
rm csr_vault_secondary.yaml vault_secondary.csr vault_secondary.key vault_secondary.crt vault_secondary.ca vault_secondary-cluster-keys.json vault-csr_secondary.conf