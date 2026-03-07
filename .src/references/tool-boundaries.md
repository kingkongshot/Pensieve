# Tool Boundaries

| Tool | Responsible for | Not responsible for |
|---|---|---|
| `init` | Initializing root directory, seeding default content, producing first-round exploration input | Does not directly write business conclusions |
| `upgrade` | Refreshing skill source code | Does not perform structural migration, does not give PASS/FAIL |
| `migrate` | Legacy path migration, key file alignment, remnant cleanup | Does not update versions, does not give PASS/FAIL |
| `doctor` | Structural and format health check, outputs fixed report | Does not modify business code |
| `self-improve` | Distilling maxim/decision/knowledge/pipeline | Does not replace init/migrate/doctor |

## Common redirects

| User request | Correct tool |
|---|---|
| "How to install/reinstall Pensieve" | Read `.src/references/skill-lifecycle.md` first, then go to `init` |
| "Upgrade Pensieve" | `upgrade` |
| "How to update Pensieve" | Read `.src/references/skill-lifecycle.md` first, then go to `upgrade` |
| "Clean up old paths/old graph" | `migrate` |
| "Check if data has issues" | `doctor` |
| "Distill this experience" | `self-improve` |
