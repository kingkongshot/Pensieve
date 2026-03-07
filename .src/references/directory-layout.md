# 目录结构

Pensieve 有三个固定锚点：

- **skill 根目录**：git clone 下来的系统文件
- **用户数据目录**：跟 skill 根并列存在、但被 git 忽略的本地知识数据
- **project 根目录**：隐藏运行时状态

推荐安装方式是直接把 `main` 分支 clone 到项目内的 `.claude/skills/pensieve/`。默认布局如下：

```text
<skill-root>/
├── SKILL.md                # 生成型路由文件（generated, gitignored）
├── .src/                   # 系统脚本、模板、规范（tracked）
├── agents/                 # agent 配置（tracked）
├── maxims/                 # 用户数据（ignored）
├── decisions/              # 用户数据（ignored）
├── knowledge/              # 用户数据（ignored）
└── pipelines/              # 用户数据（ignored）

<project-root>/
└── .state/                 # 运行时状态、报告、marker、缓存、图谱快照
```

说明：

- `.src/`、`agents/` 是 tracked 系统文件，跟着 `git pull` 更新
- 根目录 `SKILL.md` 是固定位置的生成文件，由 `init/doctor/migrate/upgrade/self-improve/sync` 刷新，并由 `.gitignore` 忽略
- `maxims/decisions/knowledge/pipelines` 是用户数据，初始化后本地创建，并由根 `.gitignore` 忽略
- `.state/` 默认位于项目根目录，用来存放 doctor 报告、迁移备份、session marker、自动生成图谱等运行期产物
- `maintain-project-skill.sh` 会重写根目录 `SKILL.md`
- `generate-user-data-graph.sh` / `doctor` 默认把图谱输出到 `.state/pensieve-user-data-graph.md`
- 只要某个目录包含 `.src/manifest.json`，它就是当前系统 skill 根目录；`SKILL.md` 可以后生成

## 项目内旧路径（legacy）

在项目工作区里，以下路径视为旧残留，应由 `migrate` 清理：

- `skills/pensieve/`
- `.claude/pensieve/`
- 独立 graph 文件：`_pensieve-graph*.md`、`pensieve-graph*.md`、`graph*.md`
