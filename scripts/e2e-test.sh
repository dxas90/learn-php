#!/bin/bash
set -e

echo "=== Running End-to-End Tests ==="

SERVICE_NAME="learn-php"
NAMESPACE="default"
SERVICE_PORT=4567

# Get pod name
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=learn-php -o jsonpath='{.items[0].metadata.name}')
echo "Testing pod: $POD_NAME"

echo "--- Test 1: Health Endpoint ---"
HEALTH_RESPONSE=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s http://localhost:${SERVICE_PORT}/healthz 2>&1) || {
    echo "❌ Health endpoint test failed"
    echo "Response: $HEALTH_RESPONSE"
    exit 1
}

if [[ "$HEALTH_RESPONSE" == *"healthy"* ]]; then
    echo "✅ Health endpoint test passed"
else
    echo "❌ Health endpoint test failed"
    echo "Response: $HEALTH_RESPONSE"
    exit 1
fi

echo "--- Test 2: Root Endpoint ---"
ROOT_RESPONSE=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- curl -s http://localhost:${SERVICE_PORT}/ 2>&1) || {
    echo "❌ Root endpoint test failed"
    exit 1
}

if [[ ! -z "$ROOT_RESPONSE" ]]; then
    echo "✅ Root endpoint test passed"
else
    echo "❌ Root endpoint test failed"
    exit 1
fi

echo "--- Test 3: Service Connectivity ---"
# Test that the service is accessible within the cluster
SERVICE_IP=$(kubectl get service ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')
echo "Service IP: $SERVICE_IP"

# Create a temporary pod to test service connectivity
kubectl run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n ${NAMESPACE} -- \
    curl -f -s http://${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local:${SERVICE_PORT}/healthz || {
    echo "❌ Service connectivity test failed"
    exit 1
}
echo "✅ Service connectivity test passed"

echo "--- Test 4: Pod Resilience ---"
INITIAL_POD_COUNT=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=learn-php --field-selector=status.phase=Running --no-headers | wc -l)
echo "Initial pod count: $INITIAL_POD_COUNT"

echo "Deleting a pod to test resilience..."
kubectl delete pod ${POD_NAME} -n ${NAMESPACE}

echo "Waiting for replacement pod to be ready..."
sleep 5
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=learn-php -n ${NAMESPACE} --timeout=120s

FINAL_POD_COUNT=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=learn-php --field-selector=status.phase=Running --no-headers | wc -l)
if [ "$FINAL_POD_COUNT" -eq "$INITIAL_POD_COUNT" ]; then
    echo "✅ Pod resilience test passed"
else
    echo "❌ Pod resilience test failed (Expected: $INITIAL_POD_COUNT, Got: $FINAL_POD_COUNT)"
    exit 1
fi

echo "--- Test 5: Resource Limits ---"
echo "Verifying resource limits are set..."
RESOURCE_LIMITS=$(kubectl get deployment ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources.limits}')
if [[ ! -z "$RESOURCE_LIMITS" ]]; then
    echo "✅ Resource limits configured: $RESOURCE_LIMITS"
else
    echo "⚠️  No resource limits configured"
fi

echo "=== All E2E Tests Passed ==="
