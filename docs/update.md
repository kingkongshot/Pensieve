# Update Guide

## Plugin (Marketplace)

If you installed via Marketplace:

```bash
claude plugin marketplace update kingkongshot/Pensieve
claude plugin update pensieve@kingkongshot-marketplace --scope user
```

Then restart Claude Code to apply updates.

If you are running commands from inside a Claude Code session (model executing on your behalf), `claude` detects the nested session and blocks the command. Prefix with `CLAUDECODE=` to clear the detection variable:

```bash
CLAUDECODE= claude plugin marketplace update kingkongshot/Pensieve
CLAUDECODE= claude plugin update pensieve@kingkongshot-marketplace --scope user
```

These commands are safe to run repeatedly; if already on the latest version, they produce no changes.

> If you installed with project scope, replace `--scope user` with `--scope project`.

If you installed via `.claude/settings.json` URL, restart Claude Code to get updates.

### Update Failure Fallback

If the update command fails (network, permissions, CLI version issues, etc.), check the latest documentation on GitHub before continuing:

- [docs/update.md (main branch)](https://github.com/kingkongshot/Pensieve/blob/main/docs/update.md)

Do not proceed with the Upgrade tool until the update failure is resolved.

---

## System Skills

System prompts (tools/scripts/system knowledge) are packaged inside the plugin and update with the plugin.

---

## After Updating

Restart Claude Code and say `loop` to verify the update.

### Scripted Shortest Path (Recommended)

If you want to minimize LLM involvement, run directly:

```bash
bash <SYSTEM_SKILL_ROOT>/tools/upgrade/scripts/run-upgrade.sh
```

To run health check only (can serve as a strict CI check):

```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict
```

`run-upgrade.sh` automatically executes: version comparison -> pull latest -> clean up legacy version residue (no doctor).

**Upgrade core logic (scripted simplified version)**:
- Only performs version-related actions: compare pre/post upgrade versions + pull latest version
- Only performs legacy version cleanup: old plugin keys, old plugin names, old directories and historical residue files
- Does not perform pre-upgrade structure checks, and does not run Doctor during the Upgrade stage
- After upgrade completes, the user manually runs Doctor for health check

Then:
- Prefer running Upgrade first (do not treat Doctor as a pre-upgrade prerequisite)
- Manually run Doctor once after upgrade completes
- If Doctor reports migration/structure issues, continue fixing per the report
- If Doctor passes, run Self-Improve as needed
- After running Upgrade, Doctor, or Self-Improve, the following should be maintained:
  - Project-level `.claude/skills/pensieve/SKILL.md` (fixed routing + graph)
  - The Pensieve guidance block in Claude auto memory `~/.claude/projects/<project>/memory/MEMORY.md` (description aligned with system skill `description`)

Recommended order:
1. Run Upgrade (version comparison + pull + cleanup)
2. If a version was upgraded, restart Claude Code
3. Run Doctor once (required, manually triggered)
4. If Doctor reports issues, fix per the report then rerun Doctor
5. Run Self-Improve only when you want to capture reusable improvements

If you are guiding the user, remind them they only need to express these intents:
- Loop execution
- Doctor health check
- Self-Improve capture
- Upgrade migration
- View graph (read the project-level `SKILL.md` under `## Graph`)

---

## Preserved User Data

Project user data in `.claude/skills/pensieve/` is never overwritten by plugin updates:

| Directory | Content |
|------|------|
| `.claude/skills/pensieve/maxims/` | Custom maxims |
| `.claude/skills/pensieve/decisions/` | Decisions |
| `.claude/skills/pensieve/knowledge/` | Custom knowledge |
| `.claude/skills/pensieve/pipelines/` | Project pipelines |
| `.claude/skills/pensieve/loop/` | Loop history |
