#!/bin/bash
# ==============================================================================
# Configuration Parsing Diagnostics Script
# ==============================================================================
# This script helps identify differences in how configurations are parsed
# across Dev, QA, and Prod environments.
#
# Usage:
#   ./diagnose-config-differences.sh [environment]
#   
# Examples:
#   ./diagnose-config-differences.sh dev
#   ./diagnose-config-differences.sh qa
#   ./diagnose-config-differences.sh prod
#   ./diagnose-config-differences.sh all    # Compare all environments
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="/tmp/msr-helm-diagnostics-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to check Helm installation
check_helm() {
    if ! command -v helm &> /dev/null; then
        print_error "Helm is not installed. Please install Helm first."
        exit 1
    fi
    print_success "Helm found: $(helm version --short)"
}

# Function to render Helm template for an environment
render_template() {
    local env=$1
    local output_dir="$TEMP_DIR/$env"
    
    mkdir -p "$output_dir"
    
    print_header "Rendering Helm template for $env environment"
    
    if helm template test-release "$CHART_DIR" \
        -f "$CHART_DIR/values-${env}.yaml" \
        --output-dir "$output_dir" \
        --debug > "$output_dir/helm-debug.log" 2>&1; then
        print_success "Template rendered successfully for $env"
        return 0
    else
        print_error "Failed to render template for $env"
        cat "$output_dir/helm-debug.log"
        return 1
    fi
}

# Function to extract monitor.cnf from rendered templates
extract_monitor_cnf() {
    local env=$1
    local configmap_file="$TEMP_DIR/$env/webmethods-msr/templates/configmap.yaml"
    local output_file="$TEMP_DIR/$env/monitor.cnf"
    
    if [ -f "$configmap_file" ]; then
        # Extract monitor.cnf content from ConfigMap
        awk '/monitor\.cnf: \|/,/^[^ ]/' "$configmap_file" | \
            grep -v "monitor.cnf:" | \
            sed 's/^    //' > "$output_file"
        
        if [ -s "$output_file" ]; then
            print_success "Extracted monitor.cnf for $env ($(wc -l < "$output_file") lines)"
            return 0
        else
            print_warning "monitor.cnf is empty for $env"
            return 1
        fi
    else
        print_error "ConfigMap file not found for $env"
        return 1
    fi
}

# Function to validate monitor.cnf format
validate_monitor_cnf() {
    local env=$1
    local monitor_file="$TEMP_DIR/$env/monitor.cnf"
    
    print_header "Validating monitor.cnf format for $env"
    
    if [ ! -f "$monitor_file" ]; then
        print_error "monitor.cnf not found for $env"
        return 1
    fi
    
    local issues=0
    
    # Check for required properties
    local required_props=("enableDataCollection" "retentionDays" "maxResults" "luceneMemorySize" "indexerThreadCount")
    
    for prop in "${required_props[@]}"; do
        if grep -q "^${prop}=" "$monitor_file"; then
            local value=$(grep "^${prop}=" "$monitor_file" | cut -d'=' -f2)
            if [ -z "$value" ] || [ "$value" = "<no value>" ]; then
                print_error "Property '$prop' has no value"
                ((issues++))
            else
                print_success "Property '$prop' = $value"
            fi
        else
            print_error "Required property '$prop' is missing"
            ((issues++))
        fi
    done
    
    # Check for malformed lines
    if grep -q "=<no value>" "$monitor_file"; then
        print_error "Found '<no value>' placeholders in monitor.cnf"
        grep "=<no value>" "$monitor_file"
        ((issues++))
    fi
    
    # Check for empty values
    if grep -q "=$" "$monitor_file"; then
        print_warning "Found empty values in monitor.cnf"
        grep "=$" "$monitor_file"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        print_success "monitor.cnf format is valid for $env"
        return 0
    else
        print_error "Found $issues issue(s) in monitor.cnf for $env"
        return 1
    fi
}

