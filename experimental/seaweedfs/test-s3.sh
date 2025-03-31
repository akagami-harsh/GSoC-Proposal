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

# Colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== Testing SeaweedFS S3 with AWS CLI =====${NC}"

# Get credentials from secret
echo -e "${YELLOW}Retrieving S3 credentials...${NC}"
ACCESS_KEY=$(kubectl -n kubeflow get secret seaweedfs-s3-credentials -o jsonpath='{.data.access_key}' | base64 -d)
SECRET_KEY=$(kubectl -n kubeflow get secret seaweedfs-s3-credentials -o jsonpath='{.data.secret_key}' | base64 -d)

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}Failed to retrieve credentials. Make sure the secret exists.${NC}"
    exit 1
fi

echo -e "${GREEN}Credentials retrieved successfully${NC}"

# Start port-forwarding in the background
echo -e "${YELLOW}Starting port-forward for S3 endpoint on localhost:8333${NC}"
kubectl -n kubeflow port-forward svc/seaweedfs-s3 8333:8333 &
PORT_FORWARD_PID=$!

# Make sure to kill the port-forward when the script exits
cleanup() {
    echo -e "${YELLOW}\nCleaning up resources...${NC}"
    
    # Delete test bucket and objects if they exist
    if aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 ls s3://test-bucket &>/dev/null; then
        echo -e "${YELLOW}Removing test bucket and objects...${NC}"
        aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 rm s3://test-bucket --recursive || true
        aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 rb s3://test-bucket --force || true
    fi
    
    # Kill port-forward
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo -e "${YELLOW}Stopping port-forward process...${NC}"
        kill $PORT_FORWARD_PID || true
    fi
    
    echo -e "${GREEN}Cleanup completed${NC}"
}

trap cleanup EXIT INT TERM

# Wait for port-forwarding to be established
echo -e "${YELLOW}Waiting for port-forward to be established...${NC}"
sleep 5

# Configure AWS CLI
echo -e "${YELLOW}Configuring AWS CLI...${NC}"
aws configure set aws_access_key_id "$ACCESS_KEY" --profile seaweedfs
aws configure set aws_secret_access_key "$SECRET_KEY" --profile seaweedfs
aws configure set region us-east-1 --profile seaweedfs

# Test S3 API
echo -e "${YELLOW}Testing S3 API...${NC}"

# Create a test bucket
echo -e "${YELLOW}Creating test bucket...${NC}"
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 mb s3://test-bucket

# Create a test file
echo "Hello SeaweedFS S3" > test-file.txt

# Upload the file
echo -e "${YELLOW}Uploading test file...${NC}"
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 cp test-file.txt s3://test-bucket/

# List bucket contents
echo -e "${YELLOW}Listing bucket contents:${NC}"
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 ls s3://test-bucket/

# Download the file
echo -e "${YELLOW}Downloading test file...${NC}"
aws --endpoint-url=http://localhost:8333 --profile seaweedfs s3 cp s3://test-bucket/test-file.txt test-file-downloaded.txt

# Verify download
if cmp -s test-file.txt test-file-downloaded.txt; then
    echo -e "${GREEN}SUCCESS: Downloaded file matches the original file${NC}"
else
    echo -e "${RED}ERROR: Downloaded file does not match the original file${NC}"
    exit 1
fi

# Clean up local files
rm -f test-file.txt test-file-downloaded.txt

echo -e "${GREEN}===== All tests passed! SeaweedFS S3 is working correctly =====${NC}" 