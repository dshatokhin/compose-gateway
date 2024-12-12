#!/usr/bin/env bash

outputFile="resources.yaml"
pklFile="main.pkl"
tempDir=$(mktemp -d)
configDir=${COMPOSE_GATEWAY_CONFIG_DIR:-"/config"}
interval=${COMPOSE_GATEWAY_UPDATE_INTERVAL:-"5"}

# creates an empty output file
touch "${tempDir}/${outputFile}"

# creates default config file
pkl eval "$pklFile" -p init=true -m "$configDir"

info() {
  echo "INFO: $*"
}

error() {
  echo "ERROR: $*"
} >&2

getAllContainers() {
  local ids containers

  ids=$(docker ps -q)
  containers=$(docker inspect $ids)

  if echo "$containers" | yq --exit-status >/dev/null; then
    echo "$containers"
  else
    echo "[]"
    error "Failed to parse containers JSON object"
  fi
}

generateGatewayResources() {
  local payload=${1}

  pkl eval "$pklFile" -p payload="$payload" -p file="$outputFile" -m "$tempDir" >/dev/null
  if ! diff -q "${tempDir}/${outputFile}" "${configDir}/${outputFile}" &>/dev/null; then
    info "Changes in config detected, applying now..."
    cp "${tempDir}/${outputFile}" "${configDir}/${outputFile}"
  fi
}

exit=0
trap exiting SIGINT

exiting() {
  echo ""
  echo "Exiting main loop"
  exit=1
}

info "Starting main loop"
while [ $exit -eq 0 ]; do
  generateGatewayResources "$(getAllContainers)"
  sleep "$interval"
done
