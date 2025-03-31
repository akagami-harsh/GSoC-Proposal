#!/usr/bin/env bash
# Test SeaweedFS S3 functionality with AWS CLI
# This script will:
# 1. Port-forward the S3 service
# 2. Configure AWS CLI profile
# 3. Create a test bucket
# 4. Upload a file
# 5. List the bucket contents
# 6. Download the file
# 7. Clean up
set -e

echo "===== Testing SeaweedFS S3 with AWS CLI ====="

# Get credentials from secret
echo "Retrieving S3 credentials..."
ACCESS_KEY=$(kubectl -n kubeflow get secret seaweedfs-s3-credentials -o jsonpath='{.data.access_key}' | base64 -d)
SECRET_KEY=$(kubectl -n kubeflow get secret seaweedfs-s3-credentials -o jsonpath='{.data.secret_key}' | base64 -d)

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "Failed to retrieve credentials. Make sure the secret exists."
  exit 1
fi
echo "Credentials retrieved successfully"

# Start port-forwarding in the background
echo "Starting port-forward for S3 endpoint on localhost:8333"
kubectl -n kubeflow port-forward svc/seaweedfs-s3 8333:8333 &
PORT_FORWARD_PID=$!

# Make sure to kill the port-forward when the script exits
cleanup() {
  echo "Cleaning up resources..."
  # Delete test bucket and objects if they exist
  if aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 ls s3://test-bucket &>/dev/null; then
    echo "Removing test bucket and objects..."
    aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 rm s3://test-bucket --recursive || true
    aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 rb s3://test-bucket --force || true
  fi
  
  # Kill port-forward
  if [ -n "$PORT_FORWARD_PID" ]; then
    echo "Stopping port-forward process..."
    kill $PORT_FORWARD_PID || true
  fi
  echo "Cleanup completed"
}
trap cleanup EXIT INT TERM

# Wait for port-forwarding to be established
echo "Waiting for port-forward to be established..."
sleep 5

# Configure AWS CLI
echo "Configuring AWS CLI..."
aws configure set aws_access_key_id "$ACCESS_KEY" --profile seaweedfs
aws configure set aws_secret_access_key "$SECRET_KEY" --profile seaweedfs
aws configure set region us-east-1 --profile seaweedfs

# Test S3 API
echo "Testing S3 API..."

# Create a test bucket
echo "Creating test bucket..."
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 mb s3://test-bucket

# Create a test file
echo "Hello SeaweedFS S3" > test-file.txt

# Upload the file
echo "Uploading test file..."
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 cp test-file.txt s3://test-bucket/

# List bucket contents
echo "Listing bucket contents:"
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 ls s3://test-bucket/

# Download the file
echo "Downloading test file..."
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 cp s3://test-bucket/test-file.txt test-file-downloaded.txt

# Verify download
if cmp -s test-file.txt test-file-downloaded.txt; then
  echo "SUCCESS: Downloaded file matches the original file"
else
  echo "ERROR: Downloaded file does not match the original file"
  exit 1
fi

# Clean up local files
rm -f test-file.txt test-file-downloaded.txt

echo "===== All tests passed! SeaweedFS S3 is working correctly ====="