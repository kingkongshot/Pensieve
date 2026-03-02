---
description: 只读检查工具：基于 README 规范输出 PASS/PASS_WITH_WARNINGS/FAIL 与 MUST_FIX/SHOULD_FIX/INFO 证据清单，不改用户数据文件。触发词：doctor、health check、检查。
---
# Doctor 流程

> 工具边界见 `<SYSTEM_SKILL_ROOT>/references/tool-boundaries.md` | 共享规则见 `<SYSTEM_SKILL_ROOT>/references/shared-rules.md` | 目录约定见 `<SYSTEM_SKILL_ROOT>/references/directory-layout.md`

### Use when
- 用户要求检查、合规检查、迁移后复检
- 需要明确 `MUST_FIX/SHOULD_FIX` 及证据
- 需要确认旧路径并行、命名冲突或非项目级遗留

### Failure fallback
- 规范文件不可读：中止判定，标注"无法判定"
- 快检脚本未成功：不给最终结论，先报告阻塞点
- 图谱读取失败：不给最终结论，先修复图谱步骤

从规范推导检查项而非硬编码。

---
规范来源（通用约束见 `shared-rules.md` § 规范来源）：`<SYSTEM_SKILL_ROOT>/maxims/README.md`、`decisions/README.md`、`pipelines/README.md`、`knowledge/README.md`、`tools/doctor/migrations/README.md`、`tools/upgrade/_upgrade.md`（仅版本流程）、`tools/migrate/_migrate.md`（仅迁移流程）。

检查范围：项目级用户数据（以 `migrations/README.md` Latest 为准）及旧路径候选（deprecated 列表）。插件配置：`~/.claude/settings.json`、`<project>/.claude/settings.json`。

## 严重性原则
**MUST_FIX**：
1. 存在新旧并行双源
2. 违反 README 中 `must / required / hard rule / at least one`
3. `decision`/`pipeline` 缺少链接字段或链接全部无效
4. 用户数据根目录或关键分类目录缺失
5. `pipeline` 以大段知识堆叠替代 task 编排且未拆分为链接引用
6. `pipeline` 文件名未采用 `run-when-*.md`
7. 用户数据目录存在但缺少初始种子
8. `enabledPlugins` 同时保留旧键与新键，或缺失新键
9. 发现插件级/用户级 pensieve skill 副本，未收敛到项目级
10. 发现独立 graph 文件（`_pensieve-graph*.md`/`pensieve-graph*.md`/`graph*.md`）
11. 发现项目级子目录中的历史规范 README 副本
12. `~/.claude/projects/<project>/memory/MEMORY.md` 缺失 Pensieve 引导块或未与系统 SKILL.md `description` 对齐

**SHOULD_FIX**：recommended/建议/prefer 规则未满足但不阻断主流程。含 `decision` 缺少"定位加速"段或"下次少问/下次少查/失效条件"。

**INFO**：观察项、统计项、或需用户决策的取舍项。

**结论状态判定**（硬规则）：`MUST_FIX > 0` → `FAIL`（结构迁移类问题→`migrate`；插件键类问题→`upgrade`；其余→`self-improve`）| `MUST_FIX = 0` 且 `SHOULD_FIX + INFO > 0` → `PASS_WITH_WARNINGS`（→ `self-improve`）| 三者均 0 → `PASS`（→ `none`）

**执行原则（简化）**：优先执行 `run-doctor.sh`，并以脚本产出的 summary/report 为唯一判定依据，不做人工二次推断。

---
## Phase 1: 读取规范并生成检查矩阵
**Goal**: 从规范文件提取所有检查项，生成内部检查矩阵。
**Actions**:
1. 读取"规范来源"全部文件，提取目录结构、命名、必填 section/字段、链接规则
2. 从 `migrations/README.md` 提取 latest/deprecated 列表
3. 结构判定统一由 `scan-structure.sh` 实现

## Phase 2: 扫描文件并验证
**Goal**: 运行共享结构扫描，读取结果纳入判定。
**Actions**:
0. 优先使用总控脚本（推荐）：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict
```
> 该脚本会串行执行结构扫描、frontmatter 快检、图谱生成、报告汇总与 SKILL/MEMORY 维护。若使用该脚本，可跳过下方 1~3 的手工拼装步骤。
1. 运行：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/scan-structure.sh --output .state/pensieve-structure-scan.json
```
2. 读取 `status`、`summary.must_fix_count`/`should_fix_count`、`flags.*`、`findings[]`
3. 若 `must_fix_count > 0`，结论至少 `FAIL`；结构迁移类建议动作为 `migrate`，插件键类建议动作为 `upgrade`

