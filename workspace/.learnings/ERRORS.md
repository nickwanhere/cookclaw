# Errors

Command failures and integration errors. Appended by the `self-improvement` skill when something fails unexpectedly. Dreaming reads this and promotes recurring errors to `MEMORY.md` so the agent learns to avoid the same mistakes.

**Entry format**:

```markdown
## [ERR-YYYYMMDD-XXX] skill_or_command_name

**Logged**: ISO-8601 timestamp
**Priority**: high
**Status**: pending
**Area**: frontend | backend | infra | tests | docs | config

### Summary
Brief description of what failed.

### Command
The exact command or operation attempted (redact secrets).

### Expected
What should have happened.

### Actual
What actually happened (error message, exit code, partial output).

### Suggested Action
Fix, retry strategy, or fallback.

---
```

---

_(empty — entries appended by the self-improvement skill on failures)_
