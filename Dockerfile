FROM steamcmd/steamcmd:ubuntu-24

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gettext-base \
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

ENTRYPOINT ["/opt/terraria/scripts/entrypoint.sh"]
