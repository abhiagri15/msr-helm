# webMethods MSR Helm Chart - Architecture Guide

## Document Information

| Attribute | Value |
|-----------|-------|
| Version | 2.7.0 |
| Last Updated | February 2026 |
| Author | webMethods Platform Team |
| Classification | Internal |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Component Architecture](#3-component-architecture)
4. [Deployment Topologies](#4-deployment-topologies)
5. [Security Architecture](#5-security-architecture)
6. [Integration Patterns](#6-integration-patterns)
7. [Networking Architecture](#7-networking-architecture)
8. [Storage Architecture](#8-storage-architecture)
9. [High Availability & Disaster Recovery](#9-high-availability--disaster-recovery)
10. [Scaling Architecture](#10-scaling-architecture)
11. [Monitoring & Observability](#11-monitoring--observability)
12. [Environment Strategy](#12-environment-strategy)

---

## 1. Executive Summary

This document describes the reference architecture for deploying Software AG webMethods Microservices Runtime (MSR) on Azure Kubernetes Service (AKS) using Helm charts. The architecture is designed for enterprise-grade deployments with emphasis on:

- **Security**: Zero-trust security model with Azure Key Vault integration
- **Scalability**: Horizontal Pod Autoscaling with Terracotta distributed caching
- **Reliability**: Multi-replica StatefulSet deployment with pod anti-affinity
- **Maintainability**: GitOps-ready Helm chart with environment-specific configurations

### Key Design Principles

| Principle | Implementation |
|-----------|----------------|
| Infrastructure as Code | Helm charts with declarative YAML configurations |
| Secrets Management | Azure Key Vault with CSI driver - no secrets in code |
| Immutable Infrastructure | Container-based deployment with versioned images |
| Horizontal Scaling | StatefulSet with HPA and Terracotta session clustering |
| Environment Parity | Single chart with environment-specific values files |

---

## 2. Architecture Overview

### 2.1 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              AZURE CLOUD                                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                     AZURE KUBERNETES SERVICE (AKS)                       │    │
│  │                                                                          │    │
│  │   ┌─────────────────────────────────────────────────────────────────┐   │    │
│  │   │                    NAMESPACE: webmethods                         │   │    │
│  │   │                                                                  │   │    │
│  │   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │    │
│  │   │  │   MSR-0      │  │   MSR-1      │  │   MSR-N      │          │   │    │
│  │   │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │          │   │    │
│  │   │  │ │   MSR    │ │  │ │   MSR    │ │  │ │   MSR    │ │          │   │    │
│  │   │  │ │ 11.1.0.6 │ │  │ │ 11.1.0.6 │ │  │ │ 11.1.0.6 │ │          │   │    │
│  │   │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │          │   │    │
│  │   │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │          │   │    │
│  │   │  │ │   PVC    │ │  │ │   PVC    │ │  │ │   PVC    │ │          │   │    │
│  │   │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │          │   │    │
│  │   │  └──────────────┘  └──────────────┘  └──────────────┘          │   │    │
│  │   │           │                │                │                   │   │    │
│  │   │           └────────────────┼────────────────┘                   │   │    │
│  │   │                            │                                    │   │    │
│  │   │                    ┌───────▼───────┐                           │   │    │
│  │   │                    │  MSR Service  │                           │   │    │
│  │   │                    │  (ClusterIP)  │                           │   │    │
│  │   │                    │  5555/5543    │                           │   │    │
│  │   │                    └───────────────┘                           │   │    │
│  │   │                                                                  │   │    │
│  │   │  ┌──────────────────────────────────────────────────────────┐  │   │    │
│  │   │  │              SUPPORTING SERVICES                          │  │   │    │
│  │   │  │                                                           │  │   │    │
│  │   │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │  │   │    │
│  │   │  │  │  UM Cluster │  │ Terracotta  │  │   Azure SQL     │  │  │   │    │
│  │   │  │  │  (3 nodes)  │  │  (2 nodes)  │  │   Database      │  │  │   │    │
│  │   │  │  │   :9000     │  │   :9510     │  │    :1433        │  │  │   │    │
│  │   │  │  └─────────────┘  └─────────────┘  └─────────────────┘  │  │   │    │
│  │   │  └──────────────────────────────────────────────────────────┘  │   │    │
│  │   └─────────────────────────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌──────────────────────┐     ┌──────────────────────┐                         │
│  │   AZURE KEY VAULT    │     │    AZURE CONTAINER   │                         │
│  │       (wM-kv)        │     │     REGISTRY (ACR)   │                         │
│  │                      │     │                      │                         │
│  │  • Certificates      │     │  • MSR Images        │                         │
│  │  • Secrets           │     │  • UM Images         │                         │
│  │  • Passwords         │     │  • Terracotta Images │                         │
│  └──────────────────────┘     └──────────────────────┘                         │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           REQUEST FLOW                                       │
└─────────────────────────────────────────────────────────────────────────────┘

  External Client
        │
        ▼
┌───────────────────┐
│   Azure Load      │ ◄─── Public IP / DNS
│   Balancer        │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  Ingress / API    │ ◄─── TLS Termination (optional)
│    Gateway        │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│   MSR Service     │ ◄─── Load balancing across replicas
│   (ClusterIP)     │
└─────────┬─────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
┌───────┐   ┌───────┐
│ MSR-0 │   │ MSR-1 │ ◄─── Stateless request processing
└───┬───┘   └───┬───┘
    │           │
    └─────┬─────┘
          │
    ┌─────┴─────────────────────────────┐
    │                                   │
    ▼                                   ▼
┌───────────────────┐         ┌───────────────────┐
│   Terracotta      │         │  Universal        │
│   (Session Store) │         │  Messaging        │
└───────────────────┘         └───────────────────┘
          │                             │
          ▼                             ▼
┌───────────────────┐         ┌───────────────────┐
│   Azure SQL       │         │  External         │
│   (IS Internal)   │         │  Systems          │
└───────────────────┘         └───────────────────┘
```

---

## 3. Component Architecture

### 3.1 MSR Pod Architecture

Each MSR pod consists of:

```
┌─────────────────────────────────────────────────────────────────┐
│                         MSR POD                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  INIT CONTAINERS (Sequential Execution)                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 1. copy-keyvault-keystores                               │   │
│  │    • Converts Azure Key Vault certs to PKCS12 keystores  │   │
│  │    • Creates truststore from multiple CA certificates    │   │
│  │    Image: eclipse-temurin:11-jdk                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ 2. wait-for-terracotta (conditional)                     │   │
│  │    • Waits for Terracotta servers to be available        │   │
│  │    Image: busybox                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  MAIN CONTAINER                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ msr                                                       │   │
│  │ Image: webmethods-microservicesruntime:11.1.0.6          │   │
│  │                                                           │   │
│  │ Ports:                                                    │   │
│  │   • 5555  - HTTP API                                      │   │
│  │   • 5543  - HTTPS API                                     │   │
│  │   • 9999  - Diagnostic Port                               │   │
│  │                                                           │   │
│  │ Volume Mounts:                                            │   │
│  │   • /mnt/secrets-store     - Azure Key Vault (CSI)       │   │
│  │   • /opt/.../kv-keystores  - Converted keystores          │   │
│  │   • /opt/.../config        - Application properties       │   │
│  │   • /opt/.../config/jms.cnf - JMS aliases (if enabled)   │   │
│  │   • /opt/.../config/jndi/  - JNDI properties (if enabled)│   │
│  │   • /opt/.../config/licenseKey.xml - IS license (if lic) │   │
│  │   • /opt/.../config/tc-license.key - TC license (if TC)  │   │
│  │   • /var/msr/data          - Persistent data (PVC)       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  VOLUMES                                                         │
│  ┌──────────────────┐ ┌──────────────────┐ ┌────────────────┐  │
│  │ keyvault-store   │ │ msr-data (PVC)   │ │ config         │  │
│  │ (CSI Driver)     │ │ (Persistent)     │ │ (ConfigMap)    │  │
│  └──────────────────┘ └──────────────────┘ └────────────────┘  │
│  ┌──────────────────┐ ┌──────────────────┐                     │
│  │ jms-config       │ │ license-key      │ ◄── License         │
│  │ (ConfigMap)      │ │ tc-license       │    ConfigMaps       │
│  └──────────────────┘ └──────────────────┘    (if enabled)     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Supporting Services

| Service | Purpose | Replicas | Persistence |
|---------|---------|----------|-------------|
| Universal Messaging | JMS messaging, pub/sub | 3 | PVC per node |
| Terracotta BigMemory | Distributed session cache | 2 | PVC per node |
| Azure SQL Database | ISInternal, Xref, Dashboard | N/A | Managed |

### 3.3 Helm Chart Structure

```
msr-helm/
├── README.md               # Quick start guide
├── Chart.yaml              # Chart metadata (v2.6.0)
├── values.yaml             # Default configuration (security context, caching, license, etc.)
├── values-dev.yaml         # Development environment overrides
├── values-qa.yaml          # QA environment overrides
├── values-prod.yaml        # Production environment overrides
├── adapters/               # Adapter configurations (separated for maintainability)
│   ├── values-jdbc-adapter-dev.yaml   # JDBC connections for dev
│   ├── values-jdbc-adapter-qa.yaml    # JDBC connections for QA
│   ├── values-jdbc-adapter-prod.yaml  # JDBC connections for prod
│   ├── values-sap-adapter-dev.yaml    # SAP connections/listeners for dev
│   ├── values-sap-adapter-qa.yaml     # SAP connections/listeners for QA
│   └── values-sap-adapter-prod.yaml   # SAP connections/listeners for prod
├── files/                  # Environment-specific static files mounted into MSR container
│   ├── dev/                # Development environment files
│   │   ├── config/
│   │   │   ├── aclmap_sm.cnf          # ACL map configuration
│   │   │   ├── jms.cnf               # JMS connection aliases (UM)
│   │   │   ├── jndi/
│   │   │   │   └── jndi_JNDI.properties  # JNDI provider configuration
│   │   │   └── caching/              # Public Cache Manager Ehcache XMLs
│   │   │       ├── OrderCache.xml
│   │   │       ├── SessionCache.xml
│   │   │       └── LookupCache.xml
│   │   ├── license/                  # License files (placeholders)
│   │   │   ├── licenseKey.xml        # IS/MSR license key
│   │   │   └── terracotta-license.key # TC BigMemory client license
│   │   └── integrationlive/          # webMethods Cloud configuration
│   │       ├── accounts.cnf
│   │       ├── connections.cnf
│   │       └── applications/*.cnf
│   ├── qa/                 # QA environment files (same structure as dev)
│   └── prod/               # Production environment files (same structure as dev)
├── docs/                   # Documentation
│   ├── ARCHITECTURE.md     # This document
│   ├── IMPLEMENTATION.md   # Deployment guides
│   └── ADDING-JDBC-CONNECTIONS.md  # JDBC adapter guide
└── templates/
    ├── _helpers.tpl        # Template helpers
    ├── statefulset.yaml    # MSR StatefulSet (security contexts, init containers)
    ├── service.yaml        # Kubernetes Service
    ├── configmap.yaml      # Application config, cache configs, ACL map, JMS/JNDI
    ├── secrets.yaml        # JDBC/security secrets
    ├── secretproviderclass.yaml  # Azure Key Vault CSI integration
    ├── hpa.yaml            # Horizontal Pod Autoscaler
    ├── serviceaccount.yaml # RBAC configuration
    ├── package-configs.yaml       # Package-specific app.properties
    └── webmethods-cloud-configmap.yaml  # webMethods Cloud config
```

**Key design decisions:**
- **Environment-specific files**: The `files/` directory is organized by environment (`dev/`, `qa/`, `prod/`). The `environment` value in each values file drives which directory is used at deploy time via `files/{{ .Values.environment }}/`.
- **Adapter separation**: Adapter configurations are in the `adapters/` folder to improve maintainability when dealing with many JDBC or SAP connections. This allows different teams to manage adapter configs independently.

---

## 4. Deployment Topologies

### 4.1 Topology Comparison

| Topology | MSR Nodes | Use Case | RTO | RPO |
|----------|-----------|----------|-----|-----|
| Minimal | 1 | Development/Testing | Hours | Minutes |
| Standard | 2 | Small Production | Minutes | Seconds |
| Enterprise | 3-5 | Large Production | Seconds | Near-zero |
| Multi-Region | 2+ per region | Global HA | Seconds | Near-zero |

### 4.2 Minimal Topology (Development)

```
┌─────────────────────────────────────────┐
│            Single AKS Cluster            │
│                                          │
│  ┌──────────┐                           │
│  │  MSR-0   │ ◄── Single replica        │
│  └──────────┘                           │
│       │                                  │
│       ▼                                  │
│  ┌──────────┐                           │
│  │  UM-0    │ ◄── Single UM node        │
│  └──────────┘                           │
│       │                                  │
│       ▼                                  │
│  ┌──────────┐                           │
│  │Azure SQL │ ◄── Development tier      │
│  └──────────┘                           │
└─────────────────────────────────────────┘

Resources: ~4 vCPU, 8GB RAM
Cost: ~$500/month
```

### 4.3 Standard Topology (Production)

```
┌─────────────────────────────────────────────────────────────┐
│                     Single AKS Cluster                       │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                      MSR Layer                          │ │
│  │                                                         │ │
│  │  ┌──────────┐   ┌──────────┐                           │ │
│  │  │  MSR-0   │   │  MSR-1   │ ◄── Pod Anti-Affinity    │ │
│  │  │  Node-A  │   │  Node-B  │     (different nodes)     │ │
│  │  └──────────┘   └──────────┘                           │ │
│  └────────────────────────────────────────────────────────┘ │
│                          │                                   │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                   Caching Layer                         │ │
│  │                                                         │ │
│  │  ┌──────────┐   ┌──────────┐                           │ │
│  │  │Terracotta│   │Terracotta│ ◄── Session replication  │ │
│  │  │    -0    │   │    -1    │                           │ │
│  │  └──────────┘   └──────────┘                           │ │
│  └────────────────────────────────────────────────────────┘ │
│                          │                                   │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  Messaging Layer                        │ │
│  │                                                         │ │
│  │  ┌──────────┐   ┌──────────┐   ┌──────────┐           │ │
│  │  │  UM-0    │   │  UM-1    │   │  UM-2    │           │ │
│  │  └──────────┘   └──────────┘   └──────────┘           │ │
│  │              UM Cluster (Quorum)                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                          │                                   │
│                          ▼                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Azure SQL (Standard Tier) - Geo-Replicated            │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

Resources: ~16 vCPU, 32GB RAM
Cost: ~$2,000/month
```

### 4.4 Enterprise Topology (High Availability)

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         Multi-Zone AKS Cluster                             │
│                                                                            │
│  Zone A                           Zone B                          Zone C   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐        │
│  │    MSR-0         │  │    MSR-1         │  │    MSR-2         │        │
│  │    MSR-3         │  │    MSR-4         │  │                  │        │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘        │
│           │                     │                     │                   │
│           └─────────────────────┼─────────────────────┘                   │
│                                 │                                          │
│                    ┌────────────▼────────────┐                            │
│                    │   Internal Load Balancer │                            │
│                    └────────────┬────────────┘                            │
│                                 │                                          │
│  ┌──────────────────────────────┴──────────────────────────────┐          │
│  │                     Terracotta Stripe                        │          │
│  │  ┌──────────┐  ┌──────────┐                                 │          │
│  │  │TC Active │  │TC Passive│  ◄── Active-Passive failover   │          │
│  │  │ Zone A   │  │ Zone B   │                                 │          │
│  │  └──────────┘  └──────────┘                                 │          │
│  └─────────────────────────────────────────────────────────────┘          │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────┐          │
│  │                    UM Cluster (3 nodes)                      │          │
│  │  ┌────────┐  ┌────────┐  ┌────────┐                         │          │
│  │  │ UM-0   │  │ UM-1   │  │ UM-2   │ ◄── Distributed across │          │
│  │  │ Zone A │  │ Zone B │  │ Zone C │    availability zones   │          │
│  │  └────────┘  └────────┘  └────────┘                         │          │
│  └─────────────────────────────────────────────────────────────┘          │
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────┐          │
│  │  Azure SQL (Business Critical) - Zone Redundant             │          │
│  └─────────────────────────────────────────────────────────────┘          │
└───────────────────────────────────────────────────────────────────────────┘

Resources: ~40 vCPU, 80GB RAM
Cost: ~$5,000/month
```

---

## 5. Security Architecture

### 5.1 Security Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                      SECURITY LAYERS                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 1: Network Security                                       │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • Azure NSG (Network Security Groups)                      │  │
│  │ • AKS Network Policies                                     │  │
│  │ • Private Endpoints for Azure services                     │  │
│  │ • VNet integration                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Layer 2: Identity & Access                                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • Azure AD / Entra ID integration                          │  │
│  │ • Managed Identity for pods                                │  │
│  │ • RBAC for Kubernetes resources                            │  │
│  │ • Azure Key Vault access policies                          │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Layer 3: Secrets Management                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • Azure Key Vault for all secrets                          │  │
│  │ • CSI driver for secret mounting                           │  │
│  │ • Environment-prefixed secrets (dev-, test-, prod-)        │  │
│  │ • No secrets in source code or Helm values                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Layer 4: Transport Security                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • TLS 1.2+ for all external connections                    │  │
│  │ • mTLS for internal service communication (optional)       │  │
│  │ • Azure Key Vault managed certificates                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Layer 5: Container Security                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • Pod: runAsUser=1724 (sagadmin), runAsNonRoot=true       │  │
│  │ • Container: capabilities.drop=[ALL], no privilege escal. │  │
│  │ • Init: root with minimal caps (CHOWN, DAC_OVERRIDE only) │  │
│  │ • ConfigMap/Secret mounts: readOnly=true                   │  │
│  │ • PVC: fsGroup=1724, fsGroupChangePolicy=OnRootMismatch   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Layer 6: Application Security                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • MSR ACL-based access control                             │  │
│  │ • Service-level authentication                             │  │
│  │ • Audit logging                                            │  │
│  │ • File Access Control (pub.file service paths)             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Azure Key Vault Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                  SECRETS FLOW                                    │
└─────────────────────────────────────────────────────────────────┘

                    AZURE KEY VAULT (wM-kv)
                    ┌─────────────────────────────────────────┐
                    │                                         │
                    │  Secrets (Environment-Prefixed)         │
                    │  ┌─────────────────────────────────────┐│
                    │  │ dev-jdbc-pool-password              ││
                    │  │ dev-jdbc-adapter-password           ││
                    │  │ dev-keystore-password               ││
                    │  │ dev-truststore-password             ││
                    │  │ dev-um-password                     ││
                    │  │ dev-truststore-root-ca              ││
                    │  │ ...                                 ││
                    │  └─────────────────────────────────────┘│
                    │                                         │
                    │  Certificates                           │
                    │  ┌─────────────────────────────────────┐│
                    │  │ wm-cer (with private key)           ││
                    │  └─────────────────────────────────────┘│
                    │                                         │
                    └─────────────────────┬───────────────────┘
                                          │
                         CSI Driver       │
                    ┌─────────────────────▼───────────────────┐
                    │       SecretProviderClass                │
                    │  • Maps Key Vault secrets to files       │
                    │  • Creates Kubernetes Secrets            │
                    │  • Uses Managed Identity auth            │
                    └─────────────────────┬───────────────────┘
                                          │
                    ┌─────────────────────▼───────────────────┐
                    │           MSR POD                        │
                    │                                          │
                    │  /mnt/secrets-store/                    │
                    │    ├── wm_keystore.p12                  │
                    │    ├── truststore-root-ca               │
                    │    └── ...                              │
                    │                                          │
                    │  Environment Variables:                  │
                    │    JDBC_POOL_PASSWORD=****              │
                    │    KEYSTORE_PASSWORD=****               │
                    │    UM_PASSWORD=****                     │
                    │                                          │
                    └─────────────────────────────────────────┘
```

### 5.3 Environment Secret Naming Convention

**Only passwords are stored in Azure Key Vault.** Non-sensitive configuration (URLs, usernames, server names) are stored directly in values files.

| Environment | Prefix | Key Vault | Example Secret |
|-------------|--------|-----------|----------------|
| Development | `dev-` | wM-kv | `dev-jdbcpool-ispool-password` |
| QA/Test | `test-` | wM-kv | `test-jdbcpool-ispool-password` |
| Production | `prod-` | wM-kv-prod | `prod-jdbcpool-ispool-password` |

### 5.4 Secret Naming Conventions by Component

| Component | Pattern | Example Key Vault Secret |
|-----------|---------|--------------------------|
| JDBC Pool | `{prefix}-jdbcpool-{poolname}-password` | `dev-jdbcpool-ispool-password` |
| JDBC Adapter | `{prefix}-jdbcadapter-{connection}-password` | `dev-jdbcadapter-mssql-password` |
| SAP Adapter | `{prefix}-sapadapter-{alias}-password` | `dev-sapadapter-rfcagency-password` |
| Keystore | `{prefix}-keystore-password` | `dev-keystore-password` |
| Truststore | `{prefix}-truststore-password` | `dev-truststore-password` |
| UM Connection | `{prefix}-um-{alias}-password` | `dev-um-business-password` |
| webMethods Cloud | `{prefix}-wmcloud-{account}-password` | `dev-wmcloud-dev-io-password` |

---

## 6. Integration Patterns

### 6.1 Universal Messaging Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                    UM INTEGRATION PATTERN                        │
└─────────────────────────────────────────────────────────────────┘

     MSR                                         External System
  ┌─────────┐                                    ┌─────────────┐
  │         │  1. Publish Message                │             │
  │  MSR-0  │ ─────────────────►┌─────────┐     │   Partner   │
  │         │                   │         │     │   System    │
  └─────────┘                   │   UM    │     │             │
                                │ Cluster │     └─────────────┘
  ┌─────────┐                   │         │           │
  │         │  2. Subscribe     │  ┌───┐  │           │
  │  MSR-1  │ ◄────────────────│  │ Q │  │◄──────────┘
  │         │     (Durable)     │  └───┘  │  3. Subscribe
  └─────────┘                   └─────────┘

Configuration (application.properties):
  messaging.IS_UM_CONNECTION.enabled=true
  messaging.IS_UM_CONNECTION.url=nsp://wm-um.webmethods.svc:9000
  messaging.IS_UM_CONNECTION.user=Administrator
  messaging.IS_UM_CONNECTION.password=$env{UM_PASSWORD}
```

### 6.2 Terracotta Session Clustering

```
┌─────────────────────────────────────────────────────────────────┐
│                 SESSION CLUSTERING PATTERN                       │
└─────────────────────────────────────────────────────────────────┘

  Client Request                    Terracotta Cluster
       │                         ┌────────────────────┐
       ▼                         │                    │
  ┌─────────┐  Session Data      │  ┌────────────┐   │
  │  MSR-0  │ ────────────────► │  │  Active    │   │
  │         │                    │  │  Server    │   │
  └─────────┘                    │  └────────────┘   │
                                 │        │          │
  ┌─────────┐  Session Data      │        ▼          │
  │  MSR-1  │ ────────────────► │  ┌────────────┐   │
  │         │                    │  │  Passive   │   │
  └─────────┘                    │  │  Server    │   │
                                 │  └────────────┘   │
                                 │                    │
                                 └────────────────────┘

Benefits:
  • Session failover between MSR nodes
  • Stateless MSR deployment
  • Horizontal scaling without session loss
```

### 6.3 JDBC Integration Patterns

```
┌─────────────────────────────────────────────────────────────────┐
│                    JDBC CONFIGURATION                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  JDBC POOL (MSR Internal Functions)                              │
│                                                                  │
│  Purpose: ISInternal, ISDashboardStats, Xref                    │
│                                                                  │
│  Configuration:                                                  │
│    jdbc.IS-Pool.dbURL=$env{JDBC_POOL_URL}                       │
│    jdbc.IS-Pool.userid=$env{JDBC_POOL_USERNAME}                 │
│    jdbc.IS-Pool.password=$env{JDBC_POOL_PASSWORD}               │
│    jdbc.IS-Pool.minConns=1                                      │
│    jdbc.IS-Pool.maxConns=100                                    │
│                                                                  │
│  Functional Aliases:                                             │
│    • ISInternal → IS-Pool                                       │
│    • ISDashboardStats → IS-Pool                                 │
│    • Xref → IS-Pool                                             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  JDBC ADAPTER (Business Integration)                             │
│                                                                  │
│  Purpose: WmJDBCAdapter connections for services                │
│  Config File: adapters/values-jdbc-adapter-{env}.yaml           │
│                                                                  │
│  Configuration:                                                  │
│    artConnection.AbTest.AbTest.mssql_db_connection              │
│      .connectionSettings.user=$env{JDBC_ADAPTER_USERNAME}       │
│      .connectionSettings.password=$env{JDBC_ADAPTER_PASSWORD}   │
│      .connectionManagerSettings.minPoolSize=1                   │
│      .connectionManagerSettings.maxPoolSize=10                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  SAP ADAPTER (SAP RFC/BAPI Integration)                          │
│                                                                  │
│  Purpose: WmSAP connections for SAP system integration          │
│  Config File: adapters/values-sap-adapter-{env}.yaml            │
│                                                                  │
│  Connections: (Package: SmSAPConn)                              │
│    artConnection.SmSAPConn.SmSAPConn.connNode_*                 │
│      .connectionSettings.user=$env{SAP_*_USER}                  │
│      .connectionSettings.password=$env{SAP_*_PASSWORD}          │
│                                                                  │
│  Listeners: (Package: SmSAPListeners)                           │
│    artListener.SmSAPListeners.SmSAPListeners.*                  │
│      .listenerSettings.sncMode=Yes/No                           │
│      .listenerSettings.sncMyName=p:CN=...                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Networking Architecture

### 7.1 Service Mesh

```
┌─────────────────────────────────────────────────────────────────┐
│                    KUBERNETES SERVICES                           │
└─────────────────────────────────────────────────────────────────┘

  External Traffic
        │
        ▼
┌───────────────────┐
│   LoadBalancer    │ ◄─── Azure Load Balancer (if enabled)
│   or Ingress      │      Public IP: xxx.xxx.xxx.xxx
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│   wm-msr          │ ◄─── ClusterIP Service
│   (ClusterIP)     │      Ports: 5555, 5543, 9999
│                   │      Selector: app=wm-msr
└─────────┬─────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
┌───────┐   ┌───────┐
│ Pod-0 │   │ Pod-1 │ ◄─── StatefulSet pods
└───────┘   └───────┘

Internal Services:
┌─────────────────────────────────────────────────────────────────┐
│  Service               │  Port  │  DNS Name                     │
├─────────────────────────────────────────────────────────────────┤
│  wm-msr                │  5555  │  wm-msr.webmethods.svc        │
│  wm-um                 │  9000  │  wm-um.webmethods.svc         │
│  terracotta-service    │  9510  │  terracotta-service.web...    │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Network Policies (Optional)

```yaml
# Example: Allow MSR to connect to UM only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: msr-to-um
spec:
  podSelector:
    matchLabels:
      app: wm-msr
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: wm-um
      ports:
        - port: 9000
```

---

## 8. Storage Architecture

### 8.1 Persistent Volume Claims

```
┌─────────────────────────────────────────────────────────────────┐
│                    STORAGE ARCHITECTURE                          │
└─────────────────────────────────────────────────────────────────┘

MSR StatefulSet
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│  MSR-0                              MSR-1                       │
│  ┌─────────────────────┐           ┌─────────────────────┐     │
│  │                     │           │                     │     │
│  │  /var/msr/data      │           │  /var/msr/data      │     │
│  │       │             │           │       │             │     │
│  └───────┼─────────────┘           └───────┼─────────────┘     │
│          │                                 │                    │
│          ▼                                 ▼                    │
│  ┌───────────────┐                ┌───────────────┐            │
│  │ PVC: msr-data │                │ PVC: msr-data │            │
│  │     -msr-0    │                │     -msr-1    │            │
│  │   Size: 3Gi   │                │   Size: 3Gi   │            │
│  └───────┬───────┘                └───────┬───────┘            │
│          │                                 │                    │
│          ▼                                 ▼                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Azure Managed Disk (default StorageClass)   │   │
│  │              Premium SSD recommended for production      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

Storage Classes:
  • default      - Azure Managed Disk (Standard SSD)
  • managed-csi  - Azure Managed Disk with CSI driver
  • azurefile    - Azure File Share (ReadWriteMany)
```

### 8.2 Volume Types

| Volume Type | Mount Path | Purpose | Persistence |
|-------------|------------|---------|-------------|
| PVC (msr-data) | /var/msr/data | Packages, logs | Retained on restart |
| CSI (keyvault) | /mnt/secrets-store | Certificates | Re-mounted on start |
| ConfigMap | /opt/.../config | Application config | Updated on upgrade |
| ConfigMap (license) | /opt/.../config/licenseKey.xml | IS license key | Updated on upgrade |
| ConfigMap (tc-license) | /opt/.../config/terracotta-license.key | TC client license | Updated on upgrade |
| EmptyDir | /opt/.../kv-keystores | Converted keystores | Ephemeral |

---

## 9. High Availability & Disaster Recovery

### 9.1 HA Configuration

| Component | HA Strategy | Min Replicas | Recovery Time |
|-----------|-------------|--------------|---------------|
| MSR | Pod Anti-Affinity | 2 | ~60 seconds |
| UM | Quorum-based | 3 | ~30 seconds |
| Terracotta | Active-Passive | 2 | ~15 seconds |
| Azure SQL | Zone Redundant | N/A | Automatic |

### 9.2 Pod Disruption Budget

```yaml
# Ensures minimum availability during updates
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: wm-msr-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: wm-msr
```

### 9.3 Disaster Recovery Scenarios

| Scenario | Impact | Recovery Action | RTO |
|----------|--------|-----------------|-----|
| Single pod failure | Minimal | Automatic restart | 2 min |
| Node failure | Minimal | Pod rescheduling | 5 min |
| Zone failure | Degraded | Cross-zone failover | 10 min |
| Region failure | Full outage | DR site activation | 30 min |

---

## 10. Scaling Architecture

### 10.1 Horizontal Pod Autoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: wm-msr-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: wm-msr
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

### 10.2 Scaling Recommendations

| Environment | Min Pods | Max Pods | CPU Request | Memory Request |
|-------------|----------|----------|-------------|----------------|
| Development | 1 | 2 | 500m | 1Gi |
| QA | 2 | 4 | 1000m | 2Gi |
| Production | 2 | 8 | 2000m | 4Gi |

---

## 11. Monitoring & Observability

### 11.1 Metrics & Logging

```
┌─────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY STACK                           │
└─────────────────────────────────────────────────────────────────┘

  MSR Pods
  ┌─────────┐
  │  MSR-0  │ ──── Port 9999 ────►  Prometheus
  │         │      (Metrics)         (Scraping)
  └─────────┘                            │
                                         ▼
  ┌─────────┐                      ┌──────────┐
  │  MSR-1  │ ──── stdout ────────►│  Azure   │
  │         │      (Logs)          │ Monitor  │
  └─────────┘                      └──────────┘
                                         │
                                         ▼
                                   ┌──────────┐
                                   │  Grafana │
                                   │Dashboard │
                                   └──────────┘
```

### 11.2 Key Metrics to Monitor

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU Utilization | > 70% | Scale up |
| Memory Utilization | > 80% | Scale up |
| Pod Restart Count | > 3 | Investigate |
| Request Latency P99 | > 5s | Investigate |
| JDBC Pool Utilization | > 80% | Increase pool |

---

## 12. Environment Strategy

### 12.1 Values Files Structure

```
msr-helm/
├── README.md            # Quick start guide
├── values.yaml          # Base configuration (defaults)
├── values-dev.yaml      # Development overrides (environment: dev)
├── values-qa.yaml       # QA/Test overrides (environment: qa)
├── values-prod.yaml     # Production overrides (environment: prod)
├── adapters/            # Separated adapter configurations
│   ├── values-jdbc-adapter-dev.yaml   # JDBC connections (dev)
│   ├── values-jdbc-adapter-qa.yaml    # JDBC connections (QA)
│   ├── values-jdbc-adapter-prod.yaml  # JDBC connections (prod)
│   ├── values-sap-adapter-dev.yaml    # SAP connections/listeners (dev)
│   ├── values-sap-adapter-qa.yaml     # SAP connections/listeners (QA)
│   └── values-sap-adapter-prod.yaml   # SAP connections/listeners (prod)
├── files/               # Environment-specific static files
│   ├── dev/             # Dev files (config/, integrationlive/)
│   ├── qa/              # QA files (same structure)
│   └── prod/            # Prod files (same structure)
├── docs/                # Documentation
│   ├── ARCHITECTURE.md  # This document
│   └── IMPLEMENTATION.md # Deployment guides
└── templates/           # Helm templates
```

**Benefits of Adapter Separation:**
- Independent versioning of adapter configurations
- Different teams can manage JDBC vs SAP configs
- Cleaner git diffs when adding/modifying connections
- Easier to scale to many connections (50+ SAP connections)

### 12.2 Environment Comparison

| Setting | Development | QA | Production |
|---------|-------------|-----|------------|
| Replicas | 2 | 3 | 3-5 |
| CPU Request | 1000m | 1000m | 2000m |
| Memory Request | 1Gi | 2Gi | 4Gi |
| Secret Prefix | `dev-` | `test-` | `prod-` |
| HPA Enabled | Yes | Yes | Yes |
| PDB Enabled | Yes | Yes | Yes |
| Key Vault | wM-kv | wM-kv | wM-kv-prod |
| runAsNonRoot | true | true | true |
| allowPrivilegeEscalation | false | false | false |
| capabilities.drop | ALL | ALL | ALL |

### 12.3 Deployment Commands

```bash
# Development (with all adapters)
helm upgrade --install wm-msr ./msr-helm \
  -n webmethods \
  -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml \
  -f adapters/values-sap-adapter-dev.yaml

# Development (JDBC only, no SAP)
helm upgrade --install wm-msr ./msr-helm \
  -n webmethods \
  -f values-dev.yaml \
  -f adapters/values-jdbc-adapter-dev.yaml

# QA
helm upgrade --install wm-msr ./msr-helm \
  -n webmethods-qa \
  -f values-qa.yaml \
  -f adapters/values-jdbc-adapter-qa.yaml \
  -f adapters/values-sap-adapter-qa.yaml

# Production
helm upgrade --install wm-msr ./msr-helm \
  -n webmethods-prod \
  -f values-prod.yaml \
  -f adapters/values-jdbc-adapter-prod.yaml \
  -f adapters/values-sap-adapter-prod.yaml
```

---

## Appendix A: Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| StatefulSet over Deployment | Stable pod names, ordered scaling | Oct 2024 |
| Azure Key Vault for secrets | Zero-trust, centralized management | Oct 2024 |
| Environment-prefixed secrets | Multi-env in single Key Vault | Dec 2024 |
| Terracotta for caching | Vendor-supported, session clustering | Nov 2024 |
| UM over Kafka | Native IS integration, simpler ops | Nov 2024 |
| Separated adapter configs | Scalability for many connections, team separation | Jan 2026 |
| Separate SAP conn/listener packages | Different IS packages for connections vs listeners | Jan 2026 |
| File access control via ConfigMap | Security for pub.file services, environment-specific paths | Jan 2026 |
| Package-specific app.properties | Environment-specific configuration per package | Jan 2026 |
| Container security hardening (sagadmin UID 1724) | IBM/SoftwareAG best practice, non-root, drop all caps | Feb 2026 |
| Read-only ConfigMap/Secret mounts | Prevent accidental modification of mounted configs | Feb 2026 |
| Public cache managers (Ehcache XML) | In-memory caching with auto-discovery and auto-start | Feb 2026 |
| Environment-specific files (`files/{env}/`) | Per-environment config files (aclmap, caching, integrationlive, JMS) without chart duplication | Feb 2026 |
| JMS/JNDI ConfigMap mount | UM JMS connectivity via `jms.cnf` and `jndi_JNDI.properties`, toggleable per env | Feb 2026 |
| QA adapter configurations | Full Dev/QA/Prod adapter parity for JDBC and SAP | Feb 2026 |
| License management via ConfigMap | IS + TC client licenses mounted per environment, disabled by default for safety | Feb 2026 |

---

## Appendix B: Related Documents

| Document | Purpose |
|----------|---------|
| [README.md](../README.md) | Quick start guide |
| [IMPLEMENTATION.md](IMPLEMENTATION.md) | Step-by-step deployment |
| [ADDING-JDBC-CONNECTIONS.md](ADDING-JDBC-CONNECTIONS.md) | Adding new JDBC connections |

---

*Document maintained by the webMethods Platform Team. For questions, contact the platform engineering team.*
