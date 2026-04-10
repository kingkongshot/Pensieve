---
id: fork-extensions-design
type: spec
title: "Fork 扩展设计：auto-sediment hook + 规划前检索 + hook 自管理"
status: active
created: 2026-04-10
tags: [fork, extension, auto-sediment, hooks, planning-retrieval, design-intent]
---

# Fork 扩展设计：auto-sediment hook + 规划前检索 + hook 自管理

> **本文档仅描述 `alfadb` fork 的扩展**，不是上游 `kingkongshot/Pensieve` 的官方设计。
> 上游作者的原设计见 `README.md`、`docs/architecture-v2.md`、`.src/references/`。
> 本 fork 的扩展与上游**独立并列**，不替代、不互补上游的任何机制。

## 0. 摘要

本 fork 在不修改上游核心设计的前提下，增加三层 hook 扩展：

1. **规划前知识检索**（PreToolUse/EnterPlanMode + Skill hook）
2. **会话启动知识图谱注入**（SessionStart hook 增强）
3. **每轮自动沉淀评估**（Stop hook，fork 独有）

以及一个 hook 生命周期自管理系统（`hooks.json` + `register-hooks.sh`），让 `init` 能自动注册全部 hook，避免用户手动编辑 `settings.json`。

所有扩展都经过 2026-04-09 ~ 2026-04-10 的完整 probe 实验端到端验证。三个月内三次 `verify-before-sediment` 应用（session_counter / cooldown / git_clean 过滤器的移除）留下了珍贵的元教训：**绝不在未读上游设计的前提下，把自己的期待投射到上游文件上**。

---

## 1. 问题陈述

### 1.1 上游已有能力

上游 Pensieve 提供：
- **四层知识模型**：maxim / decision / knowledge / pipeline
- **六个工具**：init / upgrade / migrate / doctor / self-improve / refine
- **三个自动 hook**（由 `install-hooks.sh` 注册）：
  - `SessionStart` → 检查初始化/升级状态
  - `PreToolUse/Agent` → 给 Explore/Plan 代理注入 SKILL.md + state.md
  - `PostToolUse/Write|Edit|MultiEdit` → 编辑后自动同步知识图谱
- **Pipeline 作为用户显式调用的工作流模板**（用户说"用 pensieve commit/review" → Claude 按 Task Blueprint 执行）

### 1.2 仍存在的知识流失场景

通过分析微信文章《从决策、执行到记忆复利：gstack + Superpowers + CE》后识别的提升空间：

1. **规划阶段不主动检索历史经验**
   - 用户开始规划时 Claude 不会自动查 `decisions/` 和 `knowledge/`
   - 容易重复踩坑、推翻已有 active decision
   - 上游的 PreToolUse/Agent hook 只在 Explore/Plan 代理被调用时注入，主对话线不覆盖

2. **用户不显式说"用 pensieve 沉淀"时洞察易丢失**
   - 上游 pipeline 必须用户显式调用才会执行
   - 纯讨论/调试/架构分析的会话经常产生洞察，但用户忙于主任务时容易忘记手动触发 self-improve
   - 会话结束后 Claude Code 关闭，洞察就永远丢失

3. **Hook 配置手动维护**
   - 上游 `install-hooks.sh` 硬编码 3 个 hook
   - 新增 hook 需要同时改脚本和用户的 settings.json
   - fork 想增加新 hook 必须维护分叉的安装脚本

### 1.3 设计约束

在设计扩展时明确以下约束（前三次失败后才彻底清醒）：

- **C1：不污染上游文件**。任何 pipeline / knowledge / reference 文档都是上游作者的原始表达，fork 不得加"纠错性注释"
- **C2：不建立虚构的互补关系**。所有扩展的"触发路径"必须有实际验证的痕迹，不能依赖"作者应该会做 X"的假设
- **C3：测试期的保守措施不能直接成为生产设计**。每个过滤器、每个限制都必须单独论证必要性
- **C4：事件驱动而非时间驱动**。任何"冷却 / 节流 / 限流"机制必须基于用户工作流事件（commit / 文件编辑），不基于墙钟
- **C5：本 fork 扩展与上游机制独立并列**。不替代上游 pipeline，不依赖上游的任何假想自动触发

---

## 2. 设计意图

### 2.1 两条沉淀路径独立并列

