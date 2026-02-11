FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        gettext-base \
        lib32gcc-s1 \
        lib32stdc++6 \
        libc6-i386 \
        steamcmd \
        unzip \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 -s /bin/bash terraria

ENV HOME=/home/terraria \
    TZ=Asia/Shanghai \
    STEAM_APP_ID=1281930 \
    TML_INSTALL_DIR=/home/terraria/tmodloader \
    TML_DATA_DIR=/home/terraria/.local/share/Terraria/tModLoader \
    WORLD_DIR=/home/terraria/.local/share/Terraria/tModLoader/Worlds \
    MODS_DIR=/home/terraria/.local/share/Terraria/tModLoader/Mods \
    LOG_DIR=/home/terraria/logs

WORKDIR /home/terraria

COPY --chown=terraria:terraria scripts/ /opt/terraria/scripts/

RUN chmod +x /opt/terraria/scripts/*.sh

USER terraria

EXPOSE 7777/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD bash -lc 'pgrep -f "tModLoaderServer|start-tModLoaderServer.sh|TerrariaServer|dotnet" >/dev/null && test -f "$LOG_DIR/server.log" && test $(( $(date +%s) - $(stat -c %Y "$LOG_DIR/server.log") )) -lt 1800'

ENTRYPOINT ["/opt/terraria/scripts/entrypoint.sh"]
