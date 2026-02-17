# Adding New JDBC Adapter Connections

This guide explains how to add new JDBC Adapter connections to the MSR Helm chart with Azure Key Vault integration.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step-by-Step Guide](#step-by-step-guide)
4. [Adding SAP Adapter Connections](#adding-sap-adapter-connections)
5. [Adding JDBC Pool Connections](#adding-jdbc-pool-connections)
6. [Examples](#examples)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The Helm chart uses a simplified approach for credential management:

| Data Type | Storage Location | Example |
|-----------|------------------|---------|
| **Password** | Azure Key Vault | `dev-jdbcadapter-mssql-password` |
| **Username** | Values file | `username: "wmadmin"` |
| **Server/URL** | Values file | `serverName: "server.database.windows.net"` |
| **Pool Settings** | Values file | `maxPoolSize: 10` |

### Why This Approach?

- **Security**: Only sensitive data (passwords) in Key Vault
- **Simplicity**: No need to modify template files for new connections
- **Flexibility**: Easy to change non-sensitive config without Key Vault access
- **Auditability**: Clear separation of secrets vs configuration

### Architecture Flow

```
Values File                 Azure Key Vault           Kubernetes
┌─────────────────┐        ┌─────────────────┐       ┌─────────────────┐
│ username        │───────►│                 │       │ ConfigMap       │
│ serverName      │        │ password only   │──────►│ artConnection   │
│ databaseName    │        │                 │       │ properties      │
│ secretName ─────┼───────►│ dev-jdbcadapter-│       │                 │
│ passwordEnvVar  │        │ mssql-password  │       │ $env{PASSWORD}  │
└─────────────────┘        └─────────────────┘       └─────────────────┘
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

### Step 1: Create Password Secret in Azure Key Vault

**Naming Convention:** `{prefix}-jdbcadapter-{connection}-password`

```bash
# Set variables
VAULT_NAME="wM-kv"
PREFIX="dev"  # Use: dev, test, or prod
CONNECTION_NAME="oracle"  # Short name for your connection

# Create password secret
az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name "${PREFIX}-jdbcadapter-${CONNECTION_NAME}-password" \
  --value "YourSecurePassword123!"

# Verify secret was created
az keyvault secret show --vault-name $VAULT_NAME --name "${PREFIX}-jdbcadapter-${CONNECTION_NAME}-password" --query "name"
```

### Step 2: Add Connection to Values File

Edit `adapters/values-jdbc-adapter-dev.yaml`:

```yaml
jdbcAdapter:
  enabled: true
  connections:
    # Existing connections...
    - name: "mssql_db_connection"
      # ... existing config ...

    # NEW CONNECTION
    - name: "oracle_db_connection"
      description: "Oracle Database Connection"
      packageName: "MyPackage"                          # IS Package name
      folderName: "connections"                         # Folder within package
      connectionType: "JDBC Adapter Connection"
      connectionFactoryInterface: "com.wm.adapter.wmjdbc.JDBCConnectionFactory"
      driverAlias: "Oracle Thin Driver"
      dataSourceClass: "oracle.jdbc.pool.OracleDataSource"
      # Connection details (in values file - not sensitive)
      serverName: "oracle-server.example.com"
      databaseName: "ORCL"
      portNumber: 1521
      networkProtocol: "tcp"
      # Credentials
      username: "oracle_user"                           # Username in values file
      secretName: "jdbcadapter-oracle-password"         # Key Vault: dev-jdbcadapter-oracle-password
      passwordEnvVar: "JDBC_ADAPTER_ORACLE_PASSWORD"    # Environment variable name
      otherProperties: ""
      transactionType: "LOCAL_TRANSACTION"
      # Connection pool settings
      minPoolSize: 1
      maxPoolSize: 10
      poolIncrementSize: 1
      blockTimeout: 1000
      expireTimeout: 1000
      startupRetryCount: 0
      startupBackoffSecs: 10
```

### Step 3: Deploy

```bash
helm upgrade --install wm-msr ./msr-helm \
  -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml \
  -f adapters/values-sap-adapter-dev.yaml \
  -n webmethods
```

### Step 4: Force Secret Refresh (if needed)

If the new password doesn't appear in the Kubernetes secret:

```bash
# Delete existing secret to force refresh
kubectl delete secret wm-msr-jdbc-secrets -n webmethods

# Delete pods to recreate with new secret
kubectl delete pods -l app=wm-msr -n webmethods

# Wait for pods to restart
kubectl get pods -n webmethods -l app=wm-msr -w
```

### Step 5: Verify

```bash
# Check secret has new password
kubectl get secret wm-msr-jdbc-secrets -n webmethods -o yaml | grep JDBC_ADAPTER_ORACLE

# Check ConfigMap has connection properties
kubectl get configmap wm-msr-config -n webmethods -o yaml | grep -A5 "oracle_db_connection"

# Verify in MSR Admin Console
kubectl port-forward svc/wm-msr 5555:5555 -n webmethods
# Open: http://localhost:5555 -> Adapters -> JDBC Adapter -> Connections
```

---

## Adding SAP Adapter Connections

### Step 1: Create Password in Key Vault

```bash
az keyvault secret set \
  --vault-name "wM-kv" \
  --name "dev-sapadapter-newconn-password" \
  --value "YourSAPPassword"
```

### Step 2: Add Connection to Values File

Edit `adapters/values-sap-adapter-dev.yaml`:

```yaml
sapAdapter:
  enabled: true
  connections:
    # NEW SAP CONNECTION
    - name: "connNode_NewConnection"
      alias: "NewConnection"
      enabled: true
      # SAP System Configuration
      appServerHost: "sap-server.example.com"
      client: "100"
      systemId: "DEV"
      systemNumber: "00"
      language: "EN"
      loadBalancing: "Off"
      messageServerHost: ""
      logonGroup: ""
      gatewayHost: ""
      gatewayService: ""
      # Authentication
      username: "SAP_USER"                              # Username in values file
      secretName: "sapadapter-newconn-password"         # Key Vault: dev-sapadapter-newconn-password
      passwordEnvVar: "SAP_NEWCONN_PASSWORD"            # Environment variable name
      # SNC Configuration
      sncMode: "No"
      sncMyName: ""
      sncPartnerName: ""
      sncQualityOfService: "Use global build-in default settings"
      # Other settings...
      minPoolSize: 0
      maxPoolSize: 10
```

### Step 3: Deploy and Verify

Same as JDBC Adapter steps 3-5.

---

## Adding JDBC Pool Connections

JDBC Pools are for MSR internal functions (ISInternal, Xref, etc.).

### Step 1: Create Password in Key Vault

```bash
az keyvault secret set \
  --vault-name "wM-kv" \
  --name "dev-jdbcpool-apppool-password" \
  --value "YourPoolPassword"
```

### Step 2: Add Pool to Values File

Edit `values-dev.yaml`:

```yaml
jdbcPool:
  enabled: true
  pools:
    # Existing pool...
    - name: "IS-Pool"
      # ...

    # NEW POOL
    - name: "App-Pool"
      description: "Custom Application JDBC Pool"
      dbURL: "jdbc:wm:sqlserver://app-sql-dev.database.windows.net:1433;databaseName=APP_DEV"
      username: "app_user"                              # Username in values file
      secretName: "jdbcpool-apppool-password"           # Key Vault: dev-jdbcpool-apppool-password
      passwordEnvVar: "JDBC_APP_POOL_PASSWORD"          # Environment variable name
      driverAlias: "DataDirect Connect JDBC SQL Server Driver"
      dataSourceClass: "com.wm.dd.jdbc.sqlserver.SQLServerDataSource"
      minConns: 1
      maxConns: 50
      poolThreshold: 5
      waitingThread: 25
      expireTime: 60000
      useSSL: true

  # Optionally add functional alias
  functionalAliases:
    - name: "AppDB"
      connPoolAlias: "App-Pool"
      failFastMode: true
```

---

## Examples

### SQL Server JDBC Adapter Connection

```yaml
- name: "sqlserver_orders_db"
  description: "Orders Database - SQL Server"
  packageName: "OrdersPackage"
  folderName: "OrdersPackage"
  connectionType: "JDBC Adapter Connection"
  connectionFactoryInterface: "com.wm.adapter.wmjdbc.JDBCConnectionFactory"
  driverAlias: "Microsoft SQL Server Driver"
  dataSourceClass: "com.microsoft.sqlserver.jdbc.SQLServerDataSource"
  serverName: "orders-sql.database.windows.net"
  databaseName: "orders"
  portNumber: 1433
  networkProtocol: "tcp"
  username: "orders_user"
  secretName: "jdbcadapter-orders-password"
  passwordEnvVar: "JDBC_ADAPTER_ORDERS_PASSWORD"
  otherProperties: "encrypt=true;trustServerCertificate=false"
  transactionType: "LOCAL_TRANSACTION"
  minPoolSize: 2
  maxPoolSize: 20
  poolIncrementSize: 2
  blockTimeout: 5000
  expireTimeout: 300000
  startupRetryCount: 5
  startupBackoffSecs: 15
```

### PostgreSQL JDBC Adapter Connection

```yaml
- name: "postgres_analytics_db"
  description: "Analytics Database - PostgreSQL"
  packageName: "AnalyticsPackage"
  folderName: "AnalyticsPackage"
  connectionType: "JDBC Adapter Connection"
  connectionFactoryInterface: "com.wm.adapter.wmjdbc.JDBCConnectionFactory"
  driverAlias: "PostgreSQL Driver"
  dataSourceClass: "org.postgresql.ds.PGSimpleDataSource"
  serverName: "analytics-postgres.postgres.database.azure.com"
  databaseName: "analytics"
  portNumber: 5432
  networkProtocol: "tcp"
  username: "analytics_user"
  secretName: "jdbcadapter-analytics-password"
  passwordEnvVar: "JDBC_ADAPTER_ANALYTICS_PASSWORD"
  otherProperties: "ssl=true;sslmode=require"
  transactionType: "LOCAL_TRANSACTION"
  minPoolSize: 1
  maxPoolSize: 15
  poolIncrementSize: 1
  blockTimeout: 3000
  expireTimeout: 120000
  startupRetryCount: 3
  startupBackoffSecs: 10
```

### Oracle JDBC Adapter Connection

```yaml
- name: "oracle_erp_db"
  description: "ERP Database - Oracle"
  packageName: "ERPPackage"
  folderName: "ERPPackage"
  connectionType: "JDBC Adapter Connection"
  connectionFactoryInterface: "com.wm.adapter.wmjdbc.JDBCConnectionFactory"
  driverAlias: "Oracle Thin Driver"
  dataSourceClass: "oracle.jdbc.pool.OracleDataSource"
  serverName: "erp-oracle.company.com"
  databaseName: "ERPDB"
  portNumber: 1521
  networkProtocol: "tcp"
  username: "erp_user"
  secretName: "jdbcadapter-erp-password"
  passwordEnvVar: "JDBC_ADAPTER_ERP_PASSWORD"
  otherProperties: "oracle.net.CONNECT_TIMEOUT=10000"
  transactionType: "LOCAL_TRANSACTION"
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

**Solutions:**
1. Verify the package exists:
   ```bash
   kubectl exec -n webmethods wm-msr-0 -- ls /opt/softwareag/IntegrationServer/packages/
   ```
2. Check ConfigMap:
   ```bash
   kubectl get configmap wm-msr-config -n webmethods -o yaml | grep "artConnection.*myconnection"
   ```
3. Restart pods:
   ```bash
   kubectl rollout restart statefulset wm-msr -n webmethods
   ```

### Key Vault Secret Not Found

**Solutions:**
1. Verify secret exists:
   ```bash
   az keyvault secret show --vault-name wM-kv --name "dev-jdbcadapter-myconn-password"
   ```
2. Check naming matches exactly (case-sensitive)
3. Verify managed identity has Key Vault access

### Environment Variable Not Set

**Solutions:**
1. Delete secret and pods to force refresh:
   ```bash
   kubectl delete secret wm-msr-jdbc-secrets -n webmethods
   kubectl delete pods -l app=wm-msr -n webmethods
   ```
2. Check secret after pods restart:
   ```bash
   kubectl get secret wm-msr-jdbc-secrets -n webmethods -o yaml
   ```

### Database Connection Refused

**Solutions:**
1. Test connectivity:
   ```bash
   kubectl exec -n webmethods wm-msr-0 -- nc -zv server.database.windows.net 1433
   ```
2. Check Azure SQL/DB firewall allows AKS subnet
3. Verify server name, port, and database name

---

## Quick Checklist

When adding a new connection:

- [ ] Create password secret in Azure Key Vault with correct naming
- [ ] Add connection to appropriate values file (`values-dev.yaml` or `adapters/values-*-dev.yaml`)
- [ ] Set `secretName` to match Key Vault secret (without prefix)
- [ ] Set `passwordEnvVar` to unique environment variable name
- [ ] Deploy with `helm upgrade`
- [ ] Force secret refresh if needed (delete secret + pods)
- [ ] Verify connection in MSR Admin Console
- [ ] Test connection

---

## Naming Convention Reference

| Component | Values File Field | Key Vault Secret | Env Variable |
|-----------|------------------|------------------|--------------|
| JDBC Pool | `secretName: "jdbcpool-ispool-password"` | `dev-jdbcpool-ispool-password` | `JDBC_IS_POOL_PASSWORD` |
| JDBC Adapter | `secretName: "jdbcadapter-mssql-password"` | `dev-jdbcadapter-mssql-password` | `JDBC_ADAPTER_MSSQL_PASSWORD` |
| SAP Adapter | `secretName: "sapadapter-rfcagency-password"` | `dev-sapadapter-rfcagency-password` | `SAP_RFCAGENCY_PASSWORD` |

---

*Document Version: 2.0*
*Last Updated: January 2026*
