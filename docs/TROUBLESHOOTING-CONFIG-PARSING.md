# Troubleshooting Configuration Parsing Differences

## Overview

This guide helps identify and resolve configuration parsing differences between Dev, QA, and Prod environments, particularly for files like `monitor.cnf`, `server.cnf`, and other Integration Server configuration files.

## Common Causes of Environment-Specific Parsing Issues

### 1. **Missing Values in Helm Templates**

**Symptom:** Configuration works in Dev/QA but fails in Prod with "format issues" or "xmlformat" errors.

**Root Cause:** Environment-specific values files (e.g., `values-prod.yaml`) are missing properties that are referenced in Helm templates.

**Example:**
```yaml
# Template references these properties:
enableDataCollection={{ .Values.dashboardStatistics.collection }}
maxResults={{ .Values.dashboardStatistics.maxResults }}

# But values-prod.yaml only has:
dashboardStatistics:
  collection: false
  # maxResults is MISSING - renders as "<no value>"
```

**Solution:**
- Ensure all properties referenced in templates are defined in ALL environment values files
- Use the diagnostic script: `./scripts/diagnose-config-differences.sh all`

### 2. **Different Docker Image Versions**

**Symptom:** Same Helm chart works differently across environments.

**Root Cause:** Different webMethods MSR image versions may have:
- Different configuration parsers
- Different validation rules
- Different default behaviors

**Check:**
```bash
# Compare image tags across environments
grep "tag:" values-dev.yaml values-qa.yaml values-prod.yaml
```

**Current Status:**
- Dev: `11.1.0.6-build-299`
- QA: `11.1.0.6`
- Prod: `11.1.0.6-build-272`

**Solution:**
- Use the same image version across all environments
- Test configuration changes in Dev with the Prod image version before deploying

### 3. **Kubernetes Cluster Differences**

**Symptom:** ConfigMaps or Secrets behave differently in Prod.

**Possible Causes:**
- Different Kubernetes versions
- Different admission controllers
- Different policy engines (OPA, Kyverno, etc.)
- Different ConfigMap size limits
- Different validation webhooks

**Check:**
```bash
# Check Kubernetes version
kubectl version --short

# Check admission controllers
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Check for policy engines
kubectl get constrainttemplates  # Gatekeeper/OPA
kubectl get clusterpolicies      # Kyverno
```

### 4. **Pipeline vs Manual Deployment**

**Symptom:** Manual deployments work, but pipeline deployments fail (or vice versa).

**Root Cause:** Pipeline may:
- Override values with `--set` flags
- Use different Helm versions
- Build images differently (affecting embedded configs)
- Apply different validation steps

**Check:**
```bash
# Review pipeline deployment command
# Look for --set overrides that might affect configuration
```

### 5. **ConfigMap Size Limits**

**Symptom:** Large configuration files fail to deploy in Prod.

**Root Cause:** Kubernetes ConfigMaps have a 1MB size limit by default. Some clusters may have stricter limits.

**Check:**
```bash
# Check ConfigMap size
kubectl get configmap <configmap-name> -o yaml | wc -c

# Check for size-related errors
kubectl describe configmap <configmap-name>
```

## Diagnostic Tools

### 1. Use the Diagnostic Script

```bash
cd msr-helm

# Check all environments
./scripts/diagnose-config-differences.sh all

# Check specific environment
./scripts/diagnose-config-differences.sh prod
```

The script will:
- Render Helm templates for each environment
- Extract and validate monitor.cnf
- Compare configurations across environments
- Check for missing values or malformed content
- Generate a comprehensive report

### 2. Manual Helm Template Validation

```bash
# Render template and check for issues
helm template test-release . -f values-prod.yaml --debug > /tmp/prod-template.yaml

# Search for problematic patterns
grep "<no value>" /tmp/prod-template.yaml
grep "=$" /tmp/prod-template.yaml  # Empty values
```

### 3. Compare Rendered ConfigMaps

