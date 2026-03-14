# Changelog

## v2.0.0 — 用户级系统 + 项目级数据

> 架构规格：`docs/architecture-v2.md`

### 动机

v1 中每个项目 `git clone` 一份完整的系统代码到 `<project>/.claude/skills/pensieve/`，用户数据与系统代码物理混合，更新需逐项目 `git pull`，安装需 skill clone + plugin 双轨操作。v2 解决这些问题。

### 破坏性变更

- **系统代码从项目级移至用户级**：`~/.claude/skills/pensieve/`（全局唯一安装）
- **用户数据从 skill 目录内移至项目根**：`<project>/.pensieve/`
- **运行时状态路径变更**：`<project>/.state/` → `<project>/.pensieve/.state/`
- **SKILL.md 变为静态 tracked 文件**：不再由 `init` 脚本生成；动态内容拆至 `<project>/.pensieve/state.md`
- **`maintain-project-skill.sh` 重命名为 `maintain-project-state.sh`**：维护目标从 SKILL.md 改为 state.md
- **`project_skill_file()` 函数移除**：v2 中 SKILL.md 和 state.md 语义完全不同，不设兼容别名
- **`claude-plugin` 分支淘汰**：hooks 合入主分支，通过 `install-hooks.sh` 全局安装

### 新增

- **`SKILL.md`**（仓库根）：静态 skill 接口声明，由 git 跟踪，`git pull` 更新
- **`install-hooks.sh`**：将 hook 配置写入 `~/.claude/settings.json`，一次安装全局生效
- **`maintain-project-state.sh`**：维护 `<project>/.pensieve/state.md`（生命周期状态 + 知识图谱）
- **`validate_project_root()`**（`lib.sh`）：拒绝 `$HOME`、`/`、`/tmp`、skill root 本身作为项目根
- **`resolve_output_path()`**（`lib.sh`）：统一输出路径解析（绝对/相对 + 默认值）
- **`project_state_file()`** / **`skill_md_file()`**（`lib.sh`）：v2 路径访问函数
- **`normalize_critical_file_content()`** / **`load_skill_description()`**（`pensieve_core.py`）：共享实现，消除 scan-structure / run-migrate / maintain-auto-memory 间的代码重复
- **`classify_state()`**（`pensieve_core.py`）：项目数据生命周期状态机（EMPTY → SEEDED → ALIGNED / DRIFTED）
- **`architecture-v2.md`**（`docs/`）：完整的架构规格文档

### 变更

#### 路径解析（`lib.sh`）

| 函数 | v1 | v2 |
|---|---|---|
| `project_root()` | 从 skill root 剥离客户端路径推导 | `CLAUDE_PROJECT_DIR` → git → `.pensieve/` 向上查找 |
| `user_data_root()` | = `skill_root()` | = `<project>/.pensieve/` |
| `state_root()` | = `<project>/.state/` | = `<project>/.pensieve/.state/` |
| `skill_root()` | 向上查找 `manifest.json` | 同上（不变），但不再参与项目路径推导 |

#### Hook 系统

| 方面 | v1 | v2 |
|---|---|---|
| 安装方式 | `claude plugin install`（`claude-plugin` 分支） | `bash install-hooks.sh`（写入 `~/.claude/settings.json`） |
| 配置位置 | 项目级 `<project>/.claude/settings.json` | 用户级 `~/.claude/settings.json` |
| `run-hook.sh` SKILL_ROOT 默认值 | `$PROJECT_ROOT/.claude/skills/pensieve` | `$HOME/.claude/skills/pensieve` |
| 优雅降级 | 无 | 所有 hook 在项目无 `.pensieve/` 时静默 `exit 0` |

#### 脚本适配

- **`explore-prehook.sh`**：注入 SKILL.md + state.md 双文件；以 `state.md` 存在作为项目激活判断
- **`pensieve-session-marker.sh`**：以 `.pensieve/` 目录存在作为优雅降级条件
- **`sync-project-skill-graph.sh`**：文件路径匹配改为 `user_data_root()`（`.pensieve/`）
- **`init-project-data.sh`**：初始化目标改为 `<project>/.pensieve/`；创建 `.gitignore` 排除 `.state/`
- **`run-doctor.sh`** / **`run-migrate.sh`** / **`run-upgrade.sh`**：适配 v2 路径 + `validate_project_root()` 防护
- **`scan-structure.sh`**：简化为仅检测旧目录存在（STR-101），移除内容级 legacy 检测
- **`generate-user-data-graph.sh`**：移除 `is_generated_skill` 过滤（SKILL.md 不再是生成文件）

#### Schema（`schema.json`）

- `schema_version`: `1` → `2`（`pensieve_core.py` 强制校验）
- 新增 `legacy_paths.project`：覆盖 `.claude/skills/pensieve`、`.agents/skills/pensieve`、`skills/pensieve`、`.claude/pensieve`
- 新增 `legacy_paths.user`：覆盖 `~/.claude/pensieve`
- 移除 findings 模板（STR-102/111/121/301），精简至结构检测

#### 文档

- **`README.md`**：全面重写——安装流程改为用户级全局安装 + `install-hooks.sh`，新增从旧版本升级说明
- **`directory-layout.md`**：重写为用户级 + 项目级双锚点布局
- **`skill-lifecycle.md`**：安装 / 卸载 / 升级流程适配 v2
- **`shared-rules.md`**：路径引用更新为 `.pensieve/`
- **`tool-boundaries.md`**：init / upgrade 职责描述更新
- **所有工具规格**（`init.md` / `doctor.md` / `migrate.md` / `upgrade.md` / `self-improve.md`）：统一使用 `$PENSIEVE_SKILL_ROOT` 前缀调用脚本

### 移除

- `project_skill_file()`：SKILL.md ↔ state.md 兼容别名（格式完全不同，静默映射会误导调用方）
- `maintain-project-skill.sh`：被 `maintain-project-state.sh` 替代
- `runtime_log()` / `run_with_retry_timeout()`（`lib.sh`）：无调用者的死代码
- `plugin_root_from_script()`（`lib.sh`）：v1 plugin 分支专用，v2 不再需要
- `project_root()` 中客户端路径剥离逻辑：v2 中 skill root 不在项目内部
- `scan-structure.sh` 中 `finding_text` / `add_finding_by_id` 间接层：直接内联消息
- `schema.json` 中 `findings` 模板定义：仅 scan-structure 内部使用，不需要集中配置
- `.gitignore` 中 v1 遗留规则：`/SKILL.md`、`/maxims/`、`/decisions/`、`/knowledge/`、`/pipelines/`、`/.state/`

### 迁移指南

从 v1 迁移到 v2：

```bash
# 1. 全局安装系统代码
git clone -b zh https://github.com/kingkongshot/Pensieve.git ~/.claude/skills/pensieve

# 2. 安装全局 hooks
bash ~/.claude/skills/pensieve/.src/scripts/install-hooks.sh

# 3. 每个项目执行迁移
cd <your-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-migrate.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict

# 4. 卸载旧插件（如有）
claude plugin uninstall pensieve 2>/dev/null || true
```

`run-migrate.sh` 自动处理：
- 用户数据从旧路径（`.claude/skills/pensieve/`、`.agents/skills/pensieve/` 等）移入 `.pensieve/`
- 运行时状态从 `<project>/.state/` 移入 `.pensieve/.state/`
- 关键种子文件对齐（备份 + 替换）
- 旧 graph 文件和 README 副本清理
- 旧版本目录删除
