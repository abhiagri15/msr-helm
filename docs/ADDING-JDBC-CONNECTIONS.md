# Adding New JDBC Adapter Connections

This guide explains how to add new JDBC Adapter connections to the MSR Helm chart with Azure Key Vault integration.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step-by-Step Guide](#step-by-step-guide)
4. [File Reference](#file-reference)
5. [Examples](#examples)
6. [Troubleshooting](#troubleshooting)

---

## Overview

Adding a new JDBC Adapter connection requires modifications to three locations:

| Location | Purpose |
|----------|---------|
| Azure Key Vault | Store credentials securely |
| `templates/secretproviderclass.yaml` | Fetch secrets and create environment variables |
| `adapters/values-jdbc-adapter-{env}.yaml` | Define connection configuration |

### Architecture Flow

```
Azure Key Vault          SecretProviderClass           ConfigMap              MSR Pod
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────┐     ┌─────────────┐
│ dev-jdbc-mydb-  │────>│ Fetch secrets from  │────>│ artConnection│────>│ JDBC Adapter│
│ username        │     │ Key Vault, create   │     │ properties   │     │ Connection  │
│ dev-jdbc-mydb-  │     │ K8s secret with     │     │ with $env{}  │     │ Pool        │
│ password        │     │ env variables       │     │ references   │     │             │
└─────────────────┘     └─────────────────────┘     └──────────────┘     └─────────────┘
```

---

## Prerequisites

- Azure CLI installed and logged in
- Helm 3.12+
- kubectl configured for your AKS cluster
- Access to Azure Key Vault (`wM-kv`)
- Knowledge of:
  - Target database connection details (server, database, port)
  - IS Package name where the connection will be created
  - Folder name within the package

---

## Step-by-Step Guide

### Step 1: Add Secrets to Azure Key Vault

Add username and password secrets with the environment-specific prefix.

**Naming Convention:** `{prefix}-jdbc-{connection-short-name}-{username|password}`

```bash
# Set variables
VAULT_NAME="wM-kv"
PREFIX="dev"  # Use: dev, test, or prod
CONNECTION_NAME="mydb"  # Short name for your connection

# Add username secret
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name "${PREFIX}-jdbc-${CONNECTION_NAME}-username" \
  --value "your_db_username"

# Add password secret
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name "${PREFIX}-jdbc-${CONNECTION_NAME}-password" \
  --value "YourSecurePassword123!"

# Verify secrets were created
az keyvault secret list --vault-name $VAULT_NAME --query "[?starts_with(name, '${PREFIX}-jdbc-${CONNECTION_NAME}')]"
```

**Important:** Repeat for each environment (dev, test, prod) with appropriate values.

---

### Step 2: Update SecretProviderClass Template

Edit `templates/secretproviderclass.yaml` to fetch the new secrets from Key Vault.

#### 2a. Add to Objects Array

Find the `objects` section and add entries to fetch your new secrets:

```yaml
# File: templates/secretproviderclass.yaml
# Location: spec.parameters.objects

# Add these lines in the objects array (around line 50-100)
{{- if .Values.jdbcAdapter.enabled }}
# Existing JDBC adapter secrets...

# NEW: MyDB Connection Secrets
- |
  objectName: "{{ .Values.azureKeyVault.secretKeyPrefix }}-jdbc-mydb-username"
  objectType: secret
- |
  objectName: "{{ .Values.azureKeyVault.secretKeyPrefix }}-jdbc-mydb-password"
  objectType: secret
{{- end }}
```

#### 2b. Add to SecretObjects Array

Find the `secretObjects` section and add environment variable mappings:

```yaml
# File: templates/secretproviderclass.yaml
# Location: spec.secretObjects[0].data

# Add these lines in the data array (around line 150-200)
# NEW: MyDB Connection Environment Variables
- key: JDBC_MYDB_USERNAME
  objectName: "{{ .Values.azureKeyVault.secretKeyPrefix }}-jdbc-mydb-username"
- key: JDBC_MYDB_PASSWORD
  objectName: "{{ .Values.azureKeyVault.secretKeyPrefix }}-jdbc-mydb-password"
```

**Environment Variable Naming Convention:** `JDBC_{CONNECTION_NAME_UPPERCASE}_USERNAME` and `JDBC_{CONNECTION_NAME_UPPERCASE}_PASSWORD`

---

### Step 3: Add Connection Configuration

Edit `adapters/values-jdbc-adapter-{env}.yaml` to define the connection.

```yaml
# File: adapters/values-jdbc-adapter-dev.yaml

jdbcAdapter:
  enabled: true
  connections:
    # Existing connections...
    - name: "mssql_db_connection"
      # ... existing config ...

    # NEW CONNECTION: MyDB
    - name: "mydb_connection"
      description: "My Database Connection for XYZ Integration"

      # Package Configuration
      # These must match an existing IS package and folder
      packageName: "MyPackage"
      folderName: "MyPackage"

      # Database Connection Details
      serverName: "mydb-server.database.windows.net"
      databaseName: "mydatabase"
      portNumber: 1433
      networkProtocol: "tcp"

      # Credentials from Key Vault (via environment variables)
      user: "$env{JDBC_MYDB_USERNAME}"
      password: "$env{JDBC_MYDB_PASSWORD}"

      # Driver Configuration
      datasourceClass: "com.microsoft.sqlserver.jdbc.SQLServerDataSource"
      otherProperties: "encrypt=true;trustServerCertificate=true;loginTimeout=30"

      # Connection Pool Settings
      minPoolSize: 1
      maxPoolSize: 10
      poolIncrementSize: 1
      blockTimeout: 1000
      expireTimeout: 60000
      startupRetryCount: 3
      startupBackoffSecs: 10
```

---

### Step 4: Deploy Changes

```bash
# Navigate to helm chart directory
cd msr-helm

# Upgrade the release with all value files
helm upgrade wm-msr . -n webmethods \
  -f values.yaml \
  -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml \
  -f adapters/values-sap-adapter-dev.yaml

# Wait for rollout
kubectl rollout status statefulset/wm-msr -n webmethods

# Verify the new connection in ConfigMap
kubectl get configmap wm-msr-config -n webmethods -o yaml | grep -A10 "mydb_connection"
```

---

### Step 5: Verify Deployment

```bash
# Check pod logs for connection initialization
kubectl logs -n webmethods wm-msr-0 | grep -i "mydb\|jdbc"

# Verify environment variables are set
kubectl exec -n webmethods wm-msr-0 -- printenv | grep JDBC_MYDB

# Check MSR Admin Console (port-forward)
kubectl port-forward -n webmethods svc/wm-msr 5555:5555
# Open: http://localhost:5555 -> Adapters -> JDBC Adapter -> Connections
```

---

## File Reference

### Files to Modify

| File | Changes Required |
|------|------------------|
| `templates/secretproviderclass.yaml` | Add secret objects and environment variable mappings |
| `adapters/values-jdbc-adapter-dev.yaml` | Add connection configuration |
| `adapters/values-jdbc-adapter-qa.yaml` | Add connection for QA (if applicable) |
| `adapters/values-jdbc-adapter-prod.yaml` | Add connection for Prod (if applicable) |

### Generated Kubernetes Resources

| Resource | Contains |
|----------|----------|
| `SecretProviderClass/wm-msr-keyvault-sync` | Key Vault secret fetch configuration |
| `Secret/wm-msr-jdbc-secrets` | Environment variables from Key Vault |
| `ConfigMap/wm-msr-config` | artConnection properties for JDBC Adapter |

---

## Examples

### Example 1: SQL Server Connection

```yaml
- name: "sqlserver_orders_db"
  description: "Orders Database - SQL Server"
  packageName: "OrdersPackage"
  folderName: "OrdersPackage"
  serverName: "orders-sql.database.windows.net"
  databaseName: "orders"
  portNumber: 1433
  networkProtocol: "tcp"
  user: "$env{JDBC_ORDERS_USERNAME}"
  password: "$env{JDBC_ORDERS_PASSWORD}"
  datasourceClass: "com.microsoft.sqlserver.jdbc.SQLServerDataSource"
  otherProperties: "encrypt=true;trustServerCertificate=false"
  minPoolSize: 2
  maxPoolSize: 20
  poolIncrementSize: 2
  blockTimeout: 5000
  expireTimeout: 300000
  startupRetryCount: 5
  startupBackoffSecs: 15
```

### Example 2: PostgreSQL Connection

```yaml
- name: "postgres_analytics_db"
  description: "Analytics Database - PostgreSQL"
  packageName: "AnalyticsPackage"
  folderName: "AnalyticsPackage"
  serverName: "analytics-postgres.postgres.database.azure.com"
  databaseName: "analytics"
  portNumber: 5432
  networkProtocol: "tcp"
  user: "$env{JDBC_ANALYTICS_USERNAME}"
  password: "$env{JDBC_ANALYTICS_PASSWORD}"
  datasourceClass: "org.postgresql.ds.PGSimpleDataSource"
  otherProperties: "ssl=true;sslmode=require"
  minPoolSize: 1
  maxPoolSize: 15
  poolIncrementSize: 1
  blockTimeout: 3000
  expireTimeout: 120000
  startupRetryCount: 3
  startupBackoffSecs: 10
```

### Example 3: Oracle Connection

```yaml
- name: "oracle_erp_db"
  description: "ERP Database - Oracle"
  packageName: "ERPPackage"
  folderName: "ERPPackage"
  serverName: "erp-oracle.company.com"
  databaseName: "ERPDB"
  portNumber: 1521
  networkProtocol: "tcp"
  user: "$env{JDBC_ERP_USERNAME}"
  password: "$env{JDBC_ERP_PASSWORD}"
  datasourceClass: "oracle.jdbc.pool.OracleDataSource"
  otherProperties: "oracle.net.CONNECT_TIMEOUT=10000"
  minPoolSize: 2
  maxPoolSize: 25
  poolIncrementSize: 2
  blockTimeout: 10000
  expireTimeout: 600000
  startupRetryCount: 3
  startupBackoffSecs: 20
```

---

## Troubleshooting

### Connection Not Appearing in MSR Admin Console

**Symptom:** Connection doesn't show up in Adapters -> JDBC Adapter -> Connections

**Solutions:**
1. Verify the package exists in the MSR image:
   ```bash
   kubectl exec -n webmethods wm-msr-0 -- ls /opt/softwareag/IntegrationServer/packages/
   ```
2. Check ConfigMap has the artConnection properties:
   ```bash
   kubectl get configmap wm-msr-config -n webmethods -o yaml | grep "artConnection.*mydb"
   ```
3. Restart the pod to reload configuration:
   ```bash
   kubectl delete pod wm-msr-0 -n webmethods
   ```

### Key Vault Secret Not Found

**Symptom:** Pod fails to start with "secret not found" error

**Solutions:**
1. Verify secret exists in Key Vault:
   ```bash
   az keyvault secret show --vault-name wM-kv --name "dev-jdbc-mydb-username"
   ```
2. Check secret naming matches exactly (case-sensitive)
3. Verify managed identity has Key Vault access:
   ```bash
   az keyvault show --name wM-kv --query "properties.accessPolicies"
   ```

### Environment Variable Not Set

**Symptom:** Connection fails with authentication error, `$env{}` not resolved

**Solutions:**
1. Verify environment variable is in the secret:
   ```bash
   kubectl get secret wm-msr-jdbc-secrets -n webmethods -o yaml
   ```
2. Check SecretProviderClass has the mapping:
   ```bash
   kubectl get secretproviderclass wm-msr-keyvault-sync -n webmethods -o yaml | grep "JDBC_MYDB"
   ```
3. Verify pod has the secret volume mounted:
   ```bash
   kubectl describe pod wm-msr-0 -n webmethods | grep -A5 "keyvault-store"
   ```

### Database Connection Refused

**Symptom:** Connection pool fails to initialize, "connection refused" in logs

**Solutions:**
1. Verify database is accessible from AKS:
   ```bash
   kubectl exec -n webmethods wm-msr-0 -- nc -zv mydb-server.database.windows.net 1433
   ```
2. Check Azure SQL firewall allows AKS subnet
3. Verify database name and port are correct

---

## Quick Checklist

Use this checklist when adding a new JDBC connection:

- [ ] Create secrets in Azure Key Vault with correct naming convention
- [ ] Add secret objects to `templates/secretproviderclass.yaml`
- [ ] Add environment variable mappings to `templates/secretproviderclass.yaml`
- [ ] Add connection configuration to `adapters/values-jdbc-adapter-{env}.yaml`
- [ ] Deploy with `helm upgrade`
- [ ] Verify connection appears in MSR Admin Console
- [ ] Test connection from MSR

---

*Document Version: 1.1*
*Last Updated: January 2026*