Fork 在上游的"用户显式调用 pipeline"模式之外，新增"每轮自动评估"的第二条沉淀路径。两者**独立并列**：

| 维度 | 上游 pipeline（原设计） | Fork auto-sediment hook（扩展） |
|------|----------------------|-----------------------------|
| 触发 | 用户说"用 pensieve commit/review" | 每轮 Stop hook，过滤器 PASS 即触发 |
| 触发者 | 用户显式意图 | 系统事件（会话轮次结束） |
| 谁决定执行 | 用户 | Claude 续轮语义判断 |
| 覆盖场景 | 用户记得主动调用的重要沉淀点 | 用户未主动调用但仍有洞察的日常轮次 |
| 互相关系 | **并列**，不依赖、不替代、不互补 | **并列**，同上 |
| 去重机制 | self-improve 内部的重复检查 + `pensieve refine` | 同上 |

两条路径可能同时捕获同一洞察（比如用户说"用 pensieve commit"时 Claude 执行上游 pipeline，auto-sediment hook 同一轮也触发），由 self-improve 的重复检查和 refine 的 triage 清理。

### 2.2 Hook 自管理：让 init 成为唯一安装点

上游 `install-hooks.sh` 硬编码 hook 列表，新增 hook 必须改脚本。Fork 改为数据驱动：

```
.src/core/hooks.json           # 所有 hook 声明（单一事实来源）
.src/scripts/register-hooks.sh # 幂等读取 hooks.json + 合并到 settings.json
.src/scripts/init-project-data.sh → 调用 register-hooks.sh
```

**效果**：
- `init` 运行后自动注册所有 Pensieve hook
- 识别 Pensieve hook 通过命令中的 `run-hook.sh` 模式，不触碰 gstack / Ralph-Loop 等其他 hook
- 新增 hook 只改 `hooks.json`，不改脚本
- 用户**仍需重启 Claude Code** 会话才能让新 hook 生效（参见 `knowledge/claude-code-hook-config-startup-cache`）

### 2.3 Per-turn 而非 per-session

Claude Code 的 Stop hook 是 **per-turn 语义**：每一轮对话结束都触发，不是会话结束才触发。这是本 fork 的一个关键技术基础，在上游 decisions 中没有明确记录（上游从未用 Stop hook 做沉淀，所以没有这个知识）。

Per-turn 设计的核心前提：

- **接受每轮独立评估**：不试图用 marker 模拟"只在最后一轮触发"
- **用 `stop_hook_active` 字段防递归**：Claude 续轮执行 self-improve 时这个字段变 `true`，过滤器直接 SKIP
- **用 `last_assistant_message` 字段看本轮内容**：不需要解析 transcript.jsonl
- **接受多轮沉淀的可能性**：长会话的多个独立洞察都能被捕获
- **拒绝时间节流**：任何一轮都可能是最后一轮，时间 cooldown 会永久丢失 cooldown 窗口内的洞察

### 2.4 过滤器最小化

经过三次 `verify-before-sediment` 应用后，auto-sediment hook 的过滤器减到最少：

- ✅ `recursion_guard` — 防止 Claude 续轮无限递归
- ✅ `pensieve_project` — 非 Pensieve 项目静默退出
- ✅ `ralph_loop` — Ralph-Loop 活跃时让路
- ✅ `substantial` — 短回复跳过（避免短问答触发 Claude 续轮）
- ❌ ~~session_counter~~ — 移除：限制长会话的多个洞察
- ❌ ~~cooldown~~ — 移除：任何一轮可能是最后一轮
- ❌ ~~git_clean~~ — 移除：基于"commit pipeline 会处理"的虚构假设

剩下的 4 个都是**必需**，每个都回答过"如果移除它，什么坏情况会发生？"这个问题：

| 过滤器 | 移除后的坏情况 |
|------|-------------|
| recursion_guard | Claude 续轮后 Stop hook 再次触发 → 无限递归 |
| pensieve_project | 在非 Pensieve 项目中输出 decision:block → 污染其他项目 |
| ralph_loop | Ralph-Loop 循环被 auto-sediment 干扰 → 循环中断 |
| substantial | 每个"收到"、"好的"都触发 Claude 续轮 → 噪声爆炸 |

---

## 3. 目标

### 3.1 功能目标

