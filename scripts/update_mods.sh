#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [mods] $*"
}

retry() {
  local attempts=$1
  shift
  local count=1
  until "$@"; do
    if (( count >= attempts )); then
      return 1
    fi
    count=$((count + 1))
    sleep 2
  done
}

AUTO_DOWNLOAD_MODS="${AUTO_DOWNLOAD_MODS:-true}"
MOD_IDS_RAW="${MOD_IDS:-}"
CLEAN_OLD_MODS="${CLEAN_OLD_MODS:-true}"
STEAM_WORKSHOP_APP_ID="1281930"
MOD_SYNC_STATE_PATH="$MODS_DIR/.mod_sync_state.json"
FAILURES=()
declare -A desired_files=()

mkdir -p "$MODS_DIR"

parse_mod_ids() {
  IFS=',' read -r -a raw_ids <<< "$MOD_IDS_RAW"
  declare -A uniq=()
  mod_ids=()

  for id in "${raw_ids[@]}"; do
    id="${id//[[:space:]]/}"
    [[ -z "$id" ]] && continue
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
      log "Ignore invalid mod id: $id"
      continue
    fi
    if [[ -z "${uniq[$id]:-}" ]]; then
      uniq[$id]=1
      mod_ids+=("$id")
    fi
  done
}

load_state() {
  if [[ ! -f "$MOD_SYNC_STATE_PATH" ]]; then
    return
  fi

  local state_lines
  state_lines=$(jq -r '.mods // {} | to_entries[] | "\(.key)|\(.value.time_updated // 0)|\((.value.files // []) | join(","))"' "$MOD_SYNC_STATE_PATH" 2>/dev/null || true)
  if [[ -z "$state_lines" ]]; then
    return
  fi

  while IFS='|' read -r mod_id time_updated files_csv; do
    [[ -z "$mod_id" ]] && continue
    state_time_updated["$mod_id"]="$time_updated"
    state_files["$mod_id"]="$files_csv"
  done <<< "$state_lines"
}

fetch_remote_meta() {
  local payload
  payload="itemcount=${#mod_ids[@]}"
  for idx in "${!mod_ids[@]}"; do
    payload+="&publishedfileids[$idx]=${mod_ids[$idx]}"
  done

  remote_meta_json=$(curl -fsSL -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data "$payload" \
    "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" 2>/dev/null || true)

  if [[ -z "$remote_meta_json" ]]; then
    return 1
  fi

  local parsed
  parsed=$(printf '%s' "$remote_meta_json" | jq -r '.response.publishedfiledetails[]? | "\(.publishedfileid)|\(.time_updated // 0)"' 2>/dev/null || true)
  if [[ -z "$parsed" ]]; then
    return 1
  fi

  while IFS='|' read -r mod_id time_updated; do
    [[ -z "$mod_id" ]] && continue
    remote_time_updated["$mod_id"]="$time_updated"
  done <<< "$parsed"

  return 0
}

use_cached_mod() {
  local mod_id="$1"
  local cached_files_csv="${state_files[$mod_id]:-}"
  [[ -z "$cached_files_csv" ]] && return 1

  IFS=',' read -r -a cached_files <<< "$cached_files_csv"
  local file
  for file in "${cached_files[@]}"; do
    [[ -z "$file" ]] && continue
    if [[ ! -f "$MODS_DIR/$file" ]]; then
      return 1
    fi
  done

  for file in "${cached_files[@]}"; do
    [[ -z "$file" ]] && continue
    desired_files["$file"]=1
  done

  return 0
}

