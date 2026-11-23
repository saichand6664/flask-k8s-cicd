#!/usr/bin/env bash
# Triggers a parameterized Jenkins job and waits for the result.
set -euo pipefail

AUTH="${JENKINS_USER}:${JENKINS_TOKEN}"
JOB_URL="${JENKINS_URL%/}/job/${JENKINS_JOB}"

echo "▶ Triggering ${JOB_URL} for ${GIT_BRANCH}@${GIT_SHA}"

# 1. Trigger the build; Jenkins returns the queue item URL in the Location header
RESP=$(curl -s -i -X POST -u "$AUTH" \
  "${JOB_URL}/buildWithParameters" \
  --data-urlencode "GIT_SHA=${GIT_SHA}" \
  --data-urlencode "GIT_BRANCH=${GIT_BRANCH}" || true)
CODE=$(echo "$RESP" | head -n1 | awk '{print $2}')
QUEUE_URL=$(echo "$RESP" | grep -i '^location:' | awk '{print $2}' | tr -d '\r' || true)

if [[ -z "$QUEUE_URL" ]]; then
  echo "✖ Jenkins did not queue the build. HTTP code: ${CODE:-none (could not connect)}"
  case "$CODE" in
    401) echo "  -> JENKINS_USER / JENKINS_TOKEN wrong" ;;
    403) echo "  -> user lacks permission (or token not accepted)" ;;
    404) echo "  -> job '${JENKINS_JOB}' not found at ${JENKINS_URL}" ;;
    "")  echo "  -> cannot reach ${JENKINS_URL} (check URL / port)" ;;
  esac
  echo "  Debug: URL length=${#JENKINS_URL}, job length=${#JENKINS_JOB}, user length=${#JENKINS_USER}"
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
  [[ "$BUILDING" == "false" ]] && break
  echo "  ...still building"
  sleep 10
done

echo "──── Jenkins console (last 40 lines) ────"
curl -s -u "$AUTH" "${BUILD_URL}consoleText" | tail -n 40
echo "─────────────────────────────────────────"
echo "Result: ${RESULT}"
[[ "$RESULT" == "SUCCESS" ]] || exit 1
