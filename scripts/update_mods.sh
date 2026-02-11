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
FAILURES=()
declare -A desired_files=()

mkdir -p "$MODS_DIR"

if [[ "$AUTO_DOWNLOAD_MODS" == "true" ]]; then
  IFS=',' read -r -a raw_ids <<< "$MOD_IDS_RAW"
  declare -A uniq=()
  declare -a mod_ids=()

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

  download_mod() {
    local mod_id="$1"
    /usr/games/steamcmd \
      +login anonymous \
      +workshop_download_item 1281930 "$mod_id" validate \
      +quit >/tmp/steamcmd_mod_${mod_id}.log 2>&1

    local workshop_dir="$HOME/.local/share/Steam/steamapps/workshop/content/1281930/$mod_id"
    if [[ ! -d "$workshop_dir" ]]; then
      log "Workshop dir not found for mod $mod_id"
      log "steamcmd output:"
      cat /tmp/steamcmd_mod_${mod_id}.log 2>/dev/null || true
      return 1
    fi

    local copied=0
    shopt -s nullglob

    local search_dir="$workshop_dir"
    local latest_sub
    latest_sub=$(ls -d "$workshop_dir"/[0-9]* 2>/dev/null | sort -t. -k1,1n -k2,2n | tail -1)
    if [[ -n "$latest_sub" ]]; then
      search_dir="$latest_sub"
    fi

    local tmod_file
    for tmod_file in "$search_dir"/*.tmod; do
      local filename
      filename="$(basename "$tmod_file")"
      cp -f "$tmod_file" "$MODS_DIR/$filename"
      desired_files["$filename"]=1
      copied=1
    done
    shopt -u nullglob

    if [[ "$copied" -ne 1 ]]; then
      log "No .tmod file found in $workshop_dir, contents:"
      ls -laR "$workshop_dir" 2>/dev/null || true
      return 1
    fi

    return 0
  }

  if [[ ${#mod_ids[@]} -gt 0 ]]; then
    log "Syncing ${#mod_ids[@]} mod(s): ${mod_ids[*]}"
    for mod_id in "${mod_ids[@]}"; do
      if retry 3 download_mod "$mod_id"; then
        log "Downloaded mod $mod_id"
      else
        FAILURES+=("$mod_id")
        log "Failed to download mod $mod_id after retries"
      fi
    done

    if [[ ${#FAILURES[@]} -gt 0 ]]; then
      log "Failed MOD_IDS: ${FAILURES[*]}"
      exit 1
    fi
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
