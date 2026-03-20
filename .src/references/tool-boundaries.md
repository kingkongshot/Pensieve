# 工具边界

| 工具 | 负责什么 | 不负责什么 |
|---|---|---|
| `init` | 初始化项目 `.pensieve/` 目录、种子化默认内容、产出首轮探索输入 | 不直接写业务结论 |
| `upgrade` | 刷新全局 skill 源码（`~/.claude/skills/pensieve/`） | 不做结构迁移，不给 PASS/FAIL |
| `migrate` | 旧版本数据迁移、目录结构对齐、关键文件对齐 | 不更新版本，不给 PASS/FAIL |
| `doctor` | 结构与格式体检，输出固定报告 | 不改业务代码 |
| `self-improve` | 新建条目写入 `short-term/`，修改已有文件原地修改 | 不替代 init/migrate/doctor |
| `refine` | 精炼知识库：triage 五问审阅 + compress 压缩抽象 | compress 产出的新条目走 short-term |

## 常见重定向

| 用户请求 | 正确工具 |
|---|---|
| "怎么安装/重装 Pensieve" | 先读 `.src/references/skill-lifecycle.md`，再走 `init` |
| "升级 Pensieve" | `upgrade` |
| "怎么更新 Pensieve" | 先读 `.src/references/skill-lifecycle.md`，再走 `upgrade` |
| "迁移到 v2/清理旧路径" | `migrate` |
| "检查数据是否有问题" | `doctor` |
| "把这次经验沉淀下来" | `self-improve` |
| "整理/去重/压缩/精炼知识" | `refine` |
