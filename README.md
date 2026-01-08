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

- **Keystore Management** - Azure Key Vault certificate integration
- **Truststore Management** - Multi-certificate truststore from Key Vault
- **TLS/SSL Support** - HTTPS endpoints with custom certificates
- **File Access Control** - Configurable read/write/delete paths for pub.file services
- **Pod Security** - Non-root containers and security contexts

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

```bash
# Set environment prefix (dev, test, or prod)
PREFIX="dev"
VAULT="your-keyvault-name"

# Create required secrets
az keyvault secret set --vault-name $VAULT --name "${PREFIX}-jdbc-pool-url" \
  --value "jdbc:sqlserver://server:1433;database=msrdb"
az keyvault secret set --vault-name $VAULT --name "${PREFIX}-jdbc-pool-username" \
  --value "sqladmin"
az keyvault secret set --vault-name $VAULT --name "${PREFIX}-jdbc-pool-password" \
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
| `replicaCount` | Number of MSR replicas | `2` |
| `image.repository` | Container image repository | `abiwebmethods.azurecr.io/webmethods-microservicesruntime` |
| `image.tag` | MSR version tag | `11.1.0.6-postgresql-v2` |
| `azureKeyVault.enabled` | Enable Azure Key Vault integration | `false` |
| `azureKeyVault.secretKeyPrefix` | Environment prefix for secrets | `dev` |
| `jdbcPool.enabled` | Enable MSR internal JDBC pool | `false` |
| `jdbcAdapter.enabled` | Enable JDBC adapter connections | `false` |
| `sapAdapter.enabled` | Enable SAP adapter connections/listeners | `false` |
| `um.enabled` | Enable Universal Messaging | `false` |
| `terracotta.enabled` | Enable Terracotta caching | `false` |
| `fileAccessControl.enabled` | Enable file access control for pub.file | `false` |
| `packageConfigs.enabled` | Enable package-specific app.properties | `false` |

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
| `adapters/values-jdbc-adapter-prod.yaml` | JDBC Adapter connections (prod) |
| `adapters/values-sap-adapter-dev.yaml` | SAP connections & listeners (dev) |
| `adapters/values-sap-adapter-prod.yaml` | SAP connections & listeners (prod) |

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

All secrets use environment-specific prefixes:

| Environment | Prefix | Example |
|-------------|--------|---------|
| Development | `dev-` | `dev-jdbc-pool-password` |
| QA/Test | `test-` | `test-jdbc-pool-password` |
| Production | `prod-` | `prod-jdbc-pool-password` |

### Required Secrets

| Secret Name | Description |
|-------------|-------------|
| `{prefix}-jdbc-pool-url` | JDBC Pool connection URL |
| `{prefix}-jdbc-pool-username` | JDBC Pool username |
| `{prefix}-jdbc-pool-password` | JDBC Pool password |
| `{prefix}-jdbc-adapter-url` | JDBC Adapter connection URL |
| `{prefix}-jdbc-adapter-username` | JDBC Adapter username |
| `{prefix}-jdbc-adapter-password` | JDBC Adapter password |
| `{prefix}-sap-*-user` | SAP connection username (per connection) |
| `{prefix}-sap-*-password` | SAP connection password (per connection) |
| `{prefix}-keystore-password` | Keystore password |
| `{prefix}-keyalias-password` | Key alias password |
| `{prefix}-truststore-password` | Truststore password |
| `{prefix}-um-password` | Universal Messaging password |

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

### Current Version: 2.3.0 (January 2026)

- **File Access Control** - Configurable read/write/delete paths for WmPublic pub.file services
- **Package Configurations** - Environment-specific app.properties per custom package
- **SAP SNC Support** - Enhanced SAP Adapter with Secure Network Communication

### Previous Versions

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
*Last Updated: January 2026*
