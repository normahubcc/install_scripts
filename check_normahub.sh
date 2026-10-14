#!/usr/bin/env sh
# ==============================================================================
# NormaHub Network Connectivity & Gateway Health Diagnostic Script
# Usage: ./check_normahub.sh [OPTIONAL_API_KEY]
# ==============================================================================
set -eu

GATEWAY_HOST="api.normahub.cc"
BASE_URL="https://api.normahub.cc/v1"
API_KEY="${1:-${NORMAHUB_API_KEY:-}}"

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

printf '%b\n' "${CYAN}====================================================================${RESET}"
printf '%b\n' "${BOLD}NormaHub Network & API Gateway Diagnostic Tool${RESET}"
printf '%b\n' "Host: ${GATEWAY_HOST} | Gateway: ${BASE_URL}"
printf '%b\n' "${CYAN}====================================================================${RESET}\n"

# Check required commands
if ! command -v curl >/dev/null 2>&1; then
  printf '%b\n' "${RED}[✘] Error: 'curl' is required to run diagnostics.${RESET}" >&2
  exit 1
fi

ERRORS=0

# Step 1: DNS Resolution
printf '%b' "${BOLD}[1/4] DNS Resolution (${GATEWAY_HOST})... ${RESET}"
if command -v getent >/dev/null 2>&1; then
  RESOLVED_IP=$(getent hosts "$GATEWAY_HOST" 2>/dev/null | awk '{print $1}' | head -n 1 || true)
elif command -v nslookup >/dev/null 2>&1; then
  RESOLVED_IP=$(nslookup "$GATEWAY_HOST" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n 1 || true)
else
  RESOLVED_IP=""
fi

if [ -n "$RESOLVED_IP" ]; then
  printf '%b\n' "${GREEN}[OK] Resolved to ${RESOLVED_IP}${RESET}"
else
  printf '%b\n' "${YELLOW}[WARN] Could not inspect IP via getent/nslookup, testing via curl...${RESET}"
fi

# Step 2: TCP Connection & TLS Handshake Latency
printf '%b' "${BOLD}[2/4] TLS Handshake & Latency... ${RESET}"
TIMING=$(curl -s -o /dev/null -w "%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_total}|%{http_code}" --max-time 10 "${BASE_URL}/models" || true)

if [ -z "$TIMING" ]; then
  printf '%b\n' "${RED}[FAIL] Could not connect to ${BASE_URL}${RESET}"
  ERRORS=$((ERRORS + 1))
else
  DNS_T=$(printf '%s' "$TIMING" | cut -d'|' -f1)
  TCP_T=$(printf '%s' "$TIMING" | cut -d'|' -f2)
  TLS_T=$(printf '%s' "$TIMING" | cut -d'|' -f3)
  TOTAL_T=$(printf '%s' "$TIMING" | cut -d'|' -f4)
  HTTP_C=$(printf '%s' "$TIMING" | cut -d'|' -f5)

  printf '%b\n' "${GREEN}[OK]${RESET} DNS: ${DNS_T}s | TCP: ${TCP_T}s | TLS: ${TLS_T}s | Total: ${TOTAL_T}s (HTTP ${HTTP_C})"
fi

# Step 3: API Gateway HTTP Responsiveness
printf '%b' "${BOLD}[3/4] API Gateway HTTP Responsiveness... ${RESET}"
GATEWAY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE_URL}/models" || true)

if [ "$GATEWAY_STATUS" = "200" ] || [ "$GATEWAY_STATUS" = "401" ]; then
  printf '%b\n' "${GREEN}[OK] API Gateway online and serving requests (HTTP ${GATEWAY_STATUS})${RESET}"
else
  printf '%b\n' "${RED}[FAIL] Gateway returned unexpected status HTTP ${GATEWAY_STATUS}${RESET}"
  ERRORS=$((ERRORS + 1))
fi

# Step 4: API Key & Account Check (if provided)
printf '%b' "${BOLD}[4/4] Account & Authorization Authentication... ${RESET}"
if [ -n "$API_KEY" ]; then
  AUTH_HEADER="Authorization: Bearer ${API_KEY}"
  AUTH_RESP=$(curl -s -w "\n%{http_code}" --max-time 10 -H "$AUTH_HEADER" "${BASE_URL}/models" || true)
  AUTH_HTTP=$(printf '%s' "$AUTH_RESP" | tail -n 1)

  if [ "$AUTH_HTTP" = "200" ]; then
    printf '%b\n' "${GREEN}[OK] API Key is valid and authorized (HTTP 200)${RESET}"
  elif [ "$AUTH_HTTP" = "401" ]; then
    printf '%b\n' "${RED}[FAIL] Invalid API Key (HTTP 401 Unauthorized)${RESET}"
    ERRORS=$((ERRORS + 1))
  elif [ "$AUTH_HTTP" = "402" ]; then
    printf '%b\n' "${YELLOW}[WARN] Balance depleted (HTTP 402 Payment Required). Please top up on https://normahub.cc${RESET}"
  else
    printf '%b\n' "${YELLOW}[INFO] Gateway response HTTP ${AUTH_HTTP}${RESET}"
  fi
else
  printf '%b\n' "${CYAN}[SKIP] No API key provided. Pass as arg or set NORMAHUB_API_KEY to verify balance.${RESET}"
fi

# Final Summary
printf '\n%b\n' "${CYAN}--------------------------------------------------------------------${RESET}"
if [ "$ERRORS" -eq 0 ]; then
  printf '%b\n' "${GREEN}✔ All network diagnostics PASSED! Connection to NormaHub is optimal.${RESET}"
  printf '%b\n' "${BOLD}Platform dashboard:${RESET} https://normahub.cc/dashboard"
  exit 0
else
  printf '%b\n' "${RED}✘ Diagnostic finished with ${ERRORS} issue(s). Check network settings or VPN interference.${RESET}"
  exit 1
fi
