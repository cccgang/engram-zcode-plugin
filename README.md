# engram-zcode

[Engram](https://github.com/Gentleman-Programming/engram) 共享记忆系统的 [ZCode](https://z.ai) 插件：让 ZCode 与本机的其他 AI 编码代理（Codex 等）共用同一份本地持久记忆。

Windows 平台专用（钩子脚本为 PowerShell）。核心能力：

- **会话启动注入**：每次会话开始自动注入记忆协议全文 + 当前项目的近期记忆上下文
- **压缩后恢复**：上下文被 compact 后，注入标准的"先固化摘要、再恢复历史"恢复序列
- **会话绑定**：把宿主 session id 注册到本地 Engram 服务，写入操作归属到具体会话
- **写护栏**：对 `mem_*` 写类工具做 PreToolUse 检查，转发 Engram 的 allow/ask/deny 判定与会话改写
- **记忆 skill + MCP**：内置 `engram-memory` skill 与 Engram MCP server（`mem_*` 工具族）

## 工作原理

ZCode 支持 7 种钩子事件（`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PermissionRequest` / `PostToolUse` / `PostToolUseFailure` / `Stop`）。本插件用到其中两类：

| 钩子 | matcher | 脚本 | 作用 |
|---|---|---|---|
| SessionStart | `startup\|resume\|clear` | `scripts/session-start.ps1` | 注入 `protocol.md` 协议全文，并从 `GET /context?project=…` 拉取项目近期记忆 |
| SessionStart | `startup\|resume\|clear` | `scripts/bind-session.ps1` | `engram hook claude-bind-session` 绑定宿主会话 |
| SessionStart | `compact` | `scripts/post-compaction.ps1` | 注入"固化摘要 → 恢复历史 → 续做任务"的恢复序列 + 项目上下文 |
| PreToolUse | `mem_(save\|update\|…)$` | `scripts/pre-tool-use.ps1` | 转发 `engram hook claude-pre-tool-use` 的判定（permissionDecision / updatedInput），会话 id 写入工具入参 |
| MCP（非钩子） | — | `plugin.json` 内置 server | `engram mcp --tools=agent`，提供 `mem_*` 工具族 |

公共逻辑在 `scripts/_common.ps1`：找 engram.exe（`ENGRAM_BIN` → PATH → 兜底路径）、保证服务在线（不在线则拉起 `engram serve`）、解析项目桶名（`ENGRAM_PROJECT` → 最近的 `.engram/config.json` → 目录名）、以 UTF-8 读写钩子标准输入输出。

**协议单一来源**：`plugin/engram-zcode/protocol.md` 同时被注入脚本与 skill 引用，上游演进只需替换这一个文件。

## 前置条件

- Windows 10/11 + PowerShell 5.1 及以上（系统自带即可）
- [engram.exe](https://github.com/Gentleman-Programming/engram) **≥ 3.7.2**（会话绑定与写护栏依赖 `runtime_session_resolution` 能力，`/health` 可确认）
- ZCode 客户端

> 坑：Engram 的 `releases/latest` API 曾长期指向旧 tag（1.15.11），下载新版本请直接翻 `releases?per_page=N` 列表取最新。

## 安装

### 方式一：从 GitHub 仓库添加插件市场（推荐）

1. ZCode → 设置 → 插件管理 → Discover 标签 → 点 `+`
2. 选择添加 **GitHub 仓库**，输入 `cccgang/engram-zcode-plugin`
3. 在市场里安装 `engram-zcode`
4. 按下节[配置](#配置)绑定你自己的 engram.exe
5. 重启 ZCode，开新会话验证

### 方式二：克隆到本地，添加本地目录市场（开发者/离线用）

```bash
git clone https://github.com/cccgang/engram-zcode-plugin.git
```

Discover 标签 → `+` → 添加**本地目录** → 选中克隆目录（仓库根即市场根，`marketplace.json` 在根上）→ 安装 → 重启。

> 市场名会显示为 `dev-engram-local`——这是作者本地开发时的历史名字，仓库结构未改，不影响安装。

### 验证安装

- 设置 → MCP：应出现 `engram` server 且已连接
- 新开会话：上下文里应能看到 "Engram Memory Protocol" 注入文本
- 任意目录跑 `mem_current_project`：应返回解析出的项目名

## 配置

插件捆绑的 MCP server 默认指向**作者机器**的路径（`D:\个人\agent-memory\bin\engram.exe`），公开安装后必须二选一绑定到你自己的 Engram：

### 方式 A：用户级配置覆盖（推荐，不改插件任何文件）

ZCode 里同名 MCP server 的优先级：用户级配置 > 插件捆绑。在 `~/.zcode/cli/config.json` 的 `mcp.servers` 里定义一个同名的 `engram` server 即可覆盖：

```json
{
  "mcp": {
    "servers": {
      "engram": {
        "command": "C:\\path\\to\\engram.exe",
        "args": ["mcp", "--tools=agent"],
        "env": { "ENGRAM_DATA_DIR": "C:\\path\\to\\engram-data" }
      }
    }
  }
}
```

### 方式 B：改插件缓存里的 plugin.json

`~/.zcode/cli/plugins/cache/<市场id>/engram-zcode/<版本>/.zcode-plugin/plugin.json`，把 `mcpServers.engram` 的 `command` 与 `env.ENGRAM_DATA_DIR` 改成你的路径。缺点：插件更新后会被覆盖，不推荐。

### 钩子脚本的环境变量（可选）

钩子脚本不读 `plugin.json`，按以下优先级自行定位 Engram，全部可不设：

| 变量 | 作用 | 缺省行为 |
|---|---|---|
| `ENGRAM_BIN` | engram.exe 完整路径 | 依次找 PATH 上的 `engram` → 作者机器兜底路径 |
| `ENGRAM_DATA_DIR` | 数据目录 | 已设则不动；未设时若作者机器兜底目录存在则启用（防止自动拉起的服务落到错误数据目录） |
| `ENGRAM_URL` | 服务基地址 | `http://127.0.0.1:<ENGRAM_PORT>` |
| `ENGRAM_PORT` | 服务端口 | `7437` |
| `ENGRAM_PROJECT` | 强制指定项目桶 | 按 `ENGRAM_PROJECT` → 最近 `.engram/config.json` → 目录名解析 |
| `CLAUDE_SESSION_ID` / `ZCODE_SESSION_ID` | 会话 id 兜底 | 优先取钩子入参里的 `session_id` |
| `ENGRAM_ZCODE_DEBUG` | 任意非空值开启 | 把 PreToolUse 原始入参追加写到 `%TEMP%\engram-zcode\pretooluse-input.log` |

把 engram.exe 放进 PATH（或设 `ENGRAM_BIN`）之后，钩子脚本零修改即可用；只有 MCP server 必须按上面方式 A/B 绑定。

### 项目归属 pin（非 git 工作区建议）

git 仓库按远端归属项目桶；**非 git 目录** Engram 会回退按目录名/子仓库推断，多仓聚合目录下容易选错。在目录根部放 `.engram/config.json` 显式 pin：

```json
{ "project_name": "your-project" }
```

本插件的钩子（自 0.3.2 起）同样读取最近的 `.engram/config.json`，保证上下文注入查询与 MCP 写入落**同一个项目桶**。设置后可用 `mem_current_project` 验证，应返回 `project_source: config`。

## 设计原则

- **fail-open**：钩子脚本任何失败路径一律 `exit 0` 放行——记忆功能故障绝不阻塞会话或写入；护栏仅在本地服务健康时才可能拒绝
- **全 ASCII 脚本**：脚本逻辑与注入文本（协议原文除外）纯 ASCII，规避 Windows PowerShell 5.1 的编码坑
- **只读外部**：插件只调用 Engram 的 HTTP API / CLI，不修改任何已有记忆或其他插件

## 给 ZCode 插件作者的实测笔记

以下从 ZCode 客户端源码（`app.asar` 的 zod 枚举与钩子运行器）实锤，供写其他插件的兄弟少走弯路：

- 合法钩子事件仅 7 个：`SessionStart / UserPromptSubmit / PreToolUse / PermissionRequest / PostToolUse / PostToolUseFailure / Stop`，**没有** SubagentStop / SessionEnd / PreCompact
- `SessionStart` 的 matcher 值：`startup / resume / clear / compact`
- 钩子输出两种形状都支持：扁平 `{additionalContext}` 或嵌套 `{hookSpecificOutput:{hookEventName,additionalContext}}`（本插件用后者）
- `PreToolUse` 支持 `permissionDecision(allow|ask|deny)` / `permissionDecisionReason` / `updatedInput`
- `process` 型钩子超时单位毫秒，`command` 型为秒，默认 60 秒
- **PowerShell 5.1 编码三坑**（本插件的对策都已写进 `_common.ps1`，可直接抄）：
  1. 无 BOM 的 UTF-8 `.ps1` 会按 ANSI 误读，中文变乱码 → 所有脚本**必须带 UTF-8 BOM**
  2. `[Console]::In` 用控制台代码页（中文系统 GB2312）读 stdin，宿主发来的 JSON 里的非 ASCII 字段（如 cwd）会坏 → 自建 `StreamReader(UTF8)` 读
  3. `Invoke-RestMethod` 把无 charset 的 `application/json` 响应按 ISO-8859-1 解码，中文响应变乱码 → 用 `WebClient` 并显式按 UTF-8 解码

## 与 Codex 官方插件的差距

- **不可复刻**：SubagentStop 子代理归属、SessionEnd 自动收尾（ZCode 钩子白名单实锤无此事件），靠协议文本约定兜底
- **主动裁剪**：UserPromptSubmit 每轮提醒、git-sync 后台导入
- **工程弱化**：护栏 fail-open（服务异常不阻塞写入）；健康检查替代 instance-id 所有权校验

## 目录结构

```
engram-zcode-plugin/                 ← 仓库根 = 插件市场根
├── marketplace.json                 # 市场清单（市场名 dev-engram-local）
└── plugin/engram-zcode/
    ├── .zcode-plugin/plugin.json    # 插件清单：钩子、skill、内置 MCP server
    ├── hooks/hooks.json
    ├── protocol.md                  # 记忆协议单一来源（注入与 skill 共用）
    ├── scripts/*.ps1                # 钩子脚本（UTF-8 BOM，ASCII 逻辑）
    └── skills/memory/SKILL.md       # engram-memory skill
```

## 版本历史

| 版本 | 内容 |
|---|---|
| 0.1.0 | 链路验证：SessionStart 注入固定文本 |
| 0.2.0 | 协议 + 项目上下文注入、compact 恢复、memory skill、内置 MCP server |
| 0.3.0 | 会话绑定 + PreToolUse 写护栏（转译 Engram `claude-pre-tool-use` 输出） |
| 0.3.2 | 钩子读取最近 `.engram/config.json`，注入与写入落同一项目桶 |
| 0.3.3 | 当前版本：全链路脚本本地实测通过 |

## 故障排查

| 现象 | 排查 |
|---|---|
| MCP `engram` 连接失败 | `plugin.json` / 用户级配置里的 engram.exe 路径不对；或 engram.exe 版本 < 3.7.2 |
| 新会话没看到协议注入 | 插件未启用；或被同名更高优先级 skill/命令遮蔽；重启 ZCode 后再试 |
| 记忆写进错误的项目桶 | 非 git 目录未 pin，见上文 `.engram/config.json`；或用 `ENGRAM_PROJECT` 强制指定 |
| 出现两份数据（记忆"丢了"） | 服务以不同 `ENGRAM_DATA_DIR` 起过多次导致存储分裂：统一设一个用户级 `ENGRAM_DATA_DIR`，只迁一份库 |
| 钩子行为异常想看入参 | 设 `ENGRAM_ZCODE_DEBUG=1`，看 `%TEMP%\engram-zcode\pretooluse-input.log` |

## License

[MIT](LICENSE) © 2026 陈刚 ([cccgang](https://github.com/cccgang))
