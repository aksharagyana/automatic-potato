#!/usr/bin/env bash

connect_eks() {
    local config_path="$1"

    # 1. Check if a path was provided
    if [ -z "$config_path" ]; then
        echo "❌ Error: Please provide the path to your kubeconfig file."
        echo "Usage: connect_eks /path/to/your/kubeconfig"
        return 1
    fi

    # 2. Check if the file actually exists
    if [ ! -f "$config_path" ]; then
        echo "❌ Error: File not found at '$config_path'"
        return 1
    fi

    # 3. Export the path to the environment
    export KUBECONFIG="$config_path"
    echo "✅ KUBECONFIG exported to: $KUBECONFIG"

    # 4. Verify AWS identity (EKS requires active AWS credentials)
    echo "🔄 Verifying AWS identity..."
    if ! aws sts get-caller-identity --query "Arn" --output text; then
        echo "❌ Error: Failed to authenticate with AWS. Check your AWS CLI credentials/profile."
        return 1
    fi

    # 5. Verify cluster connection by listing namespaces
    echo "🔄 Connecting to cluster and fetching namespaces..."
    echo "--------------------------------------------------"
    if ! kubectl get ns; then
        echo "--------------------------------------------------"
        echo "❌ Error: Could not connect to the Kubernetes cluster."
        echo "Hints: Is your AWS user/role authorized in the cluster's aws-auth ConfigMap/Access Entries?"
        return 1
    fi
    echo "--------------------------------------------------"
    echo "🎉 Successfully connected to EKS cluster!"
}
