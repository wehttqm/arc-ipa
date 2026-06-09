#!/bin/bash
set -e

PROJECT_NAME="$1"
REGION="$2"
REPO_NAME="$3"
IMAGE_TAG="$4"
REPO_URL="$5"

echo "Starting CodeBuild project: $PROJECT_NAME"
BUILD_ID=$(aws codebuild start-build \
  --project-name "$PROJECT_NAME" \
  --region "$REGION" \
  --query 'build.id' \
  --output text)

echo "Build started: $BUILD_ID"
echo "Waiting for build to complete..."

ATTEMPT=0
MAX_ATTEMPTS=60
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS=$(aws codebuild batch-get-builds \
    --ids "$BUILD_ID" \
    --region "$REGION" \
    --query 'builds[0].buildStatus' \
    --output text 2>/dev/null)

  if [ "$STATUS" != "IN_PROGRESS" ]; then
    break
  fi
  sleep 10
done

if [ "$STATUS" != "SUCCEEDED" ]; then
  echo "ERROR: Build failed with status: $STATUS"
  exit 1
fi

# Verify image exists in ECR
sleep 5
if aws ecr describe-images \
  --repository-name "$REPO_NAME" \
  --image-ids imageTag="$IMAGE_TAG" \
  --region "$REGION" >/dev/null 2>&1; then
  echo "Image verified: $REPO_URL:$IMAGE_TAG"
else
  echo "ERROR: Image not found in ECR after build"
  exit 1
fi
