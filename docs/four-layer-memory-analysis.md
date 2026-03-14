# 四层记忆架构分析

> 状态：待决策
> 创建：2026-03-11
> 关联：`docs/maxim-and-auto-memory-analysis.md`（已删除，本文档替代）

---

## 1. 分析目标

评估 Pensieve 四层语义模型（IS/WANT/MUST/HOW）的设计意图与执行现实是否对齐，识别 AI 误解风险，提出改进方向。

---

## 2. 现状总览

| 层 | 语义 | 准入标准 | 存储 | 种子模板 |
|---|---|---|---|---|
| Knowledge | IS（事实） | 不写就反复拖慢执行 | `knowledge/{name}/content.md` | taste-review |
| Decision | WANT（选择） | 删掉它未来更易犯错 | `decisions/{date}-{statement}.md` | 无 |
| Maxim | MUST（准则） | 跨项目+跨语言+回归风险+一句话 | `maxims/{conclusion}.md` | 4 条哲学原则 |
| Pipeline | HOW（流程） | 重复出现+顺序不可交换+可验证 | `pipelines/run-when-*.md` | reviewing-code, committing |

---

## 3. 逐层评价

### 3.1 Knowledge — 最清晰

- 定义干净：IS 语义 + "不写就反复拖慢" 准入标准
- "别把 knowledge 写成观点集，它必须能被验证或追溯" 是有效护栏
- **低风险**。唯一隐患是探索型知识的建议清单（状态转换、症状→根因→定位……）可能让 AI 过度形式化

### 3.2 Decision — 最成功

- 准入门槛合理，与 knowledge 边界清晰（事实 vs 选择）
- **"探索减负"是整个系统中最有价值的设计** — 强制记录"下次少问什么、少查什么、何时失效"
- **中低风险**。格式要求偏重，AI 可能为满足格式而填充低价值内容，但可接受

### 3.3 Maxim — 问题最大

详见下文第 4 节。

### 3.4 Pipeline — 精良但使用场景窄

- 三条准入标准清晰合理，`run-when-*` 命名直接暗示触发条件
- 两个种子 pipeline 是高质量示范
- **中风险**。格式要求非常重（frontmatter 8 字段 + 信号判断 + Task Blueprint + 失败回退 + 链接），创建成本高，与"不确定时先最小可运行版本"矛盾

---

## 4. Maxim 层的核心问题

### 4.1 设计意图与存储位置矛盾

| 维度 | 文档声称 | 实际情况 |
|---|---|---|
| 作用域 | "跨项目、跨语言" | 存储在 `<project>/.pensieve/maxims/` — 项目级目录 |
| 准入标准 | 四条同时满足 | 种子模板满足，但用户实践中几乎不可能新增 |
| 与 decision 关系 | "只在当前项目有效 → 那是 decision" | 很多 MUST 级规则是项目特有的（如"本项目 API 必须幂等"） |
| self-improve 分类 | AI 需判断 maxim vs decision | 门槛让 AI 几乎总选 decision |

### 4.2 三个具体误导

**误导 1：门槛过高，层级形同虚设**

"换语言仍成立" 把 maxim 限制在纯哲学层面。"所有 mutation 必须经过 command bus" 这种项目级硬规则被排除在外，但这恰恰是最需要标记为 MUST 的东西。

**误导 2：种子模板给出了错误的抽象层级范例**

四条种子 maxim 全是 Linus Torvalds 式的通用哲学。AI 因此认为 maxim 应该在这个抽象层级，不会写入具体的、可执行的项目准则。

**误导 3：与 CLAUDE.md 功能重叠**

CLAUDE.md 已包含相同的 Linus 哲学（好品味、never break userspace、实用主义、简洁至上）。种子 maxim 重复了相同理念。AI 看到两处相同指令，不确定优先级关系。

---

## 5. 四层交互问题

### 5.1 self-improve 时分类模糊

AI 被迫在语义层级（IS/WANT/MUST/HOW）和作用域（项目级/跨项目）两个维度同时判断。示例：

- "本项目的错误码必须用枚举" — 按定义是 decision（项目特有），但语义上是 MUST
- "React useEffect 清理顺序是 X" — 是 knowledge 还是该忽略（AI 下次可自己查）

### 5.2 链接要求增加写入摩擦

decision 和 pipeline 强制至少一条 `[[...]]` 链接。self-improve 发生在任务末尾，AI 不一定清楚该链接到哪个已有节点。可能结果：
- 链接指向不存在的节点（doctor 报 unresolved）
- 为满足要求写无意义链接
- 跳过 self-improve

### 5.3 写入无校验

self-improve 是唯一写入入口，但没有写入时校验。格式/链接/frontmatter 合规性全靠 doctor 事后检查。写入质量完全依赖 AI 对 reference spec 的理解。

---

## 6. 执行机制的隐含假设

1. **hook 注入不对称**：state.md 注入到 Explore/Plan agent，但它们无写入能力；实际写入在主对话中，主对话不一定读过 state.md
2. **种子模板一次性播种**：升级不覆盖，种子质量永久定义用户对每个层级的第一印象
3. **Python 依赖**：所有核心逻辑（doctor/migrate/maintain-project-state）需要 Python 3.8+

---

## 7. 待决策：Maxim 层的未来

### 方案 A：重定义为项目级 MUST

- 删除跨项目/跨语言要求
- 准入标准改为："本项目反复证明必须遵守的硬规则"
- 与 decision 的区别变成 MUST vs SHOULD
- 重写 `maxims.md` 和种子模板
- **代价**：需要重新设计种子模板内容

### 方案 B：合并到 Decision 层

- 删除 maxim 层
- decision 增加 `priority: must | should` 字段
- 种子哲学移入 CLAUDE.md 或 knowledge
- **代价**：decision 层变"胖"，但减少一个概念，简化 self-improve 分类

### 方案 C：保持现状但修正描述

- 承认 maxim 是"预装编码哲学"，不期望用户新增
- 删除 self-improve 向 maxim 写入的路径
- 降低维护成本但也降低了层级价值
- **代价**：maxim 变成只读层，存在感进一步降低

### 决策输入

需要回答的核心问题：**Pensieve 的用户是否真的需要一个独立的 MUST 层，还是 decision + priority 字段就够了？**

如果答案是"需要"，走方案 A。如果答案是"不需要"，走方案 B。方案 C 是妥协但不解决根本问题。
