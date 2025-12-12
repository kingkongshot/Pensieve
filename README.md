# 引导词仓库 (Prompts Collection)

[![Run in Smithery](https://smithery.ai/badge/skills/kingkongshot)](https://smithery.ai/skills?ns=kingkongshot&utm_source=github&utm_medium=badge)


一个精心组织的引导词集合，帮助提升AI协作效率和质量。

## 📢 更新日志

### 2025-11-06
- ✨ 新增基于用户自身 MBTI 人格缺陷的 Linus Torvalds 风格引导词
- 🎨 提高了模型输出的可读性。

## 📋 快速导航

### 🛠️ 开发工具类
- **[Claude](./prompts/claude/)** - Claude AI 开发规范、Agent配置与自定义命令
- **[Kiro](./prompts/kiro/)** - Kiro 三阶段工作流规范（需求→设计→实施）

### 🎨 设计可视化类  
- **[Obsidian Canvas](./prompts/visualization/obsidian-canvas/)** - 使用Obsidian Canvas绘制功能框架图

## 📂 目录结构

```
prompts/
├── Agents/              # Agent 引导词配置
│   └── AGENTS.md        # Linus Torvalds 风格的基础引导词
├── claude/              # Claude AI 相关
│   ├── agents/          # Agent 配置
│   └── commands/        # 自定义命令
├── kiro/                # Kiro 工作流
│   ├── spec.md          # 英文规范
│   └── spec_zh.md       # 中文规范
└── visualization/       # 可视化工具
    └── obsidian-canvas/ # Obsidian Canvas图表
```

## 🌟 精选推荐

### 开发规范
- [Linus Torvalds 风格引导词](./Agents/AGENTS.md) - Linus Torvalds 风格的基础引导词
- [Kiro工作流](./prompts/kiro/spec_zh.md) - 结构化的需求→设计→实施流程

### Claude Code Agent 配置
- [Memory Network Builder](./prompts/claude/agents/memory-network-builder.md) - 配合 Obsidian构建知识网络的Agent
- [Library Usage Researcher](./prompts/claude/agents/library-usage-researcher.md) - 搜索真实代码和官方文档，提供基础说明和巧妙用法的Agent

### 自定义命令
- [Commit-As-Prompt](./prompts/claude/commands/commit-as-prompt.md) - 将Git提交转化为结构化Prompt

### 可视化工具
- [功能框架图绘制](./prompts/visualization/obsidian-canvas/使用%20Obsidian%20Canvas%20绘制功能框架图.md) - 编写 obsidian canvas 图透视项目情况

## 👤 联系作者

- **微信**: kingkongshot
- **推特 (Twitter/X)**: [@Naaaarukaru](https://x.com/Naaaarukaru)
- **小红书**: 王乔治 (ID: 9538421460)

## 💬 交流群

欢迎加入微信群一起vibe coding：

<img src="https://github.com/kingkongshot/prompts/blob/main/QRCode.png" alt="微信交流群二维码" width="200">

## 📄 许可证

本仓库采用 Apache License 许可证，详见 [LICENSE](./LICENSE) 文件。
