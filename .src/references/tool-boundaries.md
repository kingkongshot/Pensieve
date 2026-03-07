# 工具边界

| 工具 | 负责什么 | 不负责什么 |
|---|---|---|
| `init` | 初始化根目录、种子化默认内容、产出首轮探索输入 | 不直接写业务结论 |
| `upgrade` | 刷新 skill 源码 | 不做结构迁移，不给 PASS/FAIL |
| `migrate` | 旧路径迁移、关键文件对齐、残留清理 | 不更新版本，不给 PASS/FAIL |
| `doctor` | 结构与格式体检，输出固定报告 | 不改业务代码 |
| `self-improve` | 沉淀 maxim/decision/knowledge/pipeline | 不替代 init/migrate/doctor |

## 常见重定向

| 用户请求 | 正确工具 |
|---|---|
| “怎么安装/重装 Pensieve” | 先读 `.src/references/skill-lifecycle.md`，再走 `init` |
| “升级 Pensieve” | `upgrade` |
| “怎么更新 Pensieve” | 先读 `.src/references/skill-lifecycle.md`，再走 `upgrade` |
| “清理旧路径/旧 graph” | `migrate` |
| “检查数据是否有问题” | `doctor` |
| “把这次经验沉淀下来” | `self-improve` |
