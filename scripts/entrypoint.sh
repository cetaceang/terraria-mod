#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

AUTO_UPDATE_ON_START="${AUTO_UPDATE_ON_START:-true}"
DEFAULT_TML_RELEASE_URL="https://github.com/tModLoader/tModLoader/releases/latest/download/tModLoader.zip"
TML_RELEASE_URL="${TML_RELEASE_URL:-$DEFAULT_TML_RELEASE_URL}"
TML_RELEASE_STATE_PATH="${LOG_DIR}/.tml_release_state.json"

mkdir -p "$TML_INSTALL_DIR" "$TML_DATA_DIR" "$WORLD_DIR" "$MODS_DIR" "$LOG_DIR"

SERVER_CONFIG_DIR="$TML_DATA_DIR"
SERVER_CONFIG_PATH="$SERVER_CONFIG_DIR/serverconfig.txt"
SERVER_LOG_PATH="$LOG_DIR/server.log"

cleanup() {
  log "Received stop signal, shutting down server..."
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill -TERM "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" || true
  fi
  log "Server stopped."
}

trap cleanup SIGINT SIGTERM

validate_env() {
  if [[ ! -f "$SERVER_CONFIG_PATH" ]]; then
    log "Missing required config file: $SERVER_CONFIG_PATH"
    log "Please mount ./config/serverconfig.txt to $SERVER_CONFIG_PATH"
    exit 1
  fi
}

resolve_tml_release_key() {
  if [[ "$TML_RELEASE_URL" == "$DEFAULT_TML_RELEASE_URL" ]]; then
    local tag_name
    tag_name=$(curl -fsSL "https://api.github.com/repos/tModLoader/tModLoader/releases/latest" \
      | jq -r '.tag_name // empty' 2>/dev/null || true)
    if [[ -n "$tag_name" ]]; then
      echo "latest:${tag_name}"
      return 0
    fi
    log "Failed to resolve latest tag from GitHub API, fallback to URL key."
  fi

  echo "custom:${TML_RELEASE_URL}"
}

is_tml_installed() {
  if [[ -f "$TML_INSTALL_DIR/start-tModLoaderServer.sh" ]]; then
    return 0
  fi

  if find "$TML_INSTALL_DIR" -maxdepth 5 -type f \( -name "start-tModLoaderServer.sh" -o -name "tModLoaderServer*" \) | grep -q .; then
    return 0
  fi

  return 1
}

update_tmodloader() {
  log "Updating tModLoader..."

  local target_key current_key
  target_key="$(resolve_tml_release_key)"
  current_key=""

  if [[ -f "$TML_RELEASE_STATE_PATH" ]]; then
    current_key=$(jq -r '.release_key // empty' "$TML_RELEASE_STATE_PATH" 2>/dev/null || true)
  fi

  if [[ -n "$current_key" ]] && [[ "$current_key" == "$target_key" ]] && is_tml_installed; then
    log "tModLoader release unchanged ($target_key), skip download."
    return
  fi

  if [[ -n "$current_key" ]] && [[ "$current_key" == "$target_key" ]]; then
    log "Release key unchanged but installation missing, reinstalling."
  fi

  log "Downloading official release package: $TML_RELEASE_URL"
  local archive_path
  archive_path="/tmp/tmodloader-release.zip"

  rm -rf "${TML_INSTALL_DIR:?}"/*
  rm -rf "$TML_INSTALL_DIR"/.[!.]* 2>/dev/null || true

  curl -fL --retry 3 --retry-delay 2 "$TML_RELEASE_URL" -o "$archive_path"
  unzip -qo "$archive_path" -d "$TML_INSTALL_DIR"
  rm -f "$archive_path"

  if ! find "$TML_INSTALL_DIR" -maxdepth 5 -type f \( -name "start-tModLoaderServer.sh" -o -name "tModLoaderServer*" \) | grep -q .; then
    log "tModLoader install verification failed: server binary/script not found under $TML_INSTALL_DIR"
    log "Downloaded release package does not contain server binaries."
    log "Contents:"
    find "$TML_INSTALL_DIR" -maxdepth 4 -ls 2>/dev/null || true
    exit 1
  fi

  local state_tmp
  state_tmp="${TML_RELEASE_STATE_PATH}.tmp"
  jq -n --arg key "$target_key" --arg url "$TML_RELEASE_URL" --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{release_key:$key, release_url:$url, updated_at:$updated_at}' > "$state_tmp"
  mv -f "$state_tmp" "$TML_RELEASE_STATE_PATH"

  log "tModLoader installed from release package ($target_key)."
}

start_server() {
  local server_bin
  if [[ -f "$TML_INSTALL_DIR/start-tModLoaderServer.sh" ]]; then
    server_bin="$TML_INSTALL_DIR/start-tModLoaderServer.sh"
  elif [[ -f "$TML_INSTALL_DIR/steamapps/common/tModLoader/start-tModLoaderServer.sh" ]]; then
    server_bin="$TML_INSTALL_DIR/steamapps/common/tModLoader/start-tModLoaderServer.sh"
  else
    server_bin=$(find "$TML_INSTALL_DIR" -name "start-tModLoaderServer.sh" -type f 2>/dev/null | head -1)
  fi

  if [[ -z "$server_bin" ]]; then
    log "start-tModLoaderServer.sh not found under $TML_INSTALL_DIR"
    log "Contents:"
    find "$TML_INSTALL_DIR" -maxdepth 3 -ls 2>/dev/null || true
    exit 1
  fi
  chmod +x "$server_bin"

  log "Starting tModLoader server using $server_bin"
  "$server_bin" -config "$SERVER_CONFIG_PATH" > >(tee -a "$SERVER_LOG_PATH") 2>&1 &
  SERVER_PID=$!

  local rc=0
  wait "$SERVER_PID" || rc=$?

  if [[ "$rc" -eq 134 ]]; then
    log "Server exited with code 134 (abort). Printing launch logs for diagnosis..."
    if [[ -f "$TML_INSTALL_DIR/tModLoader-Logs/Launch.log" ]]; then
      tail -n 200 "$TML_INSTALL_DIR/tModLoader-Logs/Launch.log" || true
    fi

    log "Retrying once with DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1"
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
      "$server_bin" -config "$SERVER_CONFIG_PATH" > >(tee -a "$SERVER_LOG_PATH") 2>&1 &
    SERVER_PID=$!
    rc=0
    wait "$SERVER_PID" || rc=$?
  fi

  return "$rc"
}

main() {
  log "Bootstrap starting..."
  validate_env

  if [[ "$AUTO_UPDATE_ON_START" == "true" ]]; then
    update_tmodloader
  else
    log "AUTO_UPDATE_ON_START=false, skip tModLoader update."
  fi

  /opt/terraria/scripts/update_mods.sh
  start_server
}

main "$@"
