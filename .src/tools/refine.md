---
description: 精炼 Pensieve 知识库：通过五问决策审阅条目（triage），通过抽象和归纳压缩知识（compress）。
---

# Refine 工具

> 工具边界见 `.src/references/tool-boundaries.md` | 共享规则见 `.src/references/shared-rules.md`

## Use when

- session start 提醒有到期短期记忆
- doctor 报告 `short_term_due_refine`
- 用户请求 "整理" / "triage" / "去重" / "清理" / "发现关联"
- 定期维护知识库质量

---

## 子任务 1：Triage — 五问决策审阅

对条目逐个运行五问决策。适用于短期到期项、指定条目、或全库审阅。

### 范围

| 场景 | 扫描范围 |
|---|---|
| 短期到期 | `short-term/` 下 `created + 7天 < today` 的条目（跳过 tags 含 `seed`） |
| 指定条目 | 用户指定的文件 |
| 全库 | `maxims/` + `decisions/` + `knowledge/` + `pipelines/` + `short-term/` |

### 五问决策

依次回答，命中终止条件即停止。

| # | 问题 | 否 → | 是 → |
|---|---|---|---|
| Q1 | 删掉它，未来是否会重复踩坑或重复探索？ | **DELETE** | Q2 |
| Q2 | 它是否有证据支撑（代码、文档、实验结果）？ | **DELETE** | Q3 |
| Q3 | 它是否已被现有条目覆盖？ | Q4 | **DELETE**（合并到已有条目） |
| Q4 | 写入时的上下文是否仍然成立？ | **DELETE** | Q5 |
| Q5 | 它是否符合目标层的内容规范？ | 补齐或 **DELETE** | **KEEP/PROMOTE** |

Q5 规范文件：

| type | 规范 |
|---|---|
| `maxim` | `.src/references/maxims.md` |
| `decision` | `.src/references/decisions.md` |
| `knowledge` | `.src/references/knowledge.md` |
| `pipeline` | `.src/references/pipelines.md` |

### 执行

- **PROMOTE**（short-term 条目）：`mv short-term/{type}/file.md {type}/file.md`，status 改 `active`
- **KEEP**（长期条目）：无需操作
- **补齐**：按规范补齐缺失内容，然后 KEEP/PROMOTE
- **DELETE**：删除文件。若 Q3 判定重复，将有价值内容合并到已有条目后再删除

---

## 子任务 2：Compress — 压缩知识库

从整体视角审视所有条目，通过抽象和归纳**减少总条目数，同时提升信息密度**。

### 三种压缩手法

#### A. 向上抽象：多个条目 → 一个更高层条目

多个条目呈现同一模式时，提炼出涵盖它们的更高层抽象，原条目可删除。

> 例：三条 knowledge 分别记录"API A 必须幂等""API B 必须幂等""API C 必须幂等"
> → 提炼一条 maxim "所有对外 API 必须幂等"，删除三条 knowledge。

#### B. 提取共用：重复内容 → 独立条目 + 引用

多个条目引用相同的事实或前提时，将共用部分提取为独立 knowledge，原条目改为 `[[...]]` 引用。

> 例：三条 decision 都重复描述了同一段认证流程
> → 提取为 `knowledge/auth-flow/content.md`，三条 decision 改为 `基于：[[knowledge/auth-flow/content]]`。

#### C. 消除特殊情况：发现深层原理取代表面规则

从整体视角发现看似不同的条目其实是同一深层原理的特殊情况，写出深层原理，删除表面规则。

> 例：一条 maxim "不要在 handler 里直接操作数据库" + 一条 decision "service 层统一管理事务"
> → 它们都是"关注点分离"的特殊情况。写一条更深的 maxim，原条目降级为 `[[...]]` 引用或删除。

### 执行

1. 读取所有长期目录 + short-term 的条目，建立全局视图
2. 读取图谱（`.pensieve/.state/pensieve-user-data-graph.md`），理解链接结构
3. 寻找压缩机会（A/B/C 三种手法）
4. 对每个压缩方案：
   - 说明涉及的条目和压缩手法
   - 写出新条目（按目标层规范，走 short-term）
   - 对被替代的旧条目运行五问 Q1-Q3，确认可删除后删除
   - 保留 `[[...]]` 链接连通性

---

## 刷新状态

任何写操作后，刷新项目状态：

```bash
bash "${PENSIEVE_SKILL_ROOT:-$HOME/.claude/skills/pensieve}/.src/scripts/maintain-project-state.sh" --event sync --note "refine: 描述"
```
