# MSR Helm Chart - Deployment Summary

## ✅ Helm Chart Complete

The multi-environment MSR Helm chart is ready for deployment in `10112025_v1/msr-helm/`.

## 📁 Chart Structure

```
msr-helm/
├── Chart.yaml                  # Helm chart metadata (v1.0.0)
├── values.yaml                 # Default values (2-node cluster)
├── values-dev.yaml             # Dev environment (2 nodes, reduced resources)
├── values-prod.yaml            # Prod environment (3 nodes, full resources)
├── README.md                   # Comprehensive deployment guide
├── DEPLOYMENT_SUMMARY.md       # This file
└── templates/
    ├── _helpers.tpl            # Template helper functions
    ├── configmap.yaml          # JDBC configuration
    ├── statefulset.yaml        # MSR StatefulSet (scalable cluster)
    └── service.yaml            # ClusterIP service
```

## 🎯 Key Features

- ✅ Multi-node cluster (2-3 nodes, scalable to any size)
- ✅ PostgreSQL JDBC pre-configured with IS-Pool
- ✅ Multi-environment support (dev, prod values files)
- ✅ High Availability with Pod Anti-Affinity
- ✅ Pod Disruption Budget for zero-downtime updates
- ✅ Health Probes (startup, liveness, readiness)
- ✅ Resource management per environment
- ✅ Persistent storage per pod

## 🚀 Quick Start

### Deploy to Development (2-node cluster)

```bash
cd C:\Users\abhia\OneDrive\Desktop\SMUD\fullStack\working_09252025\IS-Cluster\10112025_v1

helm install wm-msr ./msr-helm \
  --namespace webmethods \
  --values msr-helm/values-dev.yaml \
  --wait --timeout 10m
```

### Deploy to Production (3-node cluster)

```bash
cd C:\Users\abhia\OneDrive\Desktop\SMUD\fullStack\working_09252025\IS-Cluster\10112025_v1

helm install wm-msr ./msr-helm \
  --namespace webmethods \
  --values msr-helm/values-prod.yaml \
  --wait --timeout 15m
```

## 📊 Environment Configurations

### Development (values-dev.yaml)
- **Replicas**: 2 nodes
- **Memory**: 512Mi request, 1Gi limit
- **CPU**: 250m request, 500m limit
- **Storage**: 3Gi per pod (default storageClass)
- **JVM**: 256m min, 512m max
- **JDBC**: Max 10 connections

### Production (values-prod.yaml)
- **Replicas**: 3 nodes
- **Memory**: 2Gi request, 4Gi limit
- **CPU**: 1000m request, 2000m limit
- **Storage**: 10Gi per pod (managed-premium)
- **JVM**: 1024m min, 2048m max
- **JDBC**: Max 50 connections

## 🔧 JDBC Configuration

### JDBC Pool: IS-Pool
- **Driver**: PostgresqlDriver (org.postgresql.Driver)
- **URL**: jdbc:postgresql://wm-postgresql.webmethods.svc.cluster.local:5432/isinternal
- **Username**: isadmin
- **Password**: isdbpassword

### JDBC Functional Aliases
- **ISInternal** → IS-Pool (failFastMode: true)
- **ISDashboardStats** → IS-Pool (failFastMode: false)
- **Xref** → IS-Pool (failFastMode: true)

## 📈 Scaling

### Scale Up to 5 nodes
```bash
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --set replicaCount=5 \
  --reuse-values
```

### Scale Down to 2 nodes
```bash
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --set replicaCount=2 \
  --reuse-values
```

## 🔍 Monitoring

```bash
# Check pod status
kubectl get pods -n webmethods -l app=wm-msr

# Check logs
kubectl logs -n webmethods wm-msr-0 --tail=100

# Check JDBC configuration
kubectl logs -n webmethods wm-msr-0 | grep -i "jdbc\|pool"
```

## 🌐 Access MSR

### Port-Forward to localhost
```bash
# Access first pod
kubectl port-forward -n webmethods pod/wm-msr-0 5555:5555

# Access via service (load-balanced)
kubectl port-forward -n webmethods svc/wm-msr 5555:5555
```

Then open: **http://localhost:5555**
- Username: `Administrator`
- Password: `manage`

## 📝 Prerequisites

1. ✅ AKS Cluster deployed (`webmethods-cluster`)
2. ✅ PostgreSQL deployed (`wm-postgresql.webmethods.svc.cluster.local:5432`)
3. ✅ MSR Image: `abiwebmethods.azurecr.io/webmethods-microservicesruntime:11.1.0.6-postgresql-v2`
4. ✅ Helm 3.x installed
5. ✅ kubectl configured

## 🗑️ Uninstall

```bash
# Uninstall MSR
helm uninstall wm-msr -n webmethods

# Delete PVCs (data will be lost!)
kubectl delete pvc -n webmethods -l app=wm-msr
```

## 📚 References

- [Chart README](./README.md) - Full deployment guide
- [IBM webMethods Documentation](https://www.ibm.com/docs/en/webmethods-integration/wm-integration-server/11.1.0)
- [IBM webMethods Demos](https://github.com/ibm-webmethods-demos)

---

**Status**: ✅ Ready for deployment
**Created**: October 11, 2025
**Version**: 1.0.0
