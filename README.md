# Terraria + tModLoader Docker Server

## Current Behavior

- tModLoader server files are installed from GitHub release zip.
- Default URL is latest release, so you do **not** need to manually change version:
  - `https://github.com/tModLoader/tModLoader/releases/latest/download/tModLoader.zip`
- Mods are auto-downloaded from Steam Workshop by default.
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
  - Whether to download/update tModLoader on container start.

- `TML_RELEASE_URL` (optional)
  - Override release URL.
  - Default is latest release URL above.
  - Use this only when pinning a specific version.

- `AUTO_DOWNLOAD_MODS` (default: `true`)
  - Auto-download Workshop mods from `MOD_IDS`.

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
