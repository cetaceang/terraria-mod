#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

AUTO_UPDATE_ON_START="${AUTO_UPDATE_ON_START:-true}"
MOD_IDS="${MOD_IDS:-}"

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
  if [[ -z "$MOD_IDS" ]]; then
    log "Warning: MOD_IDS is empty. Server will start without workshop mod sync."
  fi

  if [[ ! -f "$SERVER_CONFIG_PATH" ]]; then
    log "Missing required config file: $SERVER_CONFIG_PATH"
    log "Please mount ./config/serverconfig.txt to $SERVER_CONFIG_PATH"
    exit 1
  fi
}

update_tmodloader() {
  log "Updating tModLoader via SteamCMD (app ${STEAM_APP_ID})..."
  /usr/games/steamcmd \
    +force_install_dir "$TML_INSTALL_DIR" \
    +login anonymous \
    +app_update "$STEAM_APP_ID" validate \
    +quit
}

find_server_binary() {
  local candidates=(
    "$TML_INSTALL_DIR/start-tModLoaderServer.sh"
    "$TML_INSTALL_DIR/start-tModLoaderServer"
    "$TML_INSTALL_DIR/tModLoaderServer"
  )

  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      echo "$path"
      return 0
    fi
  done

  local discovered
  discovered="$(find "$TML_INSTALL_DIR" -maxdepth 2 -type f \( -name 'start-tModLoaderServer.sh' -o -name 'tModLoaderServer' \) | head -n 1 || true)"
  if [[ -n "$discovered" ]]; then
    chmod +x "$discovered" || true
    echo "$discovered"
    return 0
  fi

  return 1
}

start_server() {
  local server_bin
  if ! server_bin="$(find_server_binary)"; then
    log "Could not find tModLoader server startup script in $TML_INSTALL_DIR"
    exit 1
  fi

  chmod +x "$server_bin" || true

  log "Starting tModLoader server using $server_bin"
  if [[ "$server_bin" == *.sh ]]; then
    bash "$server_bin" -config "$SERVER_CONFIG_PATH" > >(tee -a "$SERVER_LOG_PATH") 2>&1 &
  else
    "$server_bin" -config "$SERVER_CONFIG_PATH" > >(tee -a "$SERVER_LOG_PATH") 2>&1 &
  fi
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

  /opt/terraria/scripts/update_mods.sh "$MOD_IDS"
  start_server
}

main "$@"
