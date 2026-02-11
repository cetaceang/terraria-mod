# Terraria + tModLoader (Calamity) Docker 自建服

本项目用于在 Ubuntu 主机上，以你自己构建的镜像部署 tModLoader 模组服务器（含灾厄）。

## 1. 前置条件

- 主机架构：`amd64`
- 已安装 Docker Engine
- 已安装 Docker Compose 插件（`docker compose`）

检查：

```bash
docker --version
docker compose version
```

## 2. 项目结构

```text
.
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── config/
│   └── serverconfig.txt
└── scripts/
    ├── entrypoint.sh
    └── update_mods.sh
```

## 3. 快速开始

1) 复制环境变量模板：

```bash
cp .env.example .env
```

2) 编辑 `.env`，至少确认：

- `MOD_IDS`：填入你要加载的 Steam Workshop 模组 ID（逗号分隔，包含灾厄相关）

3) 按需编辑 `config/serverconfig.txt`（端口/密码/世界名等都在这里）

4) 构建并启动：

```bash
docker compose build
docker compose up -d
```

5) 查看日志：

```bash
docker compose logs -f terraria
```

## 4. 配置方式说明

- `serverconfig.txt` 通过卷挂载：
  - `./config/serverconfig.txt` -> `/home/terraria/.local/share/Terraria/tModLoader/serverconfig.txt`
- 容器不再根据环境变量生成该文件。
- 你可以直接在宿主机编辑 `config/serverconfig.txt` 并重启容器生效。

## 5. 环境变量说明

- `TZ`：时区（默认 `Asia/Shanghai`）
- `MOD_IDS`：Steam Workshop 模组 ID 列表
- `AUTO_UPDATE_ON_START`：容器启动时自动更新 tModLoader（默认 `true`）
- `CLEAN_OLD_MODS`：是否清理不在 `MOD_IDS` 列表中的旧模组文件（默认 `true`）

### 5.1 当前模组与 ID 对照

- `Calamity Mod (灾厄本体)`：`2824688072`
- `Calamity Music (灾厄音乐)`：`2824688266`
- `灾厄Mod-汉化补丁`：`2825151264`
- `Magic Storage (魔法存储)`：`2563344837`
- `AbsoluteAquarian Utilities`：`2908170107`
- `AlchemistNPC Lite (炼金NPC)`：`2599842771`
- `Quality of Terraria (更好的体验)`：`2797518634`
- `Recipe Browser (合成表)`：`2619954303`
- `Boss Checklist (Boss清单)`：`2669644269`

## 6. 公网开放（最小示例）

如你使用 UFW：

```bash
sudo ufw allow 22/tcp
sudo ufw allow 7777/tcp
sudo ufw status
```

同时确保云服务器安全组/路由器转发已放行 `7777/tcp`。

## 7. 常用运维命令

重启服务：

```bash
docker compose restart terraria
```

停止服务：

```bash
docker compose down
```

查看容器健康状态：

```bash
docker inspect --format='{{json .State.Health}}' terraria-tmodloader
```

## 8. 升级策略

### 默认自动更新（当前默认）

- `AUTO_UPDATE_ON_START=true`
- 每次容器重启会拉取最新 tModLoader，并同步 `MOD_IDS` 对应模组

### 临时冻结（避免新版本兼容波动）

将 `.env` 改为：

```env
AUTO_UPDATE_ON_START=false
```

然后重启容器：

```bash
docker compose up -d
```

## 9. 故障排查

### 9.1 容器提示缺少 serverconfig

- 确认宿主机存在 `./config/serverconfig.txt`
- 确认 `docker-compose.yml` 中挂载路径未改错

### 9.2 模组下载失败

- 检查 `MOD_IDS` 是否为纯数字 ID
- 检查网络是否可访问 Steam
- 查看日志中的失败 ID：

```bash
docker compose logs --tail=200 terraria
```

### 9.3 客户端提示版本不匹配

- 客户端 tModLoader 版本与服务端不一致
- 客户端模组版本与服务端不一致
- 如需稳定，先冻结服务端更新并统一客户端版本

### 9.4 权限问题

- 确保 `./data/worlds`, `./data/mods`, `./data/logs`, `./config/serverconfig.txt` 对容器用户可读写

## 10. 数据持久化与备份边界

本项目**不实现备份脚本/定时任务**。你的外部备份方案应覆盖：

- `./data/worlds`
- `./data/mods`
- `./data/logs`
- `./config/serverconfig.txt`

恢复时，停止容器后还原上述数据，再重新启动容器。