| 目标 | 实现机制 | 验证证据 |
|------|---------|---------|
| G1：规划前自动检索相关历史经验 | PreToolUse/EnterPlanMode + Skill hook → `planning-prehook.sh` | probe 实验 2026-04-09 |
| G2：会话启动自动注入知识图谱 | 增强 `pensieve-session-marker.sh` 追加图谱内容到 `additionalContext` | 本 fork 所有会话 |
| G3：每轮自动评估是否沉淀 | Stop hook → `stop-hook-auto-sediment.sh` → `decision:block` + 信号评估 prompt | probe v1-v5 端到端验证 |
| G4：Hook 注册自动化 | `hooks.json` + `register-hooks.sh` + `init` 末尾调用 | 本 fork 默认安装流程 |
| G5：捕获失败经验（"好的失败"） | commit pipeline Task 1 信号清单 + auto-sediment prompt 信号清单 | 本会话 3 次 verify-before-sediment 应用的沉淀 |
| G6：避免沉淀重复 | commit pipeline Task 2 加重复检查步骤（写入前 grep 现有条目） | feature/hook-lifecycle-and-planning-pipeline 分支 |
| G7：评审深度按 diff 规模动态扩展 | review pipeline 加 S/M/L 分级 + Task 3 按分级审查广度 | feature/hook-lifecycle-and-planning-pipeline 分支 |

### 3.2 非功能目标

- **N1：零上游污染**。上游 pipeline / knowledge / reference 文件不被本 fork 修改内容，只增加独立的脚本和 `hooks.json` 条目
- **N2：兼容上游更新**。上游更新可通过标准 merge / rebase 流程合并，本 fork 的改动集中在新增文件和少量辅助脚本
- **N3：可观测**。所有 hook 调用通过 `run-hook.sh` 的 `hook-trace.log` 统一记录，出错时可诊断
- **N4：降级安全**。非 Pensieve 项目（无 `.pensieve/`）所有 hook 静默 `exit 0`，对其他项目零影响
- **N5：幂等**。`register-hooks.sh` 可反复运行，多次结果一致

---

## 4. 方法

### 4.1 新增的脚本

| 文件 | 用途 | 触发 | 依赖上游假设 |
|------|------|------|------|
| `.src/core/hooks.json` | 单一事实来源 Hook 清单 | 数据 | 无 |
| `.src/scripts/register-hooks.sh` | 幂等 hook 注册到 `settings.json` | `init` 调用 | 无 |
| `.src/scripts/planning-prehook.sh` | 规划前注入 Pensieve 知识上下文 | PreToolUse/EnterPlanMode + PreToolUse/Skill (plan-*) | 无 |
| `.src/scripts/stop-hook-auto-sediment.sh` | 每轮 Stop 触发沉淀评估 | Stop | 无 |
| `.src/scripts/pensieve-session-marker.sh` | （增强上游脚本）追加图谱注入到 `additionalContext` | SessionStart（上游注册） | 增强，不修改行为 |
| `.src/scripts/run-hook.sh` | （增强上游脚本）增加 `hook-trace.log` 追踪 | 所有 hook 的入口 | 增强，不修改行为 |
| `.src/scripts/init-project-data.sh` | （增强上游脚本）末尾调用 `register-hooks.sh` | `init` 工具 | 增强，不修改行为 |

