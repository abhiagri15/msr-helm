# webMethods MSR Helm Chart

Helm chart for deploying webMethods Microservices Runtime (MSR) v11.1.0.6 on Kubernetes with Azure Key Vault integration.

## Features

- Azure Key Vault integration for keystores and truststores
- PostgreSQL database integration
- Universal Messaging (UM) cluster integration
- Terracotta distributed caching
- Horizontal Pod Autoscaler (HPA)
- StatefulSet with persistent volumes

## Prerequisites

- Kubernetes cluster (AKS recommended)
- Helm 3.x
- Azure CLI configured
- Azure Key Vault with CSI driver enabled

## Quick Start

### 1. Deploy Infrastructure

```bash
# Create namespace
kubectl create namespace webmethods

# Deploy PostgreSQL
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgresql bitnami/postgresql \
  --namespace webmethods \
  --set auth.postgresPassword=admin123 \
  --set auth.database=webmethods

# Deploy UM (optional)
helm install wm-um ../um-helm \
  --namespace webmethods \
  --values ../um-helm/values-dev.yaml

# Deploy Terracotta (optional)
helm install terracotta-bmm ../webmethods-helm-charts/terracottabigmemorymax/helm \
  --namespace webmethods
```

### 2. Setup Azure Key Vault

See [AZURE_KEYVAULT.md](AZURE_KEYVAULT.md) for complete setup instructions.

**Quick summary:**

```bash
# Enable CSI driver on AKS
az aks enable-addons \
  --addons azure-keyvault-secrets-provider \
  --resource-group <RG_NAME> \
  --name <CLUSTER_NAME>

# Get managed identity client ID
az aks show \
  --resource-group <RG_NAME> \
  --name <CLUSTER_NAME> \
  --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId \
  -o tsv

# Grant Key Vault access
az keyvault set-policy \
  --name <VAULT_NAME> \
  --object-id <IDENTITY_OBJECT_ID> \
  --secret-permissions get \
  --certificate-permissions get
```

### 3. Create Certificates in Azure Key Vault

**Keystore (with private key):**
```bash
# Generate self-signed certificate
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout wm-cert.key -out wm-cert.crt -days 365 \
  -subj "/CN=webmethods-msr/O=YourOrg/C=US"

# Convert to PKCS12
openssl pkcs12 -export -in wm-cert.crt -inkey wm-cert.key \
  -out wm-cert.p12 -passout pass:

# Import to Key Vault as Certificate
az keyvault certificate import \
  --vault-name <VAULT_NAME> \
  --name wm-cer \
  --file wm-cert.p12
```

**Truststore certificates (public certs only):**
```bash
# Store as Secrets (not Certificates)
az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name truststore-root-ca \
  --file root-ca.crt

az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name truststore-partner-cert \
  --file partner.crt

# Repeat for all truststore certificates
```

### 4. Configure values-dev.yaml

Update Azure Key Vault settings:

```yaml
azureKeyVault:
  enabled: true
  vaultName: "wM-kv"
  tenantId: "YOUR_TENANT_ID"
  clientId: "YOUR_MANAGED_IDENTITY_CLIENT_ID"

keystoreCertificate:
  enabled: true
  certName: "wm-cer"
  keystoreFileName: "wm_keystore.p12"
  aliasName: "WM_KEYSTORE"
  password: "changeit"

truststoreCertificates:
  enabled: true
  fileName: "wm_truststore.p12"
  aliasName: "WM_TRUSTSTORE"
  password: "changeit"
  certificates:
    - certName: "truststore-root-ca"
      alias: "root-ca"
    - certName: "truststore-partner-cert"
      alias: "partner-cert"
```

### 5. Deploy MSR

```bash
helm install wm-msr . \
  --namespace webmethods \
  --values values-dev.yaml \
  --timeout=15m
```

### 6. Access MSR

```bash
# Port forward
kubectl port-forward -n webmethods svc/wm-msr 5555:5555

# Open browser
# URL: http://localhost:5555
# Username: Administrator
# Password: manage
```

## Configuration

### Important Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of MSR replicas | `2` |
| `image.repository` | MSR Docker image repository | `abiwebmethods.azurecr.io/webmethods-microservicesruntime` |
| `image.tag` | MSR version | `11.1.0.6-dev` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `jdbcPool.enabled` | Enable MSR internal JDBC pool | `false` |
| `jdbcAdapter.enabled` | Enable JDBC adapter connections | `false` |
| `azureKeyVault.enabled` | Enable Azure Key Vault integration | `false` |
| `um.enabled` | Enable Universal Messaging integration | `false` |
| `terracotta.enabled` | Enable Terracotta caching | `false` |
| `truststoreCertificates.enabled` | Enable truststore from Key Vault | `false` |

See [values-dev.yaml](values-dev.yaml) for complete configuration example.

### Minimal Deployment (No Database)

For a minimal deployment without database or integrations:

```bash
helm upgrade --install wm-msr . \
  --namespace webmethods \
  --set image.tag=11.1.0.6-dev \
  --set replicaCount=1 \
  --set jdbcAdapter.enabled=false \
  --set jdbcPool.enabled=false \
  --set um.enabled=false \
  --set terracotta.enabled=false \
  --set azureKeyVault.enabled=false \
  --set truststoreCertificates.enabled=false \
  --set persistence.enabled=true
```

