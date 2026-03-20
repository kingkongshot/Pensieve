# Short-Term（短期记忆）

`short-term/` 是新知识的暂存区。`self-improve` 新建的条目默认进入这里。

## 工作流

1. `self-improve` 新建条目 → 写入 `short-term/{type}/`
2. 条目带 `created` 日期，默认 7 天后算到期
3. 到期条目通过 session hook / doctor / commit pipeline 提醒
4. 人工决定 promote（mv 到长期目录）或 delete

## 存储位置

`short-term/` 镜像长期目录结构：

```text
<project>/.pensieve/short-term/
├── maxims/
├── decisions/
├── knowledge/
└── pipelines/
```

文件命名与对应长期目录一致（如 `decisions/{date}-{statement}.md`）。

## 链接规则

`[[...]]` 链接**不含** `short-term/` 前缀：

```markdown
- 基于：[[decisions/2026-03-16-foo]]     ✅
- 基于：[[short-term/decisions/2026-03-16-foo]]  ❌
```

图谱解析 short-term 内文件时 strip 前缀，与长期文件共享节点 ID。
promote 时只需 `mv` 文件，零引用更新。

## TTL 规则

- 基于 `created` 日期 + 7 天（schema.json `short_term.default_ttl_days`）
- 仅用于提醒，不自动移动或删除
- frontmatter tags 含 `seed` 的文件跳过 TTL 检查

## 何时跳过 short-term

- 修改已有长期目录中的文件：直接原地修改
- 用户明确要求直接写入长期目录
