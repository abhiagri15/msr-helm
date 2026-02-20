# webMethods MSR Helm Chart

[![Helm Version](https://img.shields.io/badge/Helm-3.12+-blue.svg)](https://helm.sh)
[![Kubernetes Version](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io)
[![MSR Version](https://img.shields.io/badge/MSR-11.1.0.6-green.svg)](https://www.softwareag.com)

Enterprise-grade Helm chart for deploying **webMethods Microservices Runtime (MSR)** on Azure Kubernetes Service (AKS) with comprehensive Azure Key Vault integration, high availability, and production-ready configurations.

---

## Documentation

| Document | Description |
|----------|-------------|
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | System architecture, deployment topologies, security design, and integration patterns |
| **[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)** | Step-by-step deployment guides, Azure setup, troubleshooting, and upgrade procedures |
| **[docs/ADDING-JDBC-CONNECTIONS.md](docs/ADDING-JDBC-CONNECTIONS.md)** | Guide for adding new JDBC Adapter connections with Azure Key Vault |
| **README.md** (this file) | Quick start guide and feature overview |

---

## Features

### Core Capabilities

- **StatefulSet Deployment** - Stable network identities and persistent storage
- **High Availability** - Multi-replica support with pod anti-affinity rules
- **Auto-scaling** - Horizontal Pod Autoscaler (HPA) based on CPU/memory metrics
- **Rolling Updates** - Zero-downtime deployments with configurable update strategy

### Azure Integration

- **Azure Key Vault** - Centralized secret management with CSI driver
- **Environment-Specific Secrets** - Prefix-based secret naming (`dev-`, `test-`, `prod-`)
- **Azure Container Registry** - Private container image storage
- **Azure SQL Database** - Managed database backend support

### webMethods Integration

- **Universal Messaging (UM)** - JMS messaging and event-driven architecture
- **Terracotta Cache** - Distributed session clustering for HA
- **JDBC Pool** - MSR internal database connections (ISInternal, Xref)
- **JDBC Adapter** - Package-level database connections
- **SAP Adapter** - RFC/BAPI connections and listeners with SNC support

### Security

- **Pod Security Hardening** - Non-root enforcement (sagadmin UID=1724), dropped Linux capabilities, privilege escalation prevention per IBM/SoftwareAG best practices
- **Configurable Security Context** - Pod and container-level securityContext configurable via values.yaml
- **Keystore Management** - Azure Key Vault certificate integration
- **Truststore Management** - Multi-certificate truststore from Key Vault
- **TLS/SSL Support** - HTTPS endpoints with custom certificates
- **File Access Control** - Configurable read/write/delete paths for pub.file services
- **Read-Only Volume Mounts** - All ConfigMap/Secret mounts explicitly set to read-only
- **Init Container Hardening** - Root init container runs with minimal capabilities (CHOWN, DAC_OVERRIDE only)

### JMS/JNDI (Universal Messaging)

- **JMS Configuration** - Environment-specific `jms.cnf` mounted at `/opt/softwareag/IntegrationServer/config/jms.cnf`
- **JNDI Properties** - Environment-specific `jndi_JNDI.properties` mounted at `/opt/softwareag/IntegrationServer/config/jndi/jndi_JNDI.properties`
- **Toggle per Environment** - Controlled via `jmsConfig.enabled` in values files

### License Management

- **IS License** - Environment-specific `licenseKey.xml` mounted via ConfigMap when `license.enabled: true`
- **Terracotta Client License** - `terracotta-license.key` auto-mounted when `terracotta.enabled: true` with JVM property `-Dcom.tc.productkey.path`
- **Toggle per Environment** - Licenses disabled by default; enable only after placing real license files

### Caching

- **Public Cache Managers** - Auto-discovered Ehcache XML configs from `files/{environment}/config/caching/`
- **Auto-Start on Boot** - Cache managers automatically started when MSR pods come up via DSP admin endpoint
- **Terracotta Integration** - Distributed caching with Terracotta BigMemory

---

## Quick Start

### Prerequisites

- Azure subscription with AKS cluster
- Azure Key Vault with CSI driver enabled
- Helm 3.12+ and kubectl configured
- Container image in accessible registry

### 1. Create Namespace

```bash
kubectl create namespace webmethods
```

### 2. Configure Azure Key Vault Secrets

Only passwords are stored in Key Vault. URLs and usernames are configured in values files.

```bash
# Set environment prefix (dev, test, or prod)
PREFIX="dev"
VAULT="wM-kv"

# Create password secrets (only passwords, not URLs or usernames)
az keyvault secret set --vault-name $VAULT --name "${PREFIX}-jdbcpool-ispool-password" \
  --value "YourSecurePassword"
az keyvault secret set --vault-name $VAULT --name "${PREFIX}-jdbcadapter-mssql-password" \
  --value "YourSecurePassword"
az keyvault secret set --vault-name $VAULT --name "${PREFIX}-sapadapter-rfcagency-password" \
  --value "YourSecurePassword"
```

### 3. Update values-dev.yaml

```yaml
azureKeyVault:
  enabled: true
  vaultName: "your-keyvault-name"
  tenantId: "your-tenant-id"
  clientId: "kubelet-identity-client-id"
  secretKeyPrefix: "dev"
```

### 4. Deploy MSR

```bash
# Deploy with all adapters (JDBC + SAP)
helm upgrade --install wm-msr . \
  --namespace webmethods \
  --values values.yaml \
  --values values-dev.yaml \
  --values adapters/values-jdbc-adapter-dev.yaml \
  --values adapters/values-sap-adapter-dev.yaml \
  --timeout 15m

# Or deploy without SAP adapter
helm upgrade --install wm-msr . \
  --namespace webmethods \
  --values values.yaml \
  --values values-dev.yaml \
  --values adapters/values-jdbc-adapter-dev.yaml \
  --timeout 15m
```

### 5. Verify Deployment

```bash
# Check pod status
kubectl get pods -n webmethods -w

# Access MSR Admin Console
kubectl port-forward svc/wm-msr 5555:5555 -n webmethods
# Open: http://localhost:5555 (Administrator/manage)
```

---

## Configuration Overview

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `environment` | Environment identifier (`dev`, `qa`, `prod`) — drives file selection from `files/{environment}/` | `""` |
| `replicaCount` | Number of MSR replicas | `2` |
| `image.repository` | Container image repository | `abiwebmethods.azurecr.io/webmethods-microservicesruntime` |
| `image.tag` | MSR version tag | `11.1.0.6-postgresql-v2` |
| `azureKeyVault.enabled` | Enable Azure Key Vault integration | `false` |
| `azureKeyVault.secretKeyPrefix` | Environment prefix for secrets | `dev` |
| `jdbcPool.enabled` | Enable MSR internal JDBC pool | `false` |
| `jdbcAdapter.enabled` | Enable JDBC adapter connections | `false` |
| `sapAdapter.enabled` | Enable SAP adapter connections/listeners | `false` |
| `sapAdapter.snc.externalCredentials` | Mount SNC cred_v2/PSE from K8s Secret (for QA/Prod) | `false` |
| `license.enabled` | Enable IS license mounting from `files/{env}/license/licenseKey.xml` | `false` |
| `jmsConfig.enabled` | Enable JMS/JNDI configuration for UM connectivity | `false` |
| `um.enabled` | Enable Universal Messaging | `false` |
| `terracotta.enabled` | Enable Terracotta caching | `false` |
| `caching.publicCacheManagers.enabled` | Enable public Ehcache cache managers | `false` |
| `webMethodsCloud.enabled` | Enable webMethods Cloud / Integration Live connectivity | `false` |
| `fileAccessControl.enabled` | Enable file access control for pub.file | `false` |
| `packageConfigs.enabled` | Enable package-specific app.properties | `false` |
| `securityContext.pod.runAsUser` | Pod-level run-as user (sagadmin) | `1724` |
| `securityContext.pod.runAsNonRoot` | Enforce non-root containers | `true` |
| `securityContext.container.allowPrivilegeEscalation` | Prevent privilege escalation | `false` |

### Environment Files

| File | Purpose |
|------|---------|
| `values.yaml` | Base configuration and defaults |
| `values-dev.yaml` | Development environment overrides (core MSR config) |
| `values-qa.yaml` | QA/Test environment overrides |
| `values-prod.yaml` | Production environment overrides |

### Adapter Configuration Files

Adapter configurations are separated into dedicated files for better maintainability:

| File | Purpose |
|------|---------|
| `adapters/values-jdbc-adapter-dev.yaml` | JDBC Adapter connections (dev) |
| `adapters/values-jdbc-adapter-qa.yaml` | JDBC Adapter connections (QA) |
| `adapters/values-jdbc-adapter-prod.yaml` | JDBC Adapter connections (prod) |
| `adapters/values-sap-adapter-dev.yaml` | SAP connections & listeners (dev) |
| `adapters/values-sap-adapter-qa.yaml` | SAP connections & listeners (QA) - SNC external credentials |
| `adapters/values-sap-adapter-prod.yaml` | SAP connections & listeners (prod) - SNC external credentials |

### Files Directory Structure

The `files/` directory contains **environment-specific** configuration files mounted into the MSR container. The `environment` value (`dev`, `qa`, `prod`) drives which directory is used:

```
files/
├── dev/
│   ├── config/
│   │   ├── aclmap_sm.cnf                   # ACL map configuration
│   │   ├── jms.cnf                         # JMS connection aliases (UM)
│   │   ├── jndi/
│   │   │   └── jndi_JNDI.properties        # JNDI provider configuration
│   │   └── caching/                        # Public Cache Manager XML configs
│   │       ├── OrderCache.xml
│   │       ├── SessionCache.xml
│   │       └── LookupCache.xml
│   ├── license/                            # License files (placeholders until real licenses)
│   │   ├── licenseKey.xml                  # IS/MSR license key
│   │   └── terracotta-license.key          # Terracotta BigMemory client license
│   └── integrationlive/                    # webMethods Cloud config
│       ├── accounts.cnf
│       ├── connections.cnf
│       └── applications/                   # 45+ application config files
│           └── *.cnf
├── qa/                                     # Same structure as dev (QA-specific)
└── prod/                                   # Same structure as dev (Prod-specific)
```

| File/Directory | Purpose | Mount Path |
|----------------|---------|------------|
| `files/{env}/config/aclmap_sm.cnf` | ACL map configuration | `.../instances/default/config/aclmap_sm.cnf` |
| `files/{env}/config/jms.cnf` | JMS connection aliases | `.../config/jms.cnf` |
| `files/{env}/config/jndi/jndi_JNDI.properties` | JNDI provider config | `.../config/jndi/jndi_JNDI.properties` |
| `files/{env}/config/caching/*.xml` | Public Cache Manager Ehcache XMLs | `.../config/Caching/` (copied by postStart) |
| `files/{env}/integrationlive/` | webMethods Cloud configuration | `.../config/integrationlive/` |

---

## webMethods Cloud Configuration

To enable webMethods Cloud (Integration Cloud) connectivity:

### 1. Copy Configuration Files

Copy your existing `accounts.cnf`, `connections.cnf`, and application files from an existing MSR:

```bash
# From source MSR
scp -r /opt/softwareag/IntegrationServer/instances/default/packages/WmCloud/config/integrationlive/* \
  msr-helm/files/integrationlive/
```

### 2. Add Cloud Passwords to Key Vault

```bash
az keyvault secret set --vault-name "wM-kv" \
  --name "dev-wmcloud-dev-io-password" \
  --value "YourCloudPassword"
```

### 3. Configure in values-dev.yaml

```yaml
webMethodsCloud:
  enabled: true
  cloudPasswords:
    - alias: "Dev io"                           # Must match alias in accounts.cnf
      secretName: "wmcloud-dev-io-password"     # Key Vault: dev-wmcloud-dev-io-password
      envVar: "WMCLOUD_DEV_IO_PASSWORD"         # Environment variable name
```

### 4. Update accounts.cnf

In `files/{environment}/integrationlive/accounts.cnf`, set the password to use environment variable:

```properties
accounts.Dev\ io.password=$env{WMCLOUD_DEV_IO_PASSWORD}
```

---

## Deployment Topologies

### Minimal (Development)

```bash
helm upgrade --install wm-msr . -n webmethods \
  --set replicaCount=1 \
  --set persistence.enabled=false \
  --set jdbcPool.enabled=false \
  --set um.enabled=false \
  --set terracotta.enabled=false
```

### Standard (QA/Test)

```bash
helm upgrade --install wm-msr . -n webmethods \
  -f values.yaml -f values-qa.yaml \
  -f adapters/values-jdbc-adapter-qa.yaml \
  -f adapters/values-sap-adapter-qa.yaml
```

### Enterprise (Production)

```bash
helm upgrade --install wm-msr . -n webmethods \
  -f values.yaml -f values-prod.yaml \
  -f adapters/values-jdbc-adapter-prod.yaml \
  -f adapters/values-sap-adapter-prod.yaml
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#deployment-topologies) for detailed topology diagrams.

---

## Azure Key Vault Secret Naming

All secrets use environment-specific prefixes with friendly naming conventions:

| Environment | Prefix | Example |
|-------------|--------|---------|
| Development | `dev-` | `dev-jdbcpool-ispool-password` |
| QA/Test | `test-` | `test-jdbcpool-ispool-password` |
| Production | `prod-` | `prod-jdbcpool-ispool-password` |

### Configuration Approach

**Only passwords are stored in Azure Key Vault.** Non-sensitive configuration (URLs, usernames, server names) are stored directly in values files:

| Data Type | Storage Location |
|-----------|------------------|
| Database URL | Values file (`values-dev.yaml`) |
| Username | Values file (`values-dev.yaml` or adapter files) |
| Password | Azure Key Vault |
| Server/Port | Values file (adapter files) |

### Secret Naming Convention

| Component | Secret Pattern | Example |
|-----------|---------------|---------|
| JDBC Pool | `{prefix}-jdbcpool-{poolname}-password` | `dev-jdbcpool-ispool-password` |
| JDBC Adapter | `{prefix}-jdbcadapter-{connection}-password` | `dev-jdbcadapter-mssql-password` |
| SAP Adapter | `{prefix}-sapadapter-{alias}-password` | `dev-sapadapter-rfcagency-password` |
| Keystore | `{prefix}-keystore-password` | `dev-keystore-password` |
| Key Alias | `{prefix}-keyalias-password` | `dev-keyalias-password` |
| Truststore | `{prefix}-truststore-password` | `dev-truststore-password` |
| UM Connection | `{prefix}-um-{alias}-password` | `dev-um-business-password` |
| SAP SNC cred_v2 | `{prefix}-sap-snc-credv2` | `qa-sap-snc-credv2` (base64 encoded) |
| SAP SNC PSE | `{prefix}-sap-snc-pse` | `qa-sap-snc-pse` (base64 encoded) |
| webMethods Cloud | `{prefix}-wmcloud-{account}-password` | `dev-wmcloud-dev-io-password` |

---

## Common Operations

### Scale Deployment

```bash
kubectl scale statefulset wm-msr --replicas=3 -n webmethods
```

### View Logs

```bash
kubectl logs -f wm-msr-0 -n webmethods
```

### Restart Pods (Rolling)

```bash
kubectl rollout restart statefulset/wm-msr -n webmethods
```

### Upgrade Helm Release

```bash
helm upgrade wm-msr . -n webmethods \
  -f values.yaml -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml \
  -f adapters/values-sap-adapter-dev.yaml \
  --set image.tag="11.1.0.7"
```

### Rollback

```bash
helm rollback wm-msr -n webmethods
```

### Uninstall

```bash
helm uninstall wm-msr -n webmethods
kubectl delete pvc -l app.kubernetes.io/name=webmethods-msr -n webmethods
```

---

## Troubleshooting Quick Reference

| Issue | Command |
|-------|---------|
| Pod stuck in Pending | `kubectl describe pod wm-msr-0 -n webmethods` |
| Check events | `kubectl get events -n webmethods --sort-by='.lastTimestamp'` |
| View MSR logs | `kubectl logs wm-msr-0 -n webmethods` |
| Check secrets | `kubectl get secrets -n webmethods` |
| Test DB connectivity | `kubectl exec -it wm-msr-0 -n webmethods -- nc -zv dbserver 1433` |

For detailed troubleshooting, see [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md#troubleshooting).

---

## Architecture Highlights

```
                    ┌─────────────────────────────────────────┐
                    │          Azure Cloud Platform           │
                    └─────────────────────────────────────────┘
                                        │
           ┌────────────────────────────┼────────────────────────────┐
           │                            │                            │
    ┌──────▼──────┐            ┌───────▼───────┐           ┌───────▼───────┐
    │ Azure Key   │            │     AKS       │           │   Azure SQL   │
    │   Vault     │◄──────────►│   Cluster     │◄─────────►│   Database    │
    │             │  Secrets   │               │   JDBC    │               │
    └─────────────┘            └───────┬───────┘           └───────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
             ┌──────▼──────┐                      ┌──────▼──────┐
             │   wm-msr-0  │◄────Terracotta──────►│   wm-msr-1  │
             │    (MSR)    │                      │    (MSR)    │
             └──────┬──────┘                      └──────┬──────┘
                    │                                    │
                    └────────────────┬───────────────────┘
                                     │
                              ┌──────▼──────┐
                              │  Universal  │
                              │  Messaging  │
                              └─────────────┘
```

For complete architecture diagrams, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Version History

### Current Version: 2.7.0 (February 2026)

- **IS License Management** - Environment-specific `licenseKey.xml` mounted via ConfigMap when `license.enabled: true`
- **Terracotta Client License** - `terracotta-license.key` auto-mounted when `terracotta.enabled: true` with JVM property `-Dcom.tc.productkey.path`
- **Dynamic JAVA_CUSTOM_OPTS** - Refactored from single conditional to multi-source list combining JCo trace, Terracotta license, and future JVM properties
- **License Safety Toggle** - All licenses disabled by default (`license.enabled: false`); enable only after replacing placeholder files with real licenses

### 2.6.0 (February 2026)

- **Environment-Specific Files** - All static files (aclmap, caching XMLs, integrationlive) moved to `files/{environment}/` directories (`dev`, `qa`, `prod`)
- **JMS/JNDI Configuration** - `jms.cnf` and `jndi_JNDI.properties` mounted via ConfigMap when `jmsConfig.enabled: true` for UM connectivity
- **Environment Parameter** - New `environment` value drives which `files/{environment}/` directory is used at deploy time

### 2.5.0 (February 2026)

- **QA Adapter Configurations** - Added `values-jdbc-adapter-qa.yaml` and `values-sap-adapter-qa.yaml` for QA environment
- **SAP SNC External Credentials** - QA/Prod use K8s Secret volume mount to overlay per-environment cred_v2 and PSE files (`sapAdapter.snc.externalCredentials`)
- **Multi-Environment Pipeline Support** - Adapter files structured for pipeline-driven Dev → QA → Prod promotion with layered Helm values

### 2.4.0 (February 2026)

- **Container Security Hardening** - Pod/container securityContext with sagadmin (UID=1724) enforcement, dropped capabilities, privilege escalation prevention per IBM/SoftwareAG best practices
- **Read-Only Volume Mounts** - All ConfigMap/Secret mounts explicitly set `readOnly: true`
- **Public Cache Managers** - Auto-discovered Ehcache XML configs from `files/{environment}/config/caching/` with auto-start on pod boot
- **Init Container Hardening** - Root init container restricted to CHOWN and DAC_OVERRIDE capabilities only
- **Configurable Security Context** - Full `securityContext.pod` and `securityContext.container` blocks configurable per environment via values files

### Previous Versions

- **2.3.0** - File access control, package configurations, SAP SNC support
- **2.2.0** - Adapter separation (JDBC and SAP configs moved to `adapters/` folder)
- **2.1.0** - Azure Key Vault enhancement, environment-specific secret prefixes
- **2.0.0** - Azure Key Vault CSI driver integration, truststore certificate support
- **1.0.0** - Initial release with StatefulSet and basic integrations

---

## Support

For issues and questions:

1. Review [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md#troubleshooting) for common solutions
2. Check MSR logs: `kubectl logs wm-msr-0 -n webmethods`
3. Verify Azure Key Vault access and secret names
4. Ensure CSI driver is installed: `kubectl get pods -n kube-system -l app=secrets-store-csi-driver`

---

## License

This Helm chart is provided for use with licensed webMethods products from Software AG.

---

*Maintained by: webMethods Architecture Team*
*Chart Version: 2.7.0*
*Last Updated: February 2026*