# Function to compare monitor.cnf across environments
compare_environments() {
    print_header "Comparing monitor.cnf across environments"
    
    local envs=("dev" "qa" "prod")
    
    echo ""
    echo "Property Comparison:"
    echo "===================="
    printf "%-25s %-15s %-15s %-15s\n" "Property" "Dev" "QA" "Prod"
    printf "%-25s %-15s %-15s %-15s\n" "--------" "---" "--" "----"
    
    local props=("enableDataCollection" "retentionDays" "maxResults" "luceneMemorySize" "indexerThreadCount")
    
    for prop in "${props[@]}"; do
        local dev_val=$(grep "^${prop}=" "$TEMP_DIR/dev/monitor.cnf" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
        local qa_val=$(grep "^${prop}=" "$TEMP_DIR/qa/monitor.cnf" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
        local prod_val=$(grep "^${prop}=" "$TEMP_DIR/prod/monitor.cnf" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
        
        printf "%-25s %-15s %-15s %-15s" "$prop" "$dev_val" "$qa_val" "$prod_val"
        
        # Highlight differences
        if [ "$dev_val" != "$qa_val" ] || [ "$dev_val" != "$prod_val" ] || [ "$qa_val" != "$prod_val" ]; then
            echo -e " ${YELLOW}[DIFFERENT]${NC}"
        else
            echo -e " ${GREEN}[SAME]${NC}"
        fi
    done
    
    echo ""
}

# Function to check image versions
check_image_versions() {
    print_header "Checking Docker Image Versions"
    
    local envs=("dev" "qa" "prod")
    
    echo ""
    printf "%-15s %-60s %-20s\n" "Environment" "Image Repository" "Tag"
    printf "%-15s %-60s %-20s\n" "-----------" "----------------" "---"
    
    for env in "${envs[@]}"; do
        local repo=$(grep "repository:" "$CHART_DIR/values-${env}.yaml" | head -1 | awk '{print $2}')
        local tag=$(grep "tag:" "$CHART_DIR/values-${env}.yaml" | head -1 | awk '{print $2}' | tr -d '"')
        printf "%-15s %-60s %-20s\n" "$env" "$repo" "$tag"
    done
    
    echo ""
    print_warning "Different image versions may have different configuration parsing behavior"
}

# Function to check for Helm values differences
check_values_differences() {
    print_header "Checking dashboardStatistics values differences"
    
    local envs=("dev" "qa" "prod")
    
    for env in "${envs[@]}"; do
        echo ""
        echo "=== $env environment ==="
        grep -A 10 "^dashboardStatistics:" "$CHART_DIR/values-${env}.yaml" || echo "dashboardStatistics section not found"
    done
}

# Function to generate diagnostic report
generate_report() {
    local report_file="$TEMP_DIR/diagnostic-report.txt"
    
    print_header "Generating Diagnostic Report"
    
    {
        echo "MSR Helm Chart Configuration Diagnostics Report"
        echo "Generated: $(date)"
        echo "=============================================="
        echo ""
        
        echo "1. HELM VERSION"
        helm version
        echo ""
        
        echo "2. IMAGE VERSIONS"
        check_image_versions
        echo ""
        
        echo "3. DASHBOARD STATISTICS CONFIGURATION"
        check_values_differences
        echo ""
        
        echo "4. MONITOR.CNF VALIDATION RESULTS"
        for env in dev qa prod; do
            echo ""
            echo "--- $env ---"
            validate_monitor_cnf "$env" || true
        done
        echo ""
        
        echo "5. ENVIRONMENT COMPARISON"
        compare_environments
        echo ""
        
        echo "6. RECOMMENDATIONS"
        echo "==================="
        echo "- Ensure all environments use the same image version for consistency"
        echo "- Verify all required dashboardStatistics properties are defined in values files"
        echo "- Check Kubernetes cluster versions across environments"
        echo "- Review any custom admission controllers or policy engines in production"
        echo "- Validate ConfigMap size limits (1MB default in Kubernetes)"
        
    } | tee "$report_file"
    
    print_success "Report saved to: $report_file"
}

# Main execution
main() {
    local env="${1:-all}"
    
    print_header "MSR Helm Configuration Diagnostics"
    echo "Environment: $env"
    echo ""
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Check prerequisites
    check_helm
    
    if [ "$env" = "all" ]; then
        # Process all environments
        for e in dev qa prod; do
            render_template "$e" || continue
            extract_monitor_cnf "$e" || continue
            validate_monitor_cnf "$e" || continue
        done
        
        compare_environments
        check_image_versions
        generate_report
    else
        # Process single environment
        render_template "$env" || exit 1
        extract_monitor_cnf "$env" || exit 1
        validate_monitor_cnf "$env" || exit 1
    fi
    
    echo ""
    print_success "Diagnostics complete. Temp files in: $TEMP_DIR"
    echo ""
    echo "To clean up: rm -rf $TEMP_DIR"
}

# Run main function
main "$@"

# Made with Bob
