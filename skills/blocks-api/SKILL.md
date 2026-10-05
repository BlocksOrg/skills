---
name: blocks-api
description: >
  Use when working with `Blocks` to inspect existing agent sessions:
  fetch a session by ID, read its transcript (user prompts and assistant replies),
  and drill into tool calls when more detail is needed. Trigger on "Blocks session",
  "Blocks API", "fetch blocks session transcript" or any request to read what a
  Blocks agent did in a session. Requires BLOCKS_API_KEY.
license: MIT
metadata:
  version: "0.2.0"
---

## Step 0: freshness check

Before anything else, run the skill's own update check once, resolving the path relative to this file's directory:

```bash
bash scripts/skill-freshness-check.sh
```

It refreshes this skill from its source at most once a day, never prompts, and always exits 0. If it prints a note, relay it to the user (the refreshed instructions take effect next session). If it prints nothing, say nothing. Continue with the task regardless of the outcome. Set `BLOCKS_SKILLS_NO_UPDATE=1` to disable it.

## Setup

```bash
BASE_URL="${BLOCKS_API_BASE_URL:-https://api.blocks.team}"
AUTH="Authorization: ApiKey $BLOCKS_API_KEY"   # Settings > API Keys in the Blocks dashboard
```

All endpoints live under `/rest/v1`, return JSON, and are rate limited to 100 requests/minute per key.
Array query params repeat the key (`type=a&type=b`); comma lists are rejected.
Endpoint reference: https://docs.blocks.team/rest-api/quick-start

## Skills

Read the file for the task at hand. Each one is a complete, ordered walkthrough.

| Skill | What it covers |
| --- | --- |
| [`references/sessions-get-overview.md`](references/sessions-get-overview.md) | Get up to speed on an existing session by ID. Fetch its metadata, download the latest plan the agent wrote, read the transcript as a compact overview of user prompts and assistant replies, then pull tool calls, single threads, or new messages only when you need more detail. |

## Errors

| Status | Meaning |
| --- | --- |
| 401 | Missing `Authorization` header |
| 403 | Malformed header (e.g. `Bearer`), bad key, or key for a different environment |
| 404 | Session not in your workspace, or artifact not attached to it |
| 422 | Bad `limit`, `page`, `type`, `role`, `direction`, non-UUID id, comma lists |
