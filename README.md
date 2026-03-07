# Pensieve Claude Plugin

Claude Code hooks for Pensieve. Provides SessionStart, PreToolUse, PostToolUse automation.

## Install

```bash
claude plugin marketplace add kingkongshot/Pensieve#claude-plugin
claude plugin install pensieve@kingkongshot-marketplace --scope project
```

## Prerequisites

This plugin requires the Pensieve skill to be installed first:

```bash
git clone https://github.com/kingkongshot/Pensieve.git .claude/skills/pensieve
```

See [main branch](https://github.com/kingkongshot/Pensieve) for full documentation.

## What it provides

- **SessionStart**: marker check
- **PreToolUse**: Explore/Plan prompt injection
- **PostToolUse**: graph and auto memory sync

## License

MIT