**Note:** You may need to create a placeholder JDBC secrets if the pod fails to start:
```bash
kubectl create secret generic wm-msr-jdbc-secrets -n webmethods \
  --from-literal=JDBC_POOL_URL=dummy \
  --from-literal=JDBC_POOL_USERNAME=dummy \
  --from-literal=JDBC_POOL_PASSWORD=dummy
```

## How It Works

### Keystore from Azure Key Vault

1. Certificate stored in Azure Key Vault (includes private key)
2. CSI driver mounts as `.crt` and `.key` files
3. Init container converts to PKCS12 keystore using OpenSSL

### Truststore from Azure Key Vault

1. Public certificates stored as Secrets in Azure Key Vault
2. CSI driver mounts each certificate file
3. Init container uses Java keytool to import each certificate with individual alias
4. Result: PKCS12 truststore with visible certificate aliases in MSR Admin UI

**Init container image:** `eclipse-temurin:11-jdk` (includes Azure CLI, OpenSSL, keytool)

## Verification

### Check deployment status
```bash
kubectl get pods -n webmethods -l app=wm-msr
kubectl get statefulset -n webmethods wm-msr
kubectl get svc -n webmethods -l app=wm-msr
```

### Check init container logs
```bash
kubectl logs wm-msr-0 -n webmethods -c copy-keyvault-keystores
```

Expected output:
```
Converting Key Vault certificate to PKCS12 keystore...
Successfully created keystore wm_keystore.p12

Creating truststore from Azure Key Vault certificates using keytool...
Importing certificate truststore-root-ca with alias root-ca...
Certificate was added to keystore
Importing certificate truststore-partner-cert with alias partner-cert...
Certificate was added to keystore
Successfully created truststore wm_truststore.p12 with 2 certificate(s)
```

### Verify certificates in MSR UI
1. Login to MSR: http://localhost:5555
2. Navigate to: Security > Keystore
3. Check WM_KEYSTORE for keystore
4. Check WM_TRUSTSTORE > Certificate Aliases for individual truststore certificates

## Troubleshooting

### Pod fails to start

```bash
# Check events
kubectl get events -n webmethods --sort-by='.lastTimestamp'

# Check pod status
kubectl describe pod wm-msr-0 -n webmethods
```

### Certificates not mounting

```bash
# Check CSI driver
kubectl get pods -n kube-system -l app=secrets-store-csi-driver

# Check SecretProviderClass
kubectl describe secretproviderclass wm-msr-keyvault-sync -n webmethods

# Check CSI driver logs
kubectl logs -n kube-system -l app=csi-secrets-store-provider-azure
```

### Certificate not found in Key Vault

```bash
# List certificates
az keyvault certificate list --vault-name <VAULT_NAME> --output table

# List secrets
az keyvault secret list --vault-name <VAULT_NAME> --output table
```

### Identity permission issues

```bash
# Check Key Vault access policy
az keyvault show --name <VAULT_NAME> --query "properties.accessPolicies"
```

## Updating Certificates

### Update keystore certificate
```bash
# Re-import to Key Vault (creates new version)
az keyvault certificate import \
  --vault-name <VAULT_NAME> \
  --name wm-cer \
  --file updated-cert.p12

# Restart pods
kubectl rollout restart statefulset wm-msr -n webmethods
```

### Add truststore certificate
```bash
# Upload new certificate
az keyvault secret set \
  --vault-name <VAULT_NAME> \
  --name truststore-new-cert \
  --file new-cert.crt

# Update values-dev.yaml
# Add new certificate to truststoreCertificates.certificates list

# Upgrade Helm release
helm upgrade wm-msr . \
  --namespace webmethods \
  --values values-dev.yaml
```

## Uninstall

```bash
# Uninstall Helm release
helm uninstall wm-msr -n webmethods

# Delete PVCs
kubectl delete pvc -l app=wm-msr -n webmethods

# Delete namespace (optional)
kubectl delete namespace webmethods
```

## Documentation

- [AZURE_KEYVAULT.md](AZURE_KEYVAULT.md) - Step-by-step Azure Key Vault integration guide
- [CHANGELOG.md](CHANGELOG.md) - Version history and changes

## Support

For issues:
1. Check init container logs for certificate loading errors
2. Verify Azure Key Vault access policies
3. Ensure CSI driver is installed and running
4. Check SecretProviderClass configuration
5. Review MSR application logs: `kubectl logs wm-msr-0 -n webmethods`

## Version

Current version: **2.0.0**

- MSR Image: `abiwebmethods.azurecr.io/webmethods-microservicesruntime:11.1.0.6-dev`
- Init Container: `eclipse-temurin:11-jdk` (for Azure Key Vault certificate processing)
- Azure Key Vault integration with CSI driver
- Keystore and truststore auto-generated from Azure Key Vault
- Optional JDBC Pool and JDBC Adapter configuration
- Universal Messaging and Terracotta cache support

## Recent Changes (December 2024)

- Fixed values mismatch between `values.yaml` and templates
- Added `jdbcPool` and `jdbcAdapter` configuration sections
- Added `truststoreCertificates` configuration section
- Made JDBC secrets optional with `optional: true`
- Updated documentation to match actual deployment parameters
- Added minimal deployment example