copy_mod_files_from_workshop() {
  local mod_id="$1"
  local workshop_dir="$HOME/.local/share/Steam/steamapps/workshop/content/${STEAM_WORKSHOP_APP_ID}/$mod_id"

  if [[ ! -d "$workshop_dir" ]]; then
    log "Workshop dir not found for mod $mod_id"
    return 1
  fi

  local search_dir="$workshop_dir"
  local latest_sub
  latest_sub=$(find "$workshop_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E '^[0-9]+(\.[0-9]+)*$' \
    | sort -V \
    | tail -1)
  if [[ -n "$latest_sub" ]]; then
    search_dir="$workshop_dir/$latest_sub"
    log "Using latest workshop subdir for $mod_id: $latest_sub"
  fi

  local copied=0
  local copied_list=()
  shopt -s nullglob

  local tmod_file
  for tmod_file in "$search_dir"/*.tmod; do
    local filename
    filename="$(basename "$tmod_file")"
    cp -f "$tmod_file" "$MODS_DIR/$filename"
    desired_files["$filename"]=1
    copied_list+=("$filename")
    copied=1
  done

  shopt -u nullglob

  if [[ "$copied" -ne 1 ]]; then
    log "No .tmod file found in $workshop_dir, contents:"
    ls -laR "$workshop_dir" 2>/dev/null || true
    return 1
  fi

  new_files_csv["$mod_id"]="$(IFS=','; echo "${copied_list[*]}")"
  return 0
}

download_mod() {
  local mod_id="$1"
  /usr/games/steamcmd \
    +login anonymous \
    +workshop_download_item "$STEAM_WORKSHOP_APP_ID" "$mod_id" validate \
    +quit >/tmp/steamcmd_mod_${mod_id}.log 2>&1

  copy_mod_files_from_workshop "$mod_id" || {
    log "steamcmd output:"
    cat /tmp/steamcmd_mod_${mod_id}.log 2>/dev/null || true
    return 1
  }

  return 0
}

write_state() {
  local state_tmp
  state_tmp="${MOD_SYNC_STATE_PATH}.tmp"

  {
    printf '{"updated_at":"%s","mods":{' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local first=1
    local mod_id
    for mod_id in "${mod_ids[@]}"; do
      local time_updated files_csv
      time_updated="${new_time_updated[$mod_id]:-${remote_time_updated[$mod_id]:-${state_time_updated[$mod_id]:0}}}"
      files_csv="${new_files_csv[$mod_id]:-${state_files[$mod_id]:-}}"

      if [[ "$first" -eq 0 ]]; then
        printf ','
      fi
      first=0

      printf '"%s":{' "$mod_id"
      printf '"time_updated":%s,' "$time_updated"
      printf '"files":['

      local first_file=1
      IFS=',' read -r -a files_arr <<< "$files_csv"
      local file
      for file in "${files_arr[@]}"; do
        [[ -z "$file" ]] && continue
        if [[ "$first_file" -eq 0 ]]; then
          printf ','
        fi
        first_file=0
        printf '"%s"' "$file"
      done

      printf ']}'
    done

    printf '}}\n'
  } > "$state_tmp"

  mv -f "$state_tmp" "$MOD_SYNC_STATE_PATH"
}

if [[ "$AUTO_DOWNLOAD_MODS" == "true" ]]; then
  parse_mod_ids

  if [[ ${#mod_ids[@]} -gt 0 ]]; then
    declare -A state_time_updated=()
    declare -A state_files=()
    declare -A remote_time_updated=()
    declare -A new_time_updated=()
    declare -A new_files_csv=()

    load_state

    local_meta_ok=false
    if fetch_remote_meta; then
      local_meta_ok=true
      log "Fetched workshop metadata for ${#mod_ids[@]} mod(s)."
    else
      log "Workshop metadata check failed, fallback to direct steamcmd sync."
    fi

    log "Syncing ${#mod_ids[@]} mod(s): ${mod_ids[*]}"
    for mod_id in "${mod_ids[@]}"; do
      if [[ "$local_meta_ok" == "true" ]]; then
        remote_time="${remote_time_updated[$mod_id]:0}"
        state_time="${state_time_updated[$mod_id]:-0}"

        if [[ "$remote_time" != "0" ]] && [[ "$remote_time" == "$state_time" ]] && use_cached_mod "$mod_id"; then
          log "No update for mod $mod_id, using cached files."
          new_time_updated["$mod_id"]="$state_time"
          new_files_csv["$mod_id"]="${state_files[$mod_id]:-}"
          continue
        fi
      fi

      if retry 3 download_mod "$mod_id"; then
        log "Downloaded mod $mod_id"
        if [[ "$local_meta_ok" == "true" ]]; then
          new_time_updated["$mod_id"]="${remote_time_updated[$mod_id]:0}"
        fi
      else
        FAILURES+=("$mod_id")
        log "Failed to download mod $mod_id after retries"
      fi
    done

    if [[ ${#FAILURES[@]} -gt 0 ]]; then
      log "Failed MOD_IDS: ${FAILURES[*]}"
      exit 1
    fi

    write_state
  else
    log "AUTO_DOWNLOAD_MODS=true but MOD_IDS is empty. Skip workshop sync."
  fi
else
  log "AUTO_DOWNLOAD_MODS=false. Using local .tmod files in $MODS_DIR"
fi

shopt -s nullglob
local_mods=("$MODS_DIR"/*.tmod)
shopt -u nullglob

if [[ ${#local_mods[@]} -eq 0 ]]; then
  log "No local .tmod files found under $MODS_DIR"
  log "Please place mod files into ./data/mods on host before starting."
fi

for modfile in "${local_mods[@]}"; do
  filename="$(basename "$modfile")"
  desired_files["$filename"]=1
done

if [[ "$CLEAN_OLD_MODS" == "true" ]]; then
  log "Cleaning old mods is enabled."
  shopt -s nullglob
  for modfile in "$MODS_DIR"/*.tmod; do
    name="$(basename "$modfile")"
    if [[ -z "${desired_files[$name]:-}" ]]; then
      rm -f "$modfile"
      log "Removed old mod file: $name"
    fi
  done
  shopt -u nullglob
fi

enabled_json="$MODS_DIR/enabled.json"
{
  printf '[\n'
  mod_names=()
  shopt -s nullglob
  for modfile in "$MODS_DIR"/*.tmod; do
    mod_names+=("$(basename "${modfile%.tmod}")")
  done
  shopt -u nullglob

  IFS=$'\n' mod_names=($(printf '%s\n' "${mod_names[@]}" | sort))

  for idx in "${!mod_names[@]}"; do
    name="${mod_names[$idx]}"
    if (( idx + 1 < ${#mod_names[@]} )); then
      printf '  "%s",\n' "$name"
    else
      printf '  "%s"\n' "$name"
    fi
  done
  printf ']\n'
} > "$enabled_json"

log "Wrote enabled mod list: $enabled_json"
log "Mod sync completed."
