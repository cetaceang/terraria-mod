# Terraria + tModLoader Docker Server

## Current Behavior

- tModLoader server files are installed from GitHub release zip.
- Default URL is latest release, so you do **not** need to manually change version:
  - `https://github.com/tModLoader/tModLoader/releases/latest/download/tModLoader.zip`
- On each container start, tModLoader checks updates and downloads **only when version changes**.
- Mods are checked on each start and only changed Workshop items are downloaded.
- Local `.tmod` files in `./data/mods` are also loaded.

## Quick Start

1. Copy env file:

```bash
cp .env.example .env
```

2. Edit `.env` if needed (at least check `MOD_IDS`).

3. Build and start:

```bash
docker compose build --no-cache terraria
docker compose up -d
docker compose logs -f terraria
```

## Environment Variables

- `AUTO_UPDATE_ON_START` (default: `true`)
  - Whether to check tModLoader update on container start.
  - Download occurs only when release key changes.

- `TML_RELEASE_URL` (optional)
  - Override release URL.
  - Default is latest release URL above.
  - Use this only when pinning a specific version.

- `AUTO_DOWNLOAD_MODS` (default: `true`)
  - Check Workshop metadata and download only changed mods from `MOD_IDS`.

- `MOD_IDS`
  - Comma-separated Steam Workshop IDs.

- `CLEAN_OLD_MODS` (default: `true`)
  - Remove stale `.tmod` files not in current desired set.

## Data Paths

Host paths in this project:

- `./data/worlds`
- `./data/mods`
- `./data/logs`
- `./config/serverconfig.txt`

Container paths:

- `/root/.local/share/Terraria/tModLoader/Worlds`
- `/root/.local/share/Terraria/tModLoader/Mods`
- `/root/logs`
- `/root/.local/share/Terraria/tModLoader/serverconfig.txt`

## Optional: Pin a Specific tModLoader Version

Set in `.env`:

```env
TML_RELEASE_URL=https://github.com/tModLoader/tModLoader/releases/download/v2025.03.3.1/tModLoader.zip
```

## Troubleshooting

- If tModLoader install fails, verify outbound access to GitHub release URL.
- If mod download fails, verify outbound access to Steam and check `MOD_IDS` validity.
- If server fails to start, check `serverconfig.txt` mount path and file permissions.
- If startup exits with code `134`, this is usually native/.NET runtime dependency related. This image now installs common runtime libs and retries once with `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`.

## Sync State Files

- tModLoader release cache key: `/root/logs/.tml_release_state.json`
- Mod sync state: `/root/.local/share/Terraria/tModLoader/Mods/.mod_sync_state.json`

Inspect on server:

```bash
docker compose exec terraria bash -lc "cat /root/logs/.tml_release_state.json"
docker compose exec terraria bash -lc "cat /root/.local/share/Terraria/tModLoader/Mods/.mod_sync_state.json"
```

Force a full re-check by deleting state files and restarting:

```bash
docker compose exec terraria bash -lc "rm -f /root/logs/.tml_release_state.json /root/.local/share/Terraria/tModLoader/Mods/.mod_sync_state.json"
docker compose restart terraria
```
