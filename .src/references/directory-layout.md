# 目录结构

Pensieve v2 把系统代码（用户级）和项目数据（项目级）分离。

## 两个锚点

- **skill 根目录**（`~/.claude/skills/pensieve/`）：全局 git clone，系统文件，由 git 跟踪
- **项目数据**（`<project>/.pensieve/`）：每个项目独立，可纳入版本控制

## 布局

```text
~/.claude/skills/pensieve/          # 用户级（全局，单次安装）
├── SKILL.md                        #   静态：frontmatter + 路由（tracked）
├── .src/                           #   系统脚本、模板、规范（tracked）
│   ├── core/
│   ├── scripts/
│   ├── templates/
│   ├── references/
│   └── tools/
└── agents/                         #   agent 配置（tracked）

<project>/.pensieve/                # 项目级（每项目独立，可纳入版本控制）
├── maxims/                         #   工程准则（长期）
├── decisions/                      #   架构决策（长期）
├── knowledge/                      #   缓存的探索结果（长期）
├── pipelines/                      #   可复用工作流（长期）
├── short-term/                     #   新结论暂存区（镜像长期目录结构）
│   ├── maxims/
│   ├── decisions/
│   ├── knowledge/
│   └── pipelines/
├── state.md                        #   动态：生命周期状态 + 知识图谱（generated）
├── .gitignore                      #   只忽略 .state/
└── .state/                         #   运行时产物（gitignored）

<project>/.claude/agents/           # Claude Code 自定义 agent（init 时从模板播种）
└── pensieve-wand.md                #   知识检索 agent（双系统决策）
```

## 说明

- `.src/`、`agents/`、`SKILL.md` 是 tracked 系统文件，跟着 `git pull` 在 skill 根目录更新
- `SKILL.md` 是**静态、tracked** 文件——skill 接口声明；不由脚本生成
- `state.md` 是**动态、生成型**文件，位于 `<project>/.pensieve/state.md`，由 `init/doctor/migrate/upgrade/self-improve/sync` 刷新
- `maxims/decisions/knowledge/pipelines` 是长期用户数据，初始化后本地创建
- `short-term/` 是新结论暂存区，镜像长期目录结构；条目基于 `created` + 7天 TTL 提醒整理
- `.state/` 位于 `.pensieve/` 内部，用来存放 doctor 报告、迁移备份、session marker、自动生成图谱等运行期产物
- `maintain-project-state.sh` 会重写 `state.md`
- `generate-user-data-graph.sh` / `doctor` 默认把图谱输出到 `.pensieve/.state/pensieve-user-data-graph.md`
- 只要某个目录包含 `.src/manifest.json`，它就是当前系统 skill 根目录
- `init` 检测到 `<project>/.claude/` 存在时，会将 `.src/templates/agents/*.md` 播种到 `<project>/.claude/agents/`
