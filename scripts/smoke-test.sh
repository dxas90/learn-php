#!/bin/bash
set -e

echo "=== Running Smoke Tests ==="

# Get the service name
SERVICE_NAME="learn-php"
NAMESPACE="default"

echo "Checking if deployment exists..."
kubectl get deployment ${SERVICE_NAME} -n ${NAMESPACE}

echo "Checking if pods are running..."
PODS=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=learn-php --field-selector=status.phase=Running --no-headers | wc -l)
if [ "$PODS" -eq 0 ]; then
    echo "❌ No running pods found for ${SERVICE_NAME}"
    kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=learn-php
    exit 1
fi
echo "✅ Found $PODS running pod(s)"

echo "Checking if service exists..."
kubectl get service ${SERVICE_NAME} -n ${NAMESPACE}

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=learn-php -n ${NAMESPACE} --timeout=300s

echo "Checking pod health..."
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=learn-php -o jsonpath='{.items[0].metadata.name}')
echo "Using pod: $POD_NAME"

# Test health endpoint
echo "Testing health endpoint..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- wget -O- http://localhost:4567/healthz 2>/dev/null || {
    echo "❌ Health check failed with wget, trying curl..."
    # Fallback to curl
    kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -f http://localhost:4567/healthz || {
        echo "❌ Health check failed"
        exit 1
    }
}
echo "✅ Health endpoint responding"

echo "=== Smoke Tests Passed ==="
