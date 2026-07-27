#!/usr/bin/env bash
# create-gateway-target.sh — Creates the GitHub MCP gateway target.
#
# This lives outside Terraform because the AWS provider's create-waiter treats
# CREATE_PENDING_AUTH as an error. For an AUTHORIZATION_CODE target, that state
# is expected (no user has authorized yet) and the target works at runtime once
# a user completes the /connect flow.
#
# Run this ONCE after `terraform apply` on the gateway module.
# It is idempotent — if the target already exists it prints its status and exits.
#
# Usage:
#   ./scripts/create-gateway-target.sh
#
# Requires:
#   - AWS CLI v2 configured with appropriate credentials
#   - jq
#   - Terraform outputs from the gateway module (auto-read)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

# Read values from Terraform outputs
echo "Reading Terraform outputs..."
GATEWAY_ID=$(terraform -chdir="$TF_DIR" output -raw gateway_id)
CREDENTIAL_PROVIDER_ARN=$(terraform -chdir="$TF_DIR" output -raw github_credential_provider_arn 2>/dev/null || \
  terraform -chdir="${SCRIPT_DIR}/../../identity/terraform" output -raw github_credential_provider_arn)
OAUTH_CALLBACK_URL=$(terraform -chdir="$TF_DIR" output -raw oauth_callback_url 2>/dev/null || echo "")

REGION="${AWS_REGION:-us-west-2}"

if [[ -z "$GATEWAY_ID" ]]; then
  echo "ERROR: Could not read gateway_id from Terraform outputs. Run 'terraform apply' first."
  exit 1
fi

if [[ -z "$CREDENTIAL_PROVIDER_ARN" ]]; then
  echo "ERROR: Could not read github_credential_provider_arn. Deploy the identity module first."
  exit 1
fi

if [[ -z "$OAUTH_CALLBACK_URL" ]]; then
  echo "ERROR: oauth_callback_url not set. Check your tfvars."
  exit 1
fi

TARGET_NAME="github"

# Check if target already exists
echo "Checking for existing target '${TARGET_NAME}' on gateway ${GATEWAY_ID}..."
EXISTING=$(aws bedrock-agentcore-control list-gateway-targets \
  --gateway-identifier "$GATEWAY_ID" \
  --region "$REGION" \
  --query "items[?name=='${TARGET_NAME}'].{id:targetId,status:status}" \
  --output json 2>/dev/null || echo "[]")

if [[ "$EXISTING" != "[]" && "$EXISTING" != "" ]]; then
  TARGET_ID=$(echo "$EXISTING" | jq -r '.[0].id // empty')
  STATUS=$(echo "$EXISTING" | jq -r '.[0].status // empty')
  if [[ -n "$TARGET_ID" ]]; then
    echo "Target '${TARGET_NAME}' already exists: id=${TARGET_ID} status=${STATUS}"
    echo "Nothing to do."
    exit 0
  fi
fi

# Create the target
echo "Creating gateway target '${TARGET_NAME}'..."
RESPONSE=$(aws bedrock-agentcore-control create-gateway-target \
  --gateway-identifier "$GATEWAY_ID" \
  --name "$TARGET_NAME" \
  --region "$REGION" \
  --credential-provider-configurations "[{
    \"credentialProviderType\": \"OAUTH\",
    \"credentialProvider\": {
      \"oauthCredentialProvider\": {
        \"providerArn\": \"${CREDENTIAL_PROVIDER_ARN}\",
        \"scopes\": [\"repo\", \"read:org\", \"read:user\"],
        \"grantType\": \"AUTHORIZATION_CODE\",
        \"defaultReturnUrl\": \"${OAUTH_CALLBACK_URL}\"
      }
    }
  }]" \
  --target-configuration "{
    \"mcp\": {
      \"mcpServer\": {
        \"endpoint\": \"https://api.githubcopilot.com/mcp/\"
      }
    }
  }" \
  --output json)

TARGET_ID=$(echo "$RESPONSE" | jq -r '.targetId')
STATUS=$(echo "$RESPONSE" | jq -r '.status')

echo ""
echo "✓ Target created successfully."
echo "  Target ID:  ${TARGET_ID}"
echo "  Status:     ${STATUS}"
echo ""
echo "The target is in CREATE_PENDING_AUTH — this is normal."
echo "It will serve per-user requests once users authorize via /connect in Teams."
echo ""
echo "To check status later:"
echo "  aws bedrock-agentcore-control get-gateway-target \\"
echo "    --gateway-identifier ${GATEWAY_ID} --target-id ${TARGET_ID} \\"
echo "    --query 'status'"