```bash
# Extract ConfigMap from each environment
helm template test . -f values-dev.yaml | grep -A 100 "kind: ConfigMap" > /tmp/dev-cm.yaml
helm template test . -f values-qa.yaml | grep -A 100 "kind: ConfigMap" > /tmp/qa-cm.yaml
helm template test . -f values-prod.yaml | grep -A 100 "kind: ConfigMap" > /tmp/prod-cm.yaml

# Compare
diff /tmp/dev-cm.yaml /tmp/prod-cm.yaml
```

### 4. Check Running Pods

```bash
# Get the actual monitor.cnf from a running pod
kubectl exec -it <pod-name> -- cat /opt/softwareag/IntegrationServer/instances/default/config/monitor/monitor.cnf

# Compare with expected
helm template test . -f values-prod.yaml | grep -A 20 "monitor.cnf:"
```

## Specific Issue: monitor.cnf Format Problem

### Problem Description
Client reported: "monitor.cnf is not in xmlformat" when deploying to Prod via pipeline.

### Root Cause
The `values-prod.yaml` file was missing three required properties:
- `maxResults`
- `luceneMemorySize`
- `indexerThreadCount`

This caused Helm to render these values as `<no value>`, creating a malformed configuration file.

### Solution Applied
Added missing properties to all environment values files:

```yaml
dashboardStatistics:
  enabled: true
  collection: false
  retentionDays: 7
  maxResults: 1500000            # ADDED
  luceneMemorySize: 256          # ADDED
  indexerThreadCount: 8          # ADDED
```

### Verification Steps

1. **Validate Helm template rendering:**
   ```bash
   helm template test . -f values-prod.yaml --debug 2>&1 | grep -A 15 "monitor.cnf:"
   ```

2. **Check for missing values:**
   ```bash
   helm template test . -f values-prod.yaml | grep "<no value>"
   # Should return nothing
   ```

3. **Deploy and verify:**
   ```bash
   helm upgrade --install msr . -f values-prod.yaml
   kubectl exec -it msr-0 -- cat /opt/softwareag/IntegrationServer/instances/default/config/monitor/monitor.cnf
   ```

## Prevention Checklist

- [ ] All properties referenced in templates are defined in ALL environment values files
- [ ] Use the same Docker image version across all environments (or test with prod image in lower envs)
- [ ] Run `helm template` validation before deploying to production
- [ ] Use the diagnostic script as part of CI/CD pipeline
- [ ] Document any environment-specific configuration requirements
- [ ] Keep values files in sync (use a base values file and override only what's different)
- [ ] Add Helm template tests for critical configuration files
- [ ] Monitor ConfigMap sizes to avoid hitting limits

## Best Practices

### 1. Use Default Values in values.yaml

Define all properties with defaults in the main `values.yaml`:

```yaml
dashboardStatistics:
  enabled: false
  collection: false
  retentionDays: 7
  maxResults: 1500000
  luceneMemorySize: 256
  indexerThreadCount: 8
```

Then override only what's different in environment-specific files.

### 2. Add Template Validation

Add required value checks in templates:

```yaml
{{- if .Values.dashboardStatistics.enabled }}
{{- if not .Values.dashboardStatistics.maxResults }}
{{- fail "dashboardStatistics.maxResults is required when dashboardStatistics.enabled is true" }}
{{- end }}
monitor.cnf: |
  enableDataCollection={{ .Values.dashboardStatistics.collection }}
  maxResults={{ .Values.dashboardStatistics.maxResults }}
  ...
{{- end }}
```

### 3. Use Helm Lint

```bash
helm lint . -f values-prod.yaml
```

### 4. Implement Pre-Deployment Validation

Add to your CI/CD pipeline:

```bash
# Validate all environments
for env in dev qa prod; do
  echo "Validating $env..."
  helm template test . -f values-${env}.yaml --validate
  ./scripts/diagnose-config-differences.sh $env
done
```

## Additional Resources

- [Helm Template Debugging](https://helm.sh/docs/chart_template_guide/debugging/)
- [Kubernetes ConfigMap Documentation](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [webMethods Integration Server Configuration](https://documentation.softwareag.com/)

## Support

If issues persist after following this guide:

1. Run the diagnostic script and save the report
2. Collect logs from failed deployments
3. Compare working vs non-working configurations
4. Check for cluster-specific policies or restrictions
5. Contact your Kubernetes cluster administrator for environment-specific constraints