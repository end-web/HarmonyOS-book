# 简·欢音频源服务

服务端集中运行阅读音频书源，将搜索、书籍、章节和播放地址清洗成简·欢 App 使用的稳定接口。听友 FM
仍由 App 本地直连，本服务只作为第二个并行来源。

## 组成

- Express + TypeScript 标准 API
- SQLite WAL 缓存、来源版本和审计记录
- Reader/Legado 服务端音频规则引擎
- 免费听书王专有音频 API Provider（匿名会话、签名、令牌自动刷新）
- YCKCEO、AOAOSTAR、Yiove 网络目录每日同步
- Vue 3 运维后台
- Caddy HTTPS 入口

默认启用开放播客目录，LibriVox 公版音频目录保留为可选来源。阅读书源仅允许 `bookSourceType = 1`，
且只能由后台管理员导入。

“免费听书王”作为独立来源接入，不转换成 Legado JSON。服务器仅在配置 `GUOWEI_SIGNING_KEY` 时首次启用，
签名值属于部署环境配置，不得提交到仓库。

## 调用结构

App 保留听友 FM 本地直连，同时注册 `jianhu_server` 云源。搜索时两路并发、独立失败并按
`sourceUrl + bookUrl` 去重；详情、目录和播放解析仍按结果所属来源分发。
云源仅负责路由，搜索结果的 `sourceName` 会返回实际命中的阅读音频源名称，App 封面角标不再统一显示
“简·欢云源”。

| 页面或流程 | 标准接口 | 主要数据表 |
| --- | --- | --- |
| App 聚合搜索、后台链路调试 | `GET /api/v1/audio-books/search` | `sources`、`books`、`cache_entries` |
| 书籍详情 | `GET /api/v1/audio-books/:id` | `books` |
| 章节目录 | `GET /api/v1/audio-books/:id/chapters` | `books`、`chapters` |
| 播放和下载前解析 | `POST /api/v1/audio-chapters/:id/resolve` | `chapters`、`sources` |
| 来源管理和检测 | `/api/admin/sources` | `sources`、`source_versions`、`health_events` |
| 操作记录 | `GET /api/admin/logs` | `audit_logs` |

标准书籍字段为 `id/title/author/narrator/cover/intro/category/chapterCount/totalDuration`；章节字段为
`id/bookId/title/index/duration`；播放解析返回 `url/headers/format/expiresAt`。App 不接收阅读规则 JSON，
也不执行服务器规则。

## 本地开发

```bash
npm install
npm --prefix admin install
npm run typecheck
npm test
npm run admin:build
```

生成后台密码哈希：

```bash
node -e "const{randomBytes,scryptSync}=require('crypto');const p=process.argv[1],s=randomBytes(16).toString('base64url');console.log('scrypt$'+s+'$'+scryptSync(p,s,64).toString('base64url'))" "change-this-password"
```

复制 `deploy/.env.example` 为 `deploy/.env`，填入密码哈希和随机 `SESSION_SECRET`。
如已获得该 API 的合法接入授权，再填写 `GUOWEI_SIGNING_KEY`；未填写时来源会保留为停用状态。

## Docker 部署

```bash
cd deploy
docker compose -f compose.yml up -d --build
docker compose -f compose.yml ps
curl https://121.196.223.85/api/v1/health
```

当前入口为 Let's Encrypt 短期 IP 证书，Caddy 会自动续期；绑定自有域名后可直接替换为域名证书。Reader
和 API 均只在 Docker 内网暴露，公网仅开放 80/443。不要把 Reader 原始 `/reader3` 接口映射到公网。

## App 接口

- `GET /api/v1/audio-books/search?q=Alice&page=1`
- `GET /api/v1/audio-books/:id`
- `GET /api/v1/audio-books/:id/chapters`
- `POST /api/v1/audio-chapters/:id/resolve`
- `GET /api/v1/health`

所有响应使用 `{ code, data, requestId, serverTime }` 包络。聚合搜索按来源独立超时，单个来源失败时返回
其他来源结果，并通过 `partial` 标记部分失败。

## 运维

- 后台：`/admin/`
- 来源导入默认不启用，检测通过后再启用。
- 服务启动 20 秒后执行一次网络目录同步，之后每天北京时间 04:20 自动更新。
- 自动目录只保留 `bookSourceType = 1`，按 `bookSourceUrl` 去重；规则未变化时不重复创建版本。
- 新来源先保持停用，再按每日检测预算自动启用搜索、章节和首章解析均通过的来源；人工启用状态不会被后续同步覆盖。
- Yiove 官方接口单页最多 100 条，服务端会自动抓取前两页，对应网页的 `page_size=200`。
- 三个目录独立记录成功或失败，一个目录被 Cloudflare 或上游故障拦截时不会影响另外两个目录。
- 目录文件下载默认允许 120 秒，适配 AOAOSTAR 的大合集；可通过 `SOURCE_SYNC_FETCH_TIMEOUT_MS` 调整。
- 播放地址按需解析，不代理或持久化音频文件。
- `deploy/backup.sh` 使用 SQLite 在线快照备份数据库和 Reader 配置，默认保留 14 天。
- 生产服务器每天 03:17 执行一次备份，日志写入 `/var/log/jianhu-backup.log`。
- 升级 Reader 前固定镜像摘要并在测试来源上执行搜索、目录和播放解析，不使用无人值守自动更新。
