#!/usr/bin/env bash

cdsConfigPath=${CDS_CONFIG_PATH:-"/config/cds.yaml"}
vhdsConfigPath=${VHDS_CONFIG_PATH:-"/config/vhds.yaml"}
statePath=${STATE_PATH:-"/config/state.yaml"}
updateInterval=${CONFIG_UPDATE_INTERVAL:-"10"}
tempDir=$(mktemp --directory)

initConfig() {
  mkdir -p "/config"
  cp /controller/bootstrap.yaml /config/bootstrap.yaml
  yq --null-input --output-format yaml '{"resources":[]}' >"$cdsConfigPath"
  yq --null-input --output-format yaml '{"resources":[]}' >"$vhdsConfigPath"
  touch /var/run/controller
}

getContainer() {
  local name="${1}"

  docker inspect "$name" --type container --format json | yq --indent 0 -M
}

getAnnotations() {
  local container="${1}"

  yq --output-format json --indent 0 -M -r '.[].HostConfig.Annotations // ""' <<<"$container"
}

getName() {
  local container="${1}"

  yq --indent 0 -M -r '.[].Name | sub("/"; "") // ""' <<<"$container"
}

getIpAddresses() {
  local container="${1}"

  yq --output-format json --indent 0 -M '[.[].NetworkSettings.Networks[].IPAddress]' <<<"$container"
}

updateConfig() {
  local annotations="${1}"
  local name="${2}"
  local configFile="${3}"
  local type="${4}"
  local action="${5}"
  local ipAddresses="${6}"

  pkl eval /controller/main.pkl \
    -p annotations="$annotations" \
    -p container="$name" \
    -p configFile="$configFile" \
    -p type="$type" \
    -p action="$action" \
    -p ipAddresses="$ipAddresses"
}

updateState() {
  local name="${1}"
  local annotations="${2}"

  yq ".${name}.annotations = ${annotations}" "$statePath"
}

triggerReload() {
  touch "/config/updated" && mv "/config/updated" "/config/trigger" && rm "/config/trigger"
}

main() {
  local containers

  containers=$(docker ps -q)
  yq --null-input --output-format yaml '{"resources":[]}' >"${cdsConfigPath}.temp"
  yq --null-input --output-format yaml '{"resources":[]}' >"${vhdsConfigPath}.temp"

  for c in $containers; do
    local annotations name containerJson
    local compose_gateway_org_enabled=""

    containerJson=$(getContainer "$c")
    annotations=$(getAnnotations "$containerJson")
    addresses=$(getIpAddresses "$containerJson")

    compose_gateway_org_enabled=$(yq '."compose.gateway.org/enabled"' --input-format json <<<"$annotations")

    if [[ "$compose_gateway_org_enabled" == "true" ]]; then
      name=$(getName "$containerJson")
      # echo "Exposing container $name"

      updateConfig "$annotations" "$name" "${cdsConfigPath}.temp" "cds" "add" "$addresses" >"${cdsConfigPath}.updated"
      cp "${cdsConfigPath}.updated" "${cdsConfigPath}.temp"

      updateConfig "$annotations" "$name" "${vhdsConfigPath}.temp" "vhds" "add" >"${vhdsConfigPath}.updated"
      cp "${vhdsConfigPath}.updated" "${vhdsConfigPath}.temp"
    fi
  done

  diff -q "${cdsConfigPath}.temp" "$cdsConfigPath" || mv "${cdsConfigPath}.temp" "$cdsConfigPath"
  diff -q "${vhdsConfigPath}.temp" "$vhdsConfigPath" || mv "${vhdsConfigPath}.temp" "$vhdsConfigPath"
}

echo "Initialising..."
initConfig

echo "Starting main loop..."
while true; do
  main
  sleep "$updateInterval"
done

# [[ -n $annotations && -n $name && (-n $currentCdsConfig || -n $currentVhdsConfig) ]] && config=$(generate "$annotations" "$name")
# [[ -n $config ]] && echo "CLUSTERS:"

# patchCds=$(yq '.clusters' --output-format json --indent 0 --no-colors <<<"$config")
# patchRds=$(yq '.routes' --output-format json --indent 0 --no-colors <<<"$config")
# patchVhds=$(yq '.virtual_hosts' --output-format json --indent 0 --no-colors <<<"$config")
# echo $config | yq -pj -oy
# echo $currentVhds
# yq ". += $patchCds" "$cds_config_path"
# yq --inplace ". + $patchCds" "$cds_config_path"
# yq --inplace ". + $patchVhds" "$vhds_config_path"
# yq ". += $patchCds" "$cds_config_path"
# yq -n "$currentRds + $patchRds"
# yq '.clusters' --input-format json --output-format json -I0 --no-colors <<<"$config"
# yq '.routes' --input-format json --output-format json -I0 --no-colors <<<"$config"
