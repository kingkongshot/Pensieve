# Maxims（准则）

跨项目、跨场景的长期行动原则。

## 目的

Maxim 不是技术细节，而是团队“默认行为”的抽象：

- 跨项目：不依赖单一仓库
- 跨问题：面对未知问题仍可指导决策
- 可传承：新人读完即可执行

Maxim 的价值是降低决策成本，避免每次从零推导。

> 说明：插件不内置固定 maxim 文件。安装/迁移时会在 `.claude/skills/pensieve/maxims/` 种子化初始准则，用户可自由编辑。

## 语义定位（MUST 层）

`maxim` 承载 MUST（约束层）：必须遵守的底线与行为约束，即“必须这样”。

判定要点：
- 违反会显著提升回归风险或破坏协作基线
- 不是一次性项目偏好（那是 `decision`）
- 不是客观机制描述（那是 `knowledge`）

## 捕获标准

### 自检问题

以下问题都为“是”，才适合作为 maxim：

1. **与项目无关**：换项目仍成立？
2. **与语言无关**：换语言仍成立？
3. **与领域无关**：换技术域仍成立？
4. **能指导未来**：对未知问题仍有指导性？
5. **可一句话表达**：能说清楚且可执行？

任一“否”更适合记为 `decision`，而非 `maxim`。

## 关系与演化

| 方向 | 说明 |
|---|---|
| Decision -> Maxim | 重复出现的决策可上升为准则 |
| Maxim <-> Knowledge | 准则可吸收外部最佳实践 |

## 编写规范

### 目录结构（项目级）

```
.claude/skills/pensieve/maxims/
├── {maxim-conclusion-a}.md
└── {maxim-conclusion-b}.md
```

说明：
- 不再要求 `custom.md` 索引。
- 每条 maxim 一个独立文件。

### 单条准则文件格式（推荐）

每条 maxim 建议包含：
- **标题**：一句话结论
- **单行结论**：可直接执行的明确结论
- **指导规则 / 边界**：何时适用、何时不适用

```markdown
# {一句话结论}

## 一句话结论
> {团队可直接执行的一句话}

## 指导规则
- Rule 1
- Rule 2

## 举例（可选，推荐用于通用化）
- 场景 A：{具体例子}（详见 [[knowledge/xxx/content]]）
- 场景 B：{跨领域类比}
- 场景 C：{跨领域类比}

## 边界
- 以下情况不适用...

## 上下文链接（推荐）
- 基于：[[相关 decision 或 knowledge]]
- 导致：[[相关 pipeline 或后续 decision]]
- 相关：[[相关 maxim]]
```

> **举例的用途**：当 maxim 的自检暴露领域特定性（如"仅适用于 UI"），通过添加跨领域举例可以将原理提升到通用层级。标题和结论保持通用，举例提供可执行的落地场景。举例中可用 `[[knowledge/...]]` 链接到项目知识库中的实际案例。

### 冲突处理（无索引模式）

当两条 maxim 冲突时，按以下顺序判断：

1. 更具体场景的 maxim 优先于更抽象 maxim
2. 有明确 `decision`/`knowledge` 追溯证据的 maxim 优先
3. 仍冲突时，补一条 `decision` 明确当前项目优先级

### 示例

```markdown
# Preserve user-visible behavior as a hard rule

## 一句话结论
> 任何未预期的用户可见行为变化都应视为缺陷。

## 指导规则
- 重构期间保持用户可见行为稳定。
- 如果必须改变行为，必须显式说明并评审。

## 边界
- 仅在用户明确批准变更时允许改变行为。
```

## 备注

- Maxim 应保持稀缺，不要高频新增
- 如果某条 maxim 经常被改写，说明抽象层级可能不对
- 链接是推荐项（非强制），但建议保留来源脉络
- **链接类型严格对应目标类型**：`基于` → knowledge/decision，`导致` → pipeline/decision，`相关` → maxim。Maxim 之间不要用 `基于` 或 `导致`，否则会形成循环依赖且语义混乱

推荐追溯格式：

```markdown
Derived from: [[2026-01-22-do-not-break-user-visible-behavior]], [[knowledge/taste-review/content]]
```

---

## Maxim 文件位置

- 项目级条目：`.claude/skills/pensieve/maxims/*.md`（永不覆盖）
