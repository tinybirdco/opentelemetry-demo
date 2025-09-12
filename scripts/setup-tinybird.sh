#!/bin/bash

# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

set -e

echo "Setting up Tinybird..."

# Save the current directory
ORIGINAL_DIR=$(pwd)

# Disable version warnings
export TB_VERSION_WARNING=0

# Install Tinybird CLI if not present
if ! command -v tb >/dev/null 2>&1; then
    echo "Installing Tinybird CLI..."
    curl https://tinybird.co | sh
fi

# Wait for Tinybird Local to be ready
echo "Waiting for Tinybird Local to be ready..."
until curl -s http://localhost:7181/ | grep -q "Tinybird Local"; do
    echo "Waiting for Tinybird Local..."
    sleep 3
done
echo "Tinybird Local is ready!"

rm -rf tinybird
echo "Creating tinybird directory and deploying Tinybird OTel Template..."
mkdir -p tinybird

echo "Deploying Tinybird OTel Template (this may take a few minutes)..."
# Try template deployment up to 20 times
deploy_success=false
for attempt in {1..20}; do
    echo "Tinybird OTel template deployment attempt $attempt/20..."
    if (cd tinybird && tb deploy --template https://github.com/tinybirdco/tinybird-otel-template/tree/main/); then
        echo "Tinybird OTel Template deployment successful!"
        deploy_success=true
        break
    else
        echo "Tinybird OTel Template deployment attempt $attempt failed, waiting 5 seconds..."
        sleep 5
    fi
done

if [ "$deploy_success" = false ]; then
    echo "Tinybird OTel Template deployment failed after 20 attempts, but continuing..."
    echo "You can manually deploy later with: cd tinybird && tb deploy --template https://github.com/tinybirdco/tinybird-otel-template/tree/main/"
fi


# Get admin token and workspace name
echo "Getting Tinybird admin token and workspace name..."

# Get the workspace name from tb workspace current
echo "Getting workspace name..."
WORKSPACE=$(cd tinybird && TB_VERSION_WARNING=0 tb workspace current 2>/dev/null | grep "name:" | awk '{print $2}')
echo "Workspace name: $WORKSPACE"

# Get the admin token using tb token ls
echo "Attempting to retrieve admin token..."
TOKEN=$(cd tinybird && TB_VERSION_WARNING=0 tb token ls 2>/dev/null | grep -A 3 "name: admin token" | grep "token:" | awk '{print $2}')

if [ -n "$TOKEN" ]; then
    echo "Successfully retrieved admin token"
    echo "Setting Tinybird environment variables in .env..."
    
    # Remove existing Tinybird variables from .env
    if [ -f .env ]; then
        echo "Removing existing Tinybird variables from .env..."
        sed -i.bak '/^OTEL_TINYBIRD_TOKEN_LOCAL=/d' .env
        sed -i.bak '/^OTEL_TINYBIRD_CLICKHOUSE_HOST_LOCAL=/d' .env
        sed -i.bak '/^OTEL_TINYBIRD_API_HOST_LOCAL=/d' .env
        sed -i.bak '/^OTEL_TINYBIRD_WORKSPACE_LOCAL=/d' .env
    fi
    
    # Add new environment variables
    echo "" >> .env
    echo "Adding new Tinybird variables to .env..."
    echo "OTEL_TINYBIRD_TOKEN_LOCAL=$TOKEN" >> .env
    echo "OTEL_TINYBIRD_CLICKHOUSE_HOST_LOCAL=tinybird_local" >> .env
    echo "OTEL_TINYBIRD_API_HOST_LOCAL=http://tinybird_local:7181" >> .env
    echo "OTEL_TINYBIRD_WORKSPACE_LOCAL=$WORKSPACE" >> .env
    
    echo "" >> .env
    echo "Restarting Grafana and OpenTelemetry Collector..."
    source .env
    docker-compose --env-file .env up grafana otel-collector --force-recreate --remove-orphans --detach || echo "Warning: Failed to restart services, but continuing..."
else
    echo "Warning: Could not retrieve Tinybird admin token"
    echo "This might be because the template wasn't deployed yet."
    echo ""
    echo "To fix this:"
    echo "1. Wait a few more minutes for Tinybird to be fully ready"
    echo "2. Manually deploy the template: cd tinybird && tb deploy --template https://github.com/tinybirdco/tinybird-otel-template/tree/main/"
    echo "3. Then run: tb token ls to get the admin token"
    echo "4. Set OTEL_TINYBIRD_TOKEN_LOCAL in your .env file"
    echo ""
fi
