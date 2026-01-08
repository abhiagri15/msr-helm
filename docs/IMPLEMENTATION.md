# webMethods MSR Helm Chart - Implementation Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Azure Infrastructure Setup](#azure-infrastructure-setup)
4. [Azure Key Vault Configuration](#azure-key-vault-configuration)
5. [Container Registry Setup](#container-registry-setup)
6. [Helm Chart Deployment](#helm-chart-deployment)
7. [Environment-Specific Deployments](#environment-specific-deployments)
8. [Integration Configuration](#integration-configuration)
9. [Troubleshooting](#troubleshooting)
10. [Upgrade Procedures](#upgrade-procedures)
11. [Backup and Recovery](#backup-and-recovery)

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|------|-----------------|--------------|
| Azure CLI | 2.50+ | `winget install Microsoft.AzureCLI` |
| kubectl | 1.28+ | `az aks install-cli` |
| Helm | 3.12+ | `winget install Helm.Helm` |
| Docker | 24.0+ | Docker Desktop for Windows |

### Azure Subscription Requirements

- Active Azure subscription with Contributor access
- Resource providers registered:
  - `Microsoft.ContainerService`
  - `Microsoft.KeyVault`
  - `Microsoft.ContainerRegistry`
  - `Microsoft.Sql` (if using Azure SQL)

### Network Requirements

| Source | Destination | Port | Purpose |
|--------|-------------|------|---------|
| AKS Nodes | Azure Key Vault | 443 | Secret retrieval |
| AKS Nodes | Container Registry | 443 | Image pull |
| MSR Pods | Database | 1433/5432 | JDBC connections |
| MSR Pods | Universal Messaging | 9000 | Messaging |
| MSR Pods | Terracotta | 9510 | Session clustering |

---

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone https://github.com/your-org/msr-helm.git
cd msr-helm

# Login to Azure
az login
az account set --subscription "Your-Subscription-Name"

# Get AKS credentials
az aks get-credentials --resource-group webmethods-rg --name webmethods-aks
```

### 2. Create Namespace

```bash
kubectl create namespace webmethods
```

### 3. Deploy Minimal Configuration

```bash
# Deploy with default values (no external dependencies)
helm install wm-msr . -n webmethods \
  --set replicaCount=1 \
  --set persistence.enabled=false \
  --set jdbcPool.enabled=false \
  --set um.enabled=false \
  --set terracotta.enabled=false
```

### 4. Verify Deployment

```bash
# Check pod status
kubectl get pods -n webmethods -w

# Check MSR logs
kubectl logs -n webmethods wm-msr-0 -f

# Access MSR Admin Console (port-forward)
kubectl port-forward -n webmethods svc/wm-msr 5555:5555
# Open: http://localhost:5555
```

---

## Azure Infrastructure Setup

### Create Resource Group

```bash
# Variables
RESOURCE_GROUP="webmethods-rg"
LOCATION="eastus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Create AKS Cluster

```bash
# Variables
AKS_NAME="webmethods-aks"
NODE_COUNT=3
NODE_SIZE="Standard_D4s_v5"

# Create AKS cluster with Azure Key Vault CSI driver
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --enable-managed-identity \
  --enable-addons azure-keyvault-secrets-provider \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME
```

### Create Azure Container Registry

```bash
ACR_NAME="webmethodsacr"

# Create ACR
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Standard

# Attach ACR to AKS
az aks update \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --attach-acr $ACR_NAME
```

### Create Azure SQL Database (Optional)

```bash
SQL_SERVER="webmethods-sql"
SQL_DB="msrdb"
SQL_ADMIN="sqladmin"
SQL_PASSWORD="YourSecurePassword123!"

# Create SQL Server
az sql server create \
  --resource-group $RESOURCE_GROUP \
  --name $SQL_SERVER \
  --admin-user $SQL_ADMIN \
  --admin-password $SQL_PASSWORD

# Create database
az sql db create \
  --resource-group $RESOURCE_GROUP \
  --server $SQL_SERVER \
  --name $SQL_DB \
  --service-objective S1

# Allow Azure services
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SQL_SERVER \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

---

## Azure Key Vault Configuration

### Create Key Vault

```bash
KEY_VAULT="webmethods-kv"

# Create Key Vault
az keyvault create \
  --resource-group $RESOURCE_GROUP \
  --name $KEY_VAULT \
  --location $LOCATION \
  --enable-rbac-authorization false

# Get AKS kubelet identity
KUBELET_IDENTITY=$(az aks show \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --query identityProfile.kubeletidentity.clientId -o tsv)

# Grant access to Key Vault
az keyvault set-policy \
  --name $KEY_VAULT \
  --secret-permissions get list \
  --certificate-permissions get list \
  --object-id $(az ad sp show --id $KUBELET_IDENTITY --query id -o tsv)
```

### Secret Naming Convention

All secrets use environment-specific prefixes:

| Environment | Prefix | Example |
|-------------|--------|---------|
| Development | `dev-` | `dev-jdbc-pool-password` |
| QA/Test | `test-` | `test-jdbc-pool-password` |
| Production | `prod-` | `prod-jdbc-pool-password` |

### Create Development Secrets

```bash
# JDBC Pool credentials
az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-jdbc-pool-url" \
  --value "jdbc:sqlserver://server.database.windows.net:1433;database=msrdb"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-jdbc-pool-username" \
  --value "sqladmin"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-jdbc-pool-password" \
  --value "YourSecurePassword123!"

# JDBC Adapter credentials (if different from pool)
az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-jdbc-adapter-url" \
  --value "jdbc:sqlserver://server.database.windows.net:1433;database=adapterdb"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-jdbc-adapter-username" \
  --value "adapteruser"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-jdbc-adapter-password" \
  --value "AdapterPassword123!"

# Security credentials
az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-keystore-password" \
  --value "keystorepassword"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-keyalias-password" \
  --value "keyaliaspassword"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-truststore-password" \
  --value "truststorepassword"

# Universal Messaging password
az keyvault secret set --vault-name $KEY_VAULT \
  --name "dev-um-password" \
  --value "manage"
```

### Create QA/Test Secrets

```bash
# Use test- prefix for QA environment
az keyvault secret set --vault-name $KEY_VAULT \
  --name "test-jdbc-pool-url" \
  --value "jdbc:sqlserver://qa-server.database.windows.net:1433;database=msrdb"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "test-jdbc-pool-username" \
  --value "qaadmin"

az keyvault secret set --vault-name $KEY_VAULT \
  --name "test-jdbc-pool-password" \
  --value "QASecurePassword123!"

# Repeat for other secrets with test- prefix...
```

### Upload Certificates to Key Vault

```bash
# Upload keystore certificate (with private key)
az keyvault certificate import \
  --vault-name $KEY_VAULT \
  --name "dev-msr-keystore" \
  --file "/path/to/keystore.pfx" \
  --password "pfxpassword"

# Upload truststore certificates (public only)
az keyvault secret set \
  --vault-name $KEY_VAULT \
  --name "dev-truststore-root-ca" \
  --file "/path/to/root-ca.cer" \
  --encoding base64
```

---

## Container Registry Setup

### Push MSR Image to ACR

```bash
ACR_NAME="webmethodsacr"

# Login to ACR
az acr login --name $ACR_NAME

# Tag and push image
docker tag webmethods-msr:11.1.0.6 ${ACR_NAME}.azurecr.io/webmethods-msr:11.1.0.6
docker push ${ACR_NAME}.azurecr.io/webmethods-msr:11.1.0.6
```

### Create Image Pull Secret (if using external registry)

```bash
kubectl create secret docker-registry regcred \
  --namespace webmethods \
  --docker-server=sagcr.azurecr.io \
  --docker-username=your-username \
  --docker-password=your-password
```

---

## Helm Chart Deployment

### Update values.yaml for Your Environment

Key configuration sections in `values.yaml`:

```yaml
# 1. Image Configuration
image:
  repository: your-acr.azurecr.io/webmethods-msr
  tag: "11.1.0.6"
  pullPolicy: IfNotPresent

# 2. Azure Key Vault
azureKeyVault:
  enabled: true
  vaultName: "your-keyvault"
  tenantId: "your-tenant-id"
  clientId: "kubelet-identity-client-id"
  secretKeyPrefix: "dev"  # Use "test" for QA, "prod" for production

# 3. JDBC Pool (for ISInternal, Xref)
jdbcPool:
  enabled: true
  pool:
    name: "IS-Pool"
    driverAlias: "DataDirect SQL Server"

# 4. Universal Messaging
um:
  enabled: true
  url: "nsp://wm-um.webmethods.svc.cluster.local:9000"

# 5. Terracotta (for session clustering)
terracotta:
  enabled: true
  urls:
    - "terracotta-0.terracotta.webmethods.svc.cluster.local:9510"
```

### Get Required Azure IDs

```bash
# Get Tenant ID
az account show --query tenantId -o tsv

# Get Kubelet Identity Client ID
az aks show \
  --resource-group webmethods-rg \
  --name webmethods-aks \
  --query identityProfile.kubeletidentity.clientId -o tsv
```

### Deploy with Helm

```bash
# Deploy to development (with all adapters)
helm upgrade --install wm-msr . \
  -n webmethods \
  -f values.yaml \
  -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml \
  -f adapters/values-sap-adapter-dev.yaml

# Deploy to development (JDBC only, no SAP)
helm upgrade --install wm-msr . \
  -n webmethods \
  -f values.yaml \
  -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml

# Deploy to QA
helm upgrade --install wm-msr . \
  -n webmethods \
  -f values.yaml \
  -f values-qa.yaml \
  -f adapters/values-jdbc-adapter-qa.yaml \
  -f adapters/values-sap-adapter-qa.yaml

# Deploy to production
helm upgrade --install wm-msr . \
  -n webmethods \
  -f values.yaml \
  -f values-prod.yaml \
  -f adapters/values-jdbc-adapter-prod.yaml \
  -f adapters/values-sap-adapter-prod.yaml
```

**Note:** Adapter configurations are in the `adapters/` folder. Include only the adapters you need.

### Verify Deployment

```bash
# Check all resources
kubectl get all -n webmethods

# Check SecretProviderClass
kubectl get secretproviderclass -n webmethods

# Check secrets created from Key Vault
kubectl get secrets -n webmethods

# Check ConfigMaps
kubectl get configmap -n webmethods

# Describe pod for events
kubectl describe pod wm-msr-0 -n webmethods
```

---

## Environment-Specific Deployments

### Development Environment

**File: `values-dev.yaml`**

```yaml
replicaCount: 1

image:
  tag: "11.1.0.6-dev"

resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"

azureKeyVault:
  enabled: true
  vaultName: "webmethods-kv"
  tenantId: "your-tenant-id"
  clientId: "your-client-id"
  secretKeyPrefix: "dev"

jdbcPool:
  enabled: true

um:
  enabled: false

terracotta:
  enabled: false

autoscaling:
  enabled: false
```

**Deploy:**
```bash
helm upgrade --install wm-msr . -n webmethods \
  -f values.yaml -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml
```

### QA/Test Environment

**File: `values-qa.yaml`**

```yaml
replicaCount: 2

image:
  tag: "11.1.0.6-qa"

resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"

azureKeyVault:
  enabled: true
  vaultName: "webmethods-kv"
  tenantId: "your-tenant-id"
  clientId: "your-client-id"
  secretKeyPrefix: "test"

jdbcPool:
  enabled: true

um:
  enabled: true
  url: "nsp://wm-um-qa.webmethods.svc.cluster.local:9000"

terracotta:
  enabled: false

autoscaling:
  enabled: false
```

**Deploy:**
```bash
helm upgrade --install wm-msr . -n webmethods \
  -f values.yaml -f values-qa.yaml \
  -f adapters/values-jdbc-adapter-qa.yaml \
  -f adapters/values-sap-adapter-qa.yaml
```

### Production Environment

**File: `values-prod.yaml`**

```yaml
replicaCount: 3

image:
  tag: "11.1.0.6"
  pullPolicy: Always

resources:
  requests:
    memory: "4Gi"
    cpu: "2000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"

jvm:
  minMemory: "2048m"
  maxMemory: "4096m"

azureKeyVault:
  enabled: true
  vaultName: "webmethods-prod-kv"  # Separate Key Vault for production
  tenantId: "your-tenant-id"
  clientId: "your-client-id"
  secretKeyPrefix: "prod"

jdbcPool:
  enabled: true
  pool:
    minConns: 5
    maxConns: 50
    poolThreshold: 20

um:
  enabled: true
  url: "nsp://wm-um-prod.webmethods.svc.cluster.local:9000"

terracotta:
  enabled: true
  urls:
    - "terracotta-0.terracotta.webmethods.svc.cluster.local:9510"
    - "terracotta-1.terracotta.webmethods.svc.cluster.local:9510"

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

podDisruptionBudget:
  enabled: true
  minAvailable: 2
```

**Deploy:**
```bash
helm upgrade --install wm-msr . -n webmethods \
  -f values.yaml -f values-prod.yaml \
  -f adapters/values-jdbc-adapter-prod.yaml \
  -f adapters/values-sap-adapter-prod.yaml
```

---

## Integration Configuration

### JDBC Pool Configuration

The JDBC Pool is used for MSR internal operations (ISInternal, Xref, ISDashboardStats).

**values.yaml:**
```yaml
jdbcPool:
  enabled: true
  pool:
    name: "IS-Pool"
    driverAlias: "DataDirect SQL Server"  # or "PostgresqlDriver"
    dataSourceClass: "com.microsoft.sqlserver.jdbc.SQLServerDataSource"
    minConns: 1
    maxConns: 25
    poolThreshold: 10
    waitingThread: 100
    expireTime: 60000
    useSSL: false
  functionalAliases:
    - name: "ISInternal"
      connPoolAlias: "IS-Pool"
      failFastMode: true
    - name: "ISDashboardStats"
      connPoolAlias: "IS-Pool"
      failFastMode: false
    - name: "Xref"
      connPoolAlias: "IS-Pool"
      failFastMode: true
```

**Azure Key Vault Secrets Required:**
- `{prefix}-jdbc-pool-url`
- `{prefix}-jdbc-pool-username`
- `{prefix}-jdbc-pool-password`

### JDBC Adapter Configuration

The JDBC Adapter is used for package-level database connections.

**values.yaml:**
```yaml
jdbcAdapter:
  enabled: true
  connections:
    - name: "MyPackageConnection"
      description: "JDBC connection for MyPackage"
      packageName: "MyPackage"
      folderName: "connection"
      connectionType: "jdbc"
      connectionFactoryInterface: "javax.sql.DataSource"
      transactionType: "LOCAL_TRANSACTION"
      minPoolSize: 1
      maxPoolSize: 10
      poolIncrementSize: 1
      blockTimeout: 30000
      expireTimeout: 60000
      startupRetryCount: 3
      startupBackoffSecs: 10
```

**Azure Key Vault Secrets Required:**
- `{prefix}-jdbc-adapter-url`
- `{prefix}-jdbc-adapter-username`
- `{prefix}-jdbc-adapter-password`

### Universal Messaging Configuration

**values.yaml:**
```yaml
um:
  enabled: true
  connectionEnabled: true
  connectionAlias: "IS_UM_CONNECTION"
  url: "nsp://wm-um.webmethods.svc.cluster.local:9000"
  user: "Administrator"
  useCSQ: "true"
  csqSize: "-1"
  csqDrainInOrder: "true"
```

**Azure Key Vault Secret Required:**
- `{prefix}-um-password`

### Terracotta Session Clustering

**values.yaml:**
```yaml
terracotta:
  enabled: true
  cacheManagerName: "IS_TERRACOTTA_CACHE"
  urls:
    - "terracotta-0.terracotta.webmethods.svc.cluster.local:9510"
    - "terracotta-1.terracotta.webmethods.svc.cluster.local:9510"
  waitForReady: true
```

### Keystore/Truststore Configuration

**values.yaml:**
```yaml
azureKeyVault:
  enabled: true
  certificates:
    - certName: "msr-keystore"
      fileName: "msr_keystore.p12"
      keystoreConfig:
        aliasName: "MSR_KEYSTORE"
        description: "MSR Server Keystore"
        type: "PKCS12"
        provider: "SunJSSE"
        isHsm: false
        keys:
          - keyAliasName: "serverkey"

truststoreCertificates:
  enabled: true
  fileName: "msr_truststore.p12"
  aliasName: "MSR_TRUSTSTORE"
  description: "MSR Truststore"
  type: "PKCS12"
  provider: "SunJSSE"
  certificates:
    - certName: "root-ca"
      alias: "root-ca"
    - certName: "partner-cert"
      alias: "partner-cert"
```

**Azure Key Vault Secrets Required:**
- `{prefix}-keystore-password`
- `{prefix}-keyalias-password`
- `{prefix}-truststore-password`

---

## Troubleshooting

### Pod Stuck in Pending State

**Check node resources:**
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
kubectl top nodes
```

**Solution - Scale AKS cluster:**
```bash
az aks scale \
  --resource-group webmethods-rg \
  --name webmethods-aks \
  --node-count 4
```

### Pod Stuck in ContainerCreating

**Check for secret/volume issues:**
```bash
kubectl describe pod wm-msr-0 -n webmethods
kubectl get events -n webmethods --sort-by='.lastTimestamp'
```

**Common causes:**
1. **Key Vault secrets not found** - Verify secret names match exactly
2. **Identity permissions** - Verify kubelet identity has Key Vault access
3. **CSI driver not installed** - Enable azure-keyvault-secrets-provider addon

### MSR Fails to Start

**Check MSR logs:**
```bash
kubectl logs wm-msr-0 -n webmethods
kubectl logs wm-msr-0 -n webmethods --previous
```

**Common causes:**
1. **JDBC connection failure** - Verify database connectivity and credentials
2. **License issue** - Check license file is valid
3. **Memory issue** - Increase JVM and container memory limits

### Database Connection Failures

**Test database connectivity:**
```bash
# Exec into pod
kubectl exec -it wm-msr-0 -n webmethods -- /bin/bash

# Test connection (inside pod)
nc -zv database-server 1433
```

**Verify secrets are mounted:**
```bash
kubectl exec wm-msr-0 -n webmethods -- printenv | grep JDBC
```

### Key Vault Access Issues

**Verify identity permissions:**
```bash
# Get kubelet identity
KUBELET_ID=$(az aks show -g webmethods-rg -n webmethods-aks \
  --query identityProfile.kubeletidentity.clientId -o tsv)

# Check Key Vault access
az keyvault show --name webmethods-kv \
  --query "properties.accessPolicies[?objectId=='$KUBELET_ID']"
```

**Grant permissions if missing:**
```bash
az keyvault set-policy \
  --name webmethods-kv \
  --secret-permissions get list \
  --certificate-permissions get list \
  --object-id $(az ad sp show --id $KUBELET_ID --query id -o tsv)
```

### Terracotta Connection Issues

**Check Terracotta pods:**
```bash
kubectl get pods -n webmethods -l app=terracotta
kubectl logs terracotta-0 -n webmethods
```

**Verify Terracotta URLs:**
```bash
# Test connectivity from MSR pod
kubectl exec -it wm-msr-0 -n webmethods -- nc -zv terracotta-0.terracotta.webmethods.svc.cluster.local 9510
```

---

## Upgrade Procedures

### Rolling Update (Recommended)

```bash
# Update image tag
helm upgrade wm-msr . -n webmethods \
  -f values.yaml \
  -f values-dev.yaml \
  --set image.tag="11.1.0.7"

# Monitor rollout
kubectl rollout status statefulset/wm-msr -n webmethods
```

### Blue-Green Deployment

```bash
# Deploy new version with different release name
helm install wm-msr-v2 . -n webmethods \
  -f values.yaml \
  -f values-prod.yaml \
  --set image.tag="11.1.0.7"

# Verify new deployment
kubectl get pods -n webmethods -l app.kubernetes.io/instance=wm-msr-v2

# Switch traffic (update ingress or service)
# Then remove old deployment
helm uninstall wm-msr -n webmethods
```

### Rollback

```bash
# View history
helm history wm-msr -n webmethods

# Rollback to previous version
helm rollback wm-msr -n webmethods

# Rollback to specific revision
helm rollback wm-msr 2 -n webmethods
```

---

## Backup and Recovery

### Backup Strategy

1. **Configuration Backup (Helm values)**
   ```bash
   # Export current values
   helm get values wm-msr -n webmethods > backup/values-$(date +%Y%m%d).yaml
   ```

2. **Database Backup**
   ```bash
   # Azure SQL automated backups are enabled by default
   # For manual backup:
   az sql db copy \
     --resource-group webmethods-rg \
     --server webmethods-sql \
     --name msrdb \
     --dest-name msrdb-backup-$(date +%Y%m%d)
   ```

3. **Persistent Volume Backup**
   ```bash
   # Create volume snapshot
   kubectl apply -f - <<EOF
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: msr-snapshot-$(date +%Y%m%d)
     namespace: webmethods
   spec:
     source:
       persistentVolumeClaimName: data-wm-msr-0
   EOF
   ```

### Recovery Procedures

**Restore from Helm values:**
```bash
helm upgrade --install wm-msr . -n webmethods -f backup/values-20231215.yaml
```

**Restore database:**
```bash
# Point-in-time restore
az sql db restore \
  --resource-group webmethods-rg \
  --server webmethods-sql \
  --name msrdb \
  --dest-name msrdb-restored \
  --time "2023-12-15T10:00:00Z"
```

---

## Appendix

### Useful Commands Reference

```bash
# View all MSR resources
kubectl get all -n webmethods -l app.kubernetes.io/name=webmethods-msr

# Watch pod status
kubectl get pods -n webmethods -w

# Get pod logs
kubectl logs -f wm-msr-0 -n webmethods

# Execute command in pod
kubectl exec -it wm-msr-0 -n webmethods -- /bin/bash

# Port forward for admin console
kubectl port-forward svc/wm-msr 5555:5555 -n webmethods

# View secret content (base64 decoded)
kubectl get secret wm-msr-jdbc-secrets -n webmethods -o jsonpath='{.data.JDBC_POOL_URL}' | base64 -d

# Scale deployment
kubectl scale statefulset wm-msr --replicas=3 -n webmethods

# View resource usage
kubectl top pods -n webmethods

# Restart pods (rolling)
kubectl rollout restart statefulset/wm-msr -n webmethods
```

### Environment Variables Reference

| Variable | Source | Description |
|----------|--------|-------------|
| `JDBC_POOL_URL` | Key Vault | JDBC Pool connection URL |
| `JDBC_POOL_USERNAME` | Key Vault | JDBC Pool username |
| `JDBC_POOL_PASSWORD` | Key Vault | JDBC Pool password |
| `JDBC_ADAPTER_URL` | Key Vault | JDBC Adapter connection URL |
| `JDBC_ADAPTER_USERNAME` | Key Vault | JDBC Adapter username |
| `JDBC_ADAPTER_PASSWORD` | Key Vault | JDBC Adapter password |
| `KEYSTORE_PASSWORD` | Key Vault | Keystore password |
| `KEYALIAS_PASSWORD` | Key Vault | Key alias password |
| `TRUSTSTORE_PASSWORD` | Key Vault | Truststore password |
| `UM_PASSWORD` | Key Vault | Universal Messaging password |

### SAP Adapter Configuration

SAP Adapter connections and listeners are configured in separate files under `adapters/`.

**File Structure:**
- `adapters/values-sap-adapter-dev.yaml` - Development SAP connections
- `adapters/values-sap-adapter-prod.yaml` - Production SAP connections

**Configuration Example:**
```yaml
sapAdapter:
  enabled: true
  # Package where SAP connections are defined
  connectionPackageName: "SmSAPConn"
  connectionFolderName: "SmSAPConn"
  # Package where SAP listeners are defined (can be different)
  listenerPackageName: "SmSAPListeners"
  listenerFolderName: "SmSAPListeners"

  connections:
    - name: "connNode_CustomerPrograms_Conn"
      alias: "CustomerPrograms_Conn"
      enabled: true
      appServerHost: "sap-server.example.com"
      client: "010"
      systemId: "PRD"
      # ... additional SAP connection settings

  listeners:
    - name: "ESB"
      enabled: true
      gatewayHost: "sap-server.example.com"
      gatewayService: "sapgw00"
      programId: "ESB"
      sncMode: "Yes"
      # ... additional listener settings
```

**Azure Key Vault Secrets Required:**
- `{prefix}-sap-{connection}-user` - SAP connection username
- `{prefix}-sap-{connection}-password` - SAP connection password

### File Access Control Configuration

File access control restricts which directories the `pub.file` services can read, write, or delete.

**Configuration in values-{env}.yaml:**
```yaml
fileAccessControl:
  enabled: true

  # Directories with READ permission for pub.file services
  allowedReadPaths: "/tmp;/opt/softwareag/IntegrationServer/instances/default/logs/**;/opt/softwareag/IntegrationServer/instances/default/data/**"

  # Directories with WRITE permission
  allowedWritePaths: "/tmp;/opt/softwareag/IntegrationServer/instances/default/data/**"

  # Directories with DELETE permission
  allowedDeletePaths: "/tmp"
```

**Path Format:**
- Use semicolons (`;`) to separate multiple paths
- Single asterisk (`*`) matches single directory level
- Double asterisk (`**`) matches multiple nested folders
- Paths are case-sensitive on Linux

**Verification:**
```bash
# Check if fileAccessControl.cnf is mounted
kubectl exec wm-msr-0 -n webmethods -c msr -- \
  cat /opt/softwareag/IntegrationServer/packages/WmPublic/config/fileAccessControl.cnf
```

### Package-Specific Configuration

Environment-specific app.properties can be configured per custom package.

**Configuration in values-{env}.yaml:**
```yaml
packageConfigs:
  enabled: true
  packages:
    - name: MyPackage
      appProperties: |
        api.url=https://api-dev.example.com/v1
        api.key=${MY_PACKAGE_API_KEY}
        timeout.seconds=30
```

**Note:** Sensitive values use `${ENV_VAR}` syntax and are injected from Azure Key Vault.

---

*Document Version: 2.3.0*
*Last Updated: January 2026*
