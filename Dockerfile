FROM steamcmd/steamcmd:ubuntu-24

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gettext-base \
        jq \
        libgcc-s1 \
        libicu74 \
        libssl3 \
        libstdc++6 \
        unzip \
        zlib1g \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/root \
    TZ=Asia/Shanghai \
    STEAM_APP_ID=1281930 \
    TML_INSTALL_DIR=/root/tmodloader \
    TML_DATA_DIR=/root/.local/share/Terraria/tModLoader \
    WORLD_DIR=/root/.local/share/Terraria/tModLoader/Worlds \
    MODS_DIR=/root/.local/share/Terraria/tModLoader/Mods \
    LOG_DIR=/root/logs

WORKDIR /root

COPY scripts/ /opt/terraria/scripts/

RUN chmod +x /opt/terraria/scripts/*.sh

EXPOSE 7777/tcp

ENTRYPOINT ["/opt/terraria/scripts/entrypoint.sh"]
