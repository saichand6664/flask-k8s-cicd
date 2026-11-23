#!/usr/bin/env bash
# Triggers a parameterized Jenkins job and waits for the result,
# so the GitHub Actions run goes green/red with the Jenkins build.
#
# Required env vars:
#   JENKINS_URL     e.g. http://localhost:8081
#   JENKINS_USER    Jenkins username
#   JENKINS_TOKEN   Jenkins API token (User > Security > API Token)
#   JENKINS_JOB     Jenkins job name, e.g. flask-k8s-pipeline
#   GIT_SHA         commit to build
#   GIT_BRANCH      branch name
set -euo pipefail

AUTH="${JENKINS_USER}:${JENKINS_TOKEN}"
JOB_URL="${JENKINS_URL%/}/job/${JENKINS_JOB}"

echo "▶ Triggering ${JOB_URL} for ${GIT_BRANCH}@${GIT_SHA}"

# 1. Trigger the build; Jenkins returns the queue item URL in the Location header
QUEUE_URL=$(curl -s -i -X POST -u "$AUTH" \
  "${JOB_URL}/buildWithParameters" \
  --data-urlencode "GIT_SHA=${GIT_SHA}" \
  --data-urlencode "GIT_BRANCH=${GIT_BRANCH}" \
  | grep -i '^location:' | awk '{print $2}' | tr -d '\r')

if [[ -z "$QUEUE_URL" ]]; then
  echo "✖ Failed to trigger Jenkins job (check URL, user, token, job name)"
  exit 1
fi
echo "  Queued: ${QUEUE_URL}"

# 2. Wait for the queue item to become a real build
BUILD_URL=""
for _ in $(seq 1 60); do
  BUILD_URL=$(curl -s -u "$AUTH" "${QUEUE_URL}api/json" | jq -r '.executable.url // empty')
  [[ -n "$BUILD_URL" ]] && break
  sleep 5
done
[[ -z "$BUILD_URL" ]] && { echo "✖ Build never left the queue"; exit 1; }
echo "  Build started: ${BUILD_URL}"

# 3. Poll until the build finishes
while true; do
  JSON=$(curl -s -u "$AUTH" "${BUILD_URL}api/json")
  BUILDING=$(echo "$JSON" | jq -r '.building')
  RESULT=$(echo "$JSON" | jq -r '.result')
  if [[ "$BUILDING" == "false" ]]; then
    break
  fi
  echo "  ...still building"
  sleep 10
done

echo "──── Jenkins console (last 40 lines) ────"
curl -s -u "$AUTH" "${BUILD_URL}consoleText" | tail -n 40
echo "─────────────────────────────────────────"

echo "Result: ${RESULT}"
[[ "$RESULT" == "SUCCESS" ]] || exit 1