## Phase 2.2: Frontmatter 快检
**Goal**: 覆盖 frontmatter 格式验证，纳入判定。
**Actions**:
1. 运行：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/check-frontmatter.sh --format text
```
2. 读取 Files scanned、MUST_FIX/SHOULD_FIX 数量与明细
3. frontmatter 语法错误/缺失/必填字段缺失/值非法 → `MUST_FIX`；pipeline 命名违规（`FM-301/FM-302`）→ `MUST_FIX`；`decision` 定位加速缺失（`FM-401~FM-404`）→ `SHOULD_FIX`

## Phase 2.5: 生成图谱并验证链接
**Goal**: 验证知识网络链接连通性。
**Actions**:
1. 运行：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/upgrade/scripts/generate-user-data-graph.sh
```
2. 读取笔记数/链接数/已解析/未解析，至少抽样前 5 条未解析链接
3. 与文件扫描冲突时取更保守判定

## Phase 3: 输出固定格式报告
**Goal**: 按固定模板输出，每条问题含规则来源。
**Actions**:
1. 模板：

```markdown
# Pensieve Doctor 报告

## 0) 头信息
- 检查时间: {YYYY-MM-DD HH:mm:ss}
- 项目根目录: `{absolute-path}`
- 数据目录: `{absolute-path}/.claude/skills/pensieve`

## 1) 执行摘要（先看这里）
- 总体状态: {PASS | PASS_WITH_WARNINGS | FAIL}
- MUST_FIX: {n}
- SHOULD_FIX: {n}
- INFO: {n}
- 建议下一步: {`migrate` | `upgrade` | `self-improve` | `none`}

## 1.5) 图谱摘要（结论前置依据）
- 图谱文件: `{<project>/.claude/skills/pensieve/SKILL.md#Graph}`
- 扫描笔记数: {n}
- 发现链接数: {n}
- 已解析链接: {n}
- 未解析链接: {n}
- 图谱观察: {一句话说明}

## 2) 需优先处理（MUST_FIX，按优先级）
1. [D-001] {一句话问题}
文件: `{path}`
依据: `{rule source}`
修复: {一句话修复建议}

## 3) 建议处理（SHOULD_FIX）
1. [D-101] {一句话问题}（`{path}`）

## 4) 迁移与结构检查
- 发现旧路径: {yes/no}
- 发现新旧并行: {yes/no}
- 发现非项目级 skill 根: {yes/no}
- 发现独立 graph 文件: {yes/no}
- 缺失关键目录: {yes/no}
- MEMORY.md 缺失/漂移: {yes/no}
- 建议动作: {`migrate` | `upgrade` | `self-improve` | `none`}

## 5) 三步行动计划
1. {第一步（可执行的具体操作）}
2. {第二步}
3. {第三步}

## 6) 规则命中明细（附录）
| ID | 严重级别 | 分类 | 文件/路径 | 规则来源 | 问题 | 修复建议 |
|---|---|---|---|---|---|---|

## 7) 图谱断链明细（附录）
| 源文件 | 未解析链接 | 备注 |
|---|---|---|

## 8) Frontmatter 快检结果（附录）
| 文件 | 级别 | 检查码 | 问题 |
|---|---|---|---|
```

2. `FAIL` 且结构迁移相关时 `下一步` 优先 `migrate`；插件键相关时优先 `upgrade`；`decision`/`pipeline` 断链至少 `MUST_FIX`
3. Doctor 不改用户数据文件；仅允许自动维护 `SKILL.md` 与 auto memory

## Phase 3.5: 维护项目级 SKILL + MEMORY
**Goal**: 报告输出后同步 SKILL 与 MEMORY。
**Actions**:
1. 执行：
```bash
bash <SYSTEM_SKILL_ROOT>/tools/project-skill/scripts/maintain-project-skill.sh --event doctor --note "doctor summary: status={PASS|PASS_WITH_WARNINGS|FAIL}, must_fix={n}, should_fix={n}"
```
2. 仅维护 `.claude/skills/pensieve/SKILL.md` 与 `~/.claude/projects/<project>/memory/MEMORY.md` 引导块

## Phase 4: Auto Memory 补齐检查
**Goal**: 确认 auto memory 含 Pensieve 引导块，缺失/漂移为 MUST_FIX 不可降级。
**Actions**:
1. 读取 `<SYSTEM_SKILL_ROOT>/SKILL.md` frontmatter `description` 与项目 `MEMORY.md`
2. 检查引导块含系统 `description` 一致描述及"优先调用 `pensieve` skill"引导语
3. 缺失或漂移：判定 `MUST_FIX`，执行对齐写入（仅维护引导块，不改其他内容）
