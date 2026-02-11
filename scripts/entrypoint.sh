#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

AUTO_UPDATE_ON_START="${AUTO_UPDATE_ON_START:-true}"
DEFAULT_TML_RELEASE_URL="https://github.com/tModLoader/tModLoader/releases/latest/download/tModLoader.zip"
TML_RELEASE_URL="${TML_RELEASE_URL:-$DEFAULT_TML_RELEASE_URL}"

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

update_tmodloader() {
  log "Updating tModLoader..."

  log "Downloading official release package: $TML_RELEASE_URL"
  local archive_path
  archive_path="/tmp/tmodloader-release.zip"

  rm -rf "$TML_INSTALL_DIR"
  mkdir -p "$TML_INSTALL_DIR"

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

  log "tModLoader installed from release package."
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
  wait "$SERVER_PID"
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
