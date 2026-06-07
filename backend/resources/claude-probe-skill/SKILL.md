---
name: cc-mimo-rescue-probe
description: Probe Claude Code paths and image-helper capability for cc-mimo-rescue setup.
---

When asked to run this probe, inspect the current Claude Code environment and return only JSON with these fields:

```json
{
  "cwd": "",
  "claude_home_guess": "",
  "global_memory_candidates": [],
  "project_memory_candidates": [],
  "session_or_transcript_candidates": [],
  "available_agents": [],
  "supports_haiku_agent": null,
  "available_ocr_tools": [],
  "notes": []
}
```

Do not read binary images. Do not print secrets, tokens, API keys, or full environment dumps.
