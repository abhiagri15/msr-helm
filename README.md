# webMethods MSR Helm Chart
## Multi-Environment, Scalable Deployment with PostgreSQL JDBC

This Helm chart deploys webMethods MicroServices Runtime (MSR) v11.1.0.6 with PostgreSQL JDBC connectivity in a multi-node cluster configuration.

## Features

- ✅ **Multi-node cluster** (2-node default, scalable to any size)
- ✅ **PostgreSQL JDBC** pre-configured with IS-Pool
- ✅ **Multi-environment support** (dev, prod values files)
- ✅ **High Availability** with Pod Anti-Affinity
- ✅ **Pod Disruption Budget** for zero-downtime updates
- ✅ **Health Probes** (startup, liveness, readiness)
- ✅ **Resource management** per environment
- ✅ **Persistent storage** per pod

## Chart Structure

```
msr-helm/
├── Chart.yaml                 # Helm chart metadata
├── values.yaml               # Default configuration (2-node cluster)
├── values-dev.yaml           # Dev environment (2 nodes, reduced resources)
├── values-prod.yaml          # Prod environment (3 nodes, full resources)
├── templates/
│   ├── _helpers.tpl          # Template helpers
│   ├── configmap.yaml        # JDBC configuration
│   ├── statefulset.yaml      # MSR StatefulSet
│   └── service.yaml          # ClusterIP service
└── README.md                 # This file
```

## Prerequisites

1. **AKS Cluster** deployed and configured
2. **PostgreSQL** deployed: `wm-postgresql.webmethods.svc.cluster.local:5432`
   - Database: `isinternal`
   - Username: `isadmin`
   - Password: `isdbpassword`
3. **MSR Image**: `abiwebmethods.azurecr.io/webmethods-microservicesruntime:11.1.0.6-postgresql-v2`
4. **Helm 3.x** installed
5. **kubectl** configured to access your cluster

## Quick Start

### Deploy to Development (2-node cluster)

```bash
# Install MSR in dev mode
helm install wm-msr ./msr-helm \
  --namespace webmethods \
  --values msr-helm/values-dev.yaml \
  --wait --timeout 10m

# Verify deployment
kubectl get pods -n webmethods -l app=wm-msr
```

### Deploy to Production (3-node cluster)

```bash
# Install MSR in prod mode
helm install wm-msr ./msr-helm \
  --namespace webmethods \
  --values msr-helm/values-prod.yaml \
  --wait --timeout 15m

# Verify deployment
kubectl get pods -n webmethods -l app=wm-msr
```

## Configuration

### Default Configuration (values.yaml)

- **Replicas**: 2 nodes
- **Memory**: 1Gi request, 2Gi limit per pod
- **CPU**: 500m request, 1000m limit per pod
- **Storage**: 5Gi per pod
- **JVM**: 512m min, 1024m max

### Dev Environment (values-dev.yaml)

- **Replicas**: 2 nodes
- **Memory**: 512Mi request, 1Gi limit
- **CPU**: 250m request, 500m limit
- **Storage**: 3Gi per pod
- **JVM**: 256m min, 512m max
- **JDBC**: Max 10 connections

### Prod Environment (values-prod.yaml)

- **Replicas**: 3 nodes
- **Memory**: 2Gi request, 4Gi limit
- **CPU**: 1000m request, 2000m limit
- **Storage**: 10Gi per pod
- **JVM**: 1024m min, 2048m max
- **JDBC**: Max 50 connections

## Scaling

### Scale Up

```bash
# Scale to 5 nodes
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --set replicaCount=5 \
  --reuse-values

# Or edit values file and upgrade
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --values msr-helm/values-prod.yaml
```

### Scale Down

```bash
# Scale down to 2 nodes
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --set replicaCount=2 \
  --reuse-values
```

## JDBC Configuration

The Helm chart automatically configures:

### JDBC Pool (IS-Pool)
- **Driver**: PostgresqlDriver (org.postgresql.Driver)
- **URL**: jdbc:postgresql://wm-postgresql.webmethods.svc.cluster.local:5432/isinternal
- **Username**: isadmin
- **Password**: isdbpassword

### JDBC Functional Aliases
- **ISInternal** → IS-Pool (failFastMode: true)
- **ISDashboardStats** → IS-Pool (failFastMode: false)
- **Xref** → IS-Pool (failFastMode: true)

## Access MSR

### Port-Forward to localhost

```bash
# Access first pod
kubectl port-forward -n webmethods pod/wm-msr-0 5555:5555

# Access via service (load-balanced across all pods)
kubectl port-forward -n webmethods svc/wm-msr 5555:5555
```

Then open: **http://localhost:5555**
- Username: `Administrator`
- Password: `manage`

## Monitoring

```bash
# Check pod status
kubectl get pods -n webmethods -l app=wm-msr

# Check logs
kubectl logs -n webmethods wm-msr-0 --tail=100

# Check JDBC configuration
kubectl logs -n webmethods wm-msr-0 | grep -i "jdbc\|pool"

# Describe pod
kubectl describe pod -n webmethods wm-msr-0
```

## Upgrade

```bash
# Upgrade with new values
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --values msr-helm/values-prod.yaml

# Upgrade with specific parameters
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --set replicaCount=4 \
  --set resources.limits.memory=3Gi
```

## Rollback

```bash
# List releases
helm history wm-msr -n webmethods

# Rollback to previous version
helm rollback wm-msr -n webmethods

# Rollback to specific revision
helm rollback wm-msr 2 -n webmethods
```

## Uninstall

```bash
# Uninstall MSR
helm uninstall wm-msr -n webmethods

# Delete PVCs (data will be lost!)
kubectl delete pvc -n webmethods -l app=wm-msr
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n webmethods wm-msr-0

# Check logs
kubectl logs -n webmethods wm-msr-0

# Check if PostgreSQL is accessible
kubectl exec -n webmethods wm-msr-0 -- curl -v telnet://wm-postgresql:5432
```

### JDBC Connection Issues

```bash
# Verify ConfigMap is mounted
kubectl exec -n webmethods wm-msr-0 -- cat /opt/softwareag/IntegrationServer/application.properties

# Check JDBC logs
kubectl logs -n webmethods wm-msr-0 | grep -i "jdbc\|pool\|postgres"
```

### Resource Constraints

```bash
# Check resource usage
kubectl top pods -n webmethods -l app=wm-msr

# Increase resources
helm upgrade wm-msr ./msr-helm \
  --namespace webmethods \
  --set resources.limits.memory=4Gi \
  --set resources.limits.cpu=2000m
```

## References

- [IBM webMethods Documentation](https://www.ibm.com/docs/en/webmethods-integration/wm-integration-server/11.1.0)
- [IBM webMethods Demos](https://github.com/ibm-webmethods-demos)
- [Helm Documentation](https://helm.sh/docs/)

## Support

For issues or questions, contact the webMethods Team.