### 4.2 hooks.json 完整 hook 清单

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "... pensieve-session-marker.sh --mode session-start" }] }
    ],
    "PreToolUse": [
      { "matcher": "Agent", "hooks": [{ "type": "command", "command": "... explore-prehook.sh" }] },
      { "matcher": "Skill", "hooks": [{ "type": "command", "command": "... planning-prehook.sh" }] },
      { "matcher": "EnterPlanMode", "hooks": [{ "type": "command", "command": "... planning-prehook.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|MultiEdit", "hooks": [{ "type": "command", "command": "... sync-project-skill-graph.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "... stop-hook-auto-sediment.sh" }] }
    ]
  }
}
```

对比上游 `install-hooks.sh`：新增了 `PreToolUse/Skill`、`PreToolUse/EnterPlanMode` 和 `Stop` 三条。

### 4.3 auto-sediment hook 完整流程

```
Turn N 结束
  ↓
Stop hook 触发
  ↓
stop-hook-auto-sediment.sh
  ├─ 过滤器 0: recursion_guard — stop_hook_active != true
  ├─ 过滤器 1: pensieve_project — .pensieve/ 存在
  ├─ 过滤器 2: ralph_loop — 非 active
  └─ 过滤器 3: substantial — last_assistant_message 长度 ≥ 200
  ↓ 全部 PASS
输出 decision:block + 信号评估 prompt:
  [PENSIEVE AUTO-SEDIMENT CHECK]
  ... 成功信号 6 项 ...
  ... 失败信号 3 项 ...
  命中 → /pensieve self-improve
  未命中 → NO_SEDIMENT: <理由>
  严格遵守: 不继续主任务 / 不问用户 / 不调用其他 skill
  ↓
Claude 续轮评估
  ├─ 命中 → 调用 /pensieve 的 self-improve 工具 → 写入 short-term → stop
  └─ 未命中 → 输出 NO_SEDIMENT → stop
  ↓
续轮结束 → Stop hook 再次触发
  ↓
stop_hook_active = true → recursion_guard FAIL → exit 0
```

### 4.4 Planning prehook 流程

```
Claude 调用 EnterPlanMode 或 Skill(plan-*/autoplan/office-hours)
  ↓
PreToolUse hook 触发
  ↓
planning-prehook.sh
  ├─ 过滤器 0: tool_name == "EnterPlanMode" 或 skill name 匹配规划模式
  ├─ 过滤器 1: .pensieve/ 存在
  └─ 读取 .pensieve/pipelines/run-when-planning.md
      ↓
      grep decisions/ knowledge/ maxims/ 中 status: active 的条目
      ↓
      封装为 additionalContext JSON 输出
  ↓
Claude 在规划 tool 执行前获得注入的上下文
```

---

## 5. 验证历程与 3 次失败教训

### 5.1 三个 feature 分支的演进

```
upstream experimental (7b81567)
  ↓
feature/hook-lifecycle-and-planning-pipeline (d3d7bf6 → 1e8f956)
  │   ├─ 新增 hooks.json + register-hooks.sh
  │   ├─ 新增 run-when-planning.md 模板
  │   ├─ 增强 run-when-committing.md（失败信号 + 重复检查）
  │   ├─ 增强 run-when-reviewing-code.md（diff 规模分级）
  │   ├─ 增强 pensieve-session-marker.sh（图谱注入）
  │   └─ 新增 planning-prehook.sh
  │   → 初次 Stop hook 尝试失败，回归手动沉淀
  ↓
experiment/stop-hook-payload-probe（本地实验分支）
  │   ├─ probe v1: 验证 payload 字段
  │   ├─ probe v2: 验证 stop_hook_active 切换
  │   ├─ probe v3: 观察性过滤器评估
  │   ├─ probe v4: 全过滤器评估（发现 grep -v pipefail 陷阱）
  │   └─ probe v5: 启用 decision:block 真实触发
  │   → 端到端验证通过
  ↓
feature/auto-sediment-hook (0d06592 → ca278b2)
  │   ├─ 新增 stop-hook-auto-sediment.sh (104 行)
  │   ├─ hooks.json 增加 Stop 条目
  │   ├─ 移除 session_counter 过滤器（第 1 次 verify-before-sediment）
  │   ├─ 移除 cooldown 过滤器（第 2 次 verify-before-sediment）
  │   ├─ 移除 git_clean 过滤器（第 3 次 verify-before-sediment，表层）
  │   └─ 恢复 commit pipeline 警告块（第 3 次 verify-before-sediment，根因）
  │   → 4 层过滤器最终稳定
```

### 5.2 三次 verify-before-sediment 应用

所有三次都源于同一个**元错误**：从未完整读过上游的 README、install-hooks.sh、规范文档，直接基于自己的期待编造前提。每次局部修正都不够深，直到彻底调查上游原始设计才看清。

#### 第 1 次：session_counter 过滤器

- **错误**：给 hook 加 `每会话最多一次沉淀` 限制
- **用户戳破**：`per-turn 不应该是每次 stop hook 都触发沉淀吗？`
- **根因**：把 probe 测试期的"保守安全措施"直接搬进生产代码
- **修正**：移除

#### 第 2 次：cooldown 过滤器

- **错误**：加 `10 分钟内不允许重复沉淀` 时间节流
- **用户戳破**：`cooldown 是否真的有必要？是否有可能遗漏重要信息？特别是最后一轮对话`
- **根因**：假设"10 分钟内不会有多个独立洞察" — 任何一轮都可能是最后一轮
- **修正**：移除

#### 第 3 次：git_clean 过滤器 + "警告块污染"

- **错误**：加 `有未提交变更 → SKIP` 过滤器，理由"让 commit pipeline 处理脏树"
- **表层戳破（用户质问 1）**：`commit pipeline 是否真的包含了沉淀指令？我要求提交时从来没被触发过`
- **表层修正**：发现 commit pipeline 从未被任何机制自动触发，移除 git_clean；**但同时给上游 pipeline 加了"⚠️ 手动参考文档"警告块**
- **根因戳破（用户质问 2）**：`我需要你详细分析 pensieve 的 pipeline 机制，分析上游作者的真实设计方向`
- **根因**：深入调查上游 `install-hooks.sh` / README / pipelines.md 后发现——**上游从未设计自动触发**，pipeline 本来就是"用户显式调用的工作流模板"。我的警告块是在纠正**不存在的错误**，纠正对象是自己的误解，反而污染了上游原始表达
- **根因修正**：撤销警告块，恢复上游 pipeline 文件；明确 auto-sediment hook 是 fork 独立扩展，与上游 pipeline 并列而非互补

### 5.3 元教训（已沉淀到 `maxims/verify-before-sediment`）

从三次应用中提炼出的补充规则：

- **规则 5**：测试期加的约束必须在工程化时单独论证——每个约束回答"如果移除它，什么坏情况会发生？"
- **规则 6**：提防"防御性编程"陷阱——加一个"万一"过滤器容易，但每个过滤器都是在拒绝潜在的正确行为
- **规则 7**：文档中的流程 ≠ 实际运行的机制——任何依赖"另一个机制会处理 X"的设计必须验证触发路径
- **规则 8**：读上游设计时先问"作者想表达什么"，不是"我期待什么"——与自己理解冲突时默认是自己读错了
- **规则 9**：不要给上游文件加"纠错性注释"——警告块等于把"我的误解"永久刻在上游文件里

---

## 6. 与上游 Pensieve 的接触面

本 fork 改动清单（vs 上游 experimental HEAD `7b81567`）：

### 6.1 新增文件（不影响上游升级）

```
.src/core/hooks.json                              (59 行, hook 声明)
.src/scripts/register-hooks.sh                    (112 行, 幂等注册器)
.src/scripts/planning-prehook.sh                  (92 行, 规划前注入)
.src/scripts/stop-hook-auto-sediment.sh           (85 行, auto-sediment)
.src/templates/pipeline.run-when-planning.md      (108 行, 规划 pipeline 模板)
docs/fork-extensions-design.md                    (本文件)
```

### 6.2 增强文件（需要 merge 时手动处理）

```
.src/scripts/init-project-data.sh                 (+6 行, 末尾调用 register-hooks.sh)
.src/scripts/pensieve-session-marker.sh           (+9 行, 图谱注入)
.src/scripts/run-hook.sh                          (+17 行, hook-trace.log)
.src/templates/pipeline.run-when-committing.md    (+13 行, 失败信号 + 重复检查)
.src/templates/pipeline.run-when-reviewing-code.md (+18 行, diff 规模分级)
.src/manifest.json                                (版本 1.2.0 → 1.4.0)
```

### 6.3 未改动的上游内容

- 所有 `.src/references/` 规范文档
- 所有 `.src/tools/` 工具定义
- `SKILL.md` 路由表
- `README.md`
- `docs/architecture-v2.md`
- `docs/four-layer-memory-analysis.md`

### 6.4 合并上游更新的策略

标准 rebase / merge 流程即可，需要人工处理的冲突点：

- `init-project-data.sh` / `pensieve-session-marker.sh` / `run-hook.sh` — 上游如果改了这些脚本，需要手动合并扩展代码
- `pipeline.run-when-committing.md` / `pipeline.run-when-reviewing-code.md` — 如果上游改了 Task Blueprint，需要手动合并 fork 的增强部分
- `hooks.json` — 上游如果 merge 进这个文件（表示上游自己也转向数据驱动），需要合并 hook 清单
- `manifest.json` — 版本号冲突时，按 semver 规则选择更高版本

---

## 7. 使用方法

### 7.1 初始化（新项目）

```bash
cd <new-project>
bash ~/.claude/skills/pensieve/.src/scripts/init-project-data.sh
# init 末尾自动调用 register-hooks.sh 注册 5 个 hook 到 ~/.claude/settings.json

# ⚠️ 必须重启 Claude Code 会话才能让新 hook 生效
# （参见 knowledge/claude-code-hook-config-startup-cache）
```

### 7.2 升级（已初始化项目）

```bash
# 升级 Pensieve skill
cd ~/.claude/skills/pensieve
git pull

# 重新注册 hooks（幂等）
bash ~/.claude/skills/pensieve/.src/scripts/register-hooks.sh

# 在各项目中 migrate（对齐 critical files）
cd <existing-project>
bash ~/.claude/skills/pensieve/.src/scripts/run-migrate.sh
bash ~/.claude/skills/pensieve/.src/scripts/run-doctor.sh --strict

# 重启 Claude Code 会话让新 hook 生效
```

### 7.3 调优 auto-sediment hook

通过环境变量调整过滤器阈值：

```bash
# 提高 substantial 门槛（默认 200 字符）
export PENSIEVE_SEDIMENT_MIN_LENGTH=500
```

其他过滤器没有 tunable，因为它们都是必需的。

### 7.4 关闭 auto-sediment hook（保留其他 fork 扩展）

编辑 `~/.claude/settings.json`，删除 Stop hook 中的 auto-sediment 条目。或者在 `hooks.json` 中删除 Stop 部分然后重跑 `register-hooks.sh`。

---

## 8. 相关沉淀条目（知识库证据链）

本 fork 设计的完整证据链分布在以下 Pensieve 条目中（以开发者项目为例）：

### 8.1 上游设计真相
- `knowledge/pensieve-pipeline-is-user-invoked/content.md` — 上游 pipeline 是用户显式调用机制的完整证据

### 8.2 Hook 技术基础
- `knowledge/stop-hook-per-turn-pattern/content.md` — per-turn 沉淀的技术模式
- `knowledge/claude-code-hook-config-startup-cache/content.md` — hook 配置在会话启动时缓存
- `knowledge/claude-cli-sidecar-pattern/content.md` — claude CLI sidecar flag 组合
- `knowledge/claude-code-session-id-discovery/content.md` — session ID 文件系统发现

### 8.3 实现陷阱
- `knowledge/bash-grep-v-pipefail-trap/content.md` — `grep -v` 在 pipefail + 空输入下杀脚本
- `knowledge/pensieve-status-allowed-values/content.md` — frontmatter status 字段仅允许 active/archived/draft

### 8.4 设计决策
- `decisions/2026-04-09-compound-knowledge-mechanisms.md` — 从 CE 提取机制的总决策
- `decisions/2026-04-09-stop-hook-per-turn-semantics.md` — 初次放弃自动沉淀（archived）
- `decisions/2026-04-10-per-turn-sediment-validated.md` — per-turn 方案验证通过 + 修正历程

### 8.5 元教训
- `maxims/verify-before-sediment.md` — 沉淀前先验证的反模式（3 个犯错场景 + 9 条规则）

---

## 9. 设计一句话总结

> **本 fork 在上游 Pensieve "用户显式调用 pipeline" 模式之外，增加一条"每轮自动评估沉淀"的独立路径。两条路径并列共存，由 Claude 在续轮中用信号清单做语义判断，事件驱动而非时间驱动。三次过滤器"聪明化"的失败教训证明：任何偏离 per-turn 设计哲学的约束都是在把自己的期待投射到上游设计上。**

---

## 附录 A：版本历史

| 版本 | 日期 | 分支 | 关键改动 |
|------|------|------|---------|
| 1.3.0 | 2026-04-09 | feature/hook-lifecycle-and-planning-pipeline | Hook 自管理 + 规划前检索 + commit/review pipeline 增强 |
| 1.4.0 | 2026-04-10 | feature/auto-sediment-hook | Per-turn auto-sediment hook |

## 附录 B：贡献者

- Fork 维护：alfadb
- 上游作者：kingkongshot（Pensieve 原设计）
- 设计协作：Claude Opus 4.6 (1M context)
- 灵感来源：微信文章《从决策、执行到记忆复利：gstack + Superpowers + CE 完整实战工作流》
