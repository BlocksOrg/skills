---
name: blocks-api
description: >
  Use when working with the `Blocks` to inspect existing agent sessions:
  fetch a session by ID, read its transcript (user prompts and assistant replies),
  and drill into tool calls when more detail is needed. Trigger on "Blocks session",
  "Blocks API", "fetch blocks session transcript" or any request to read what a
  Blocks agent did in a session. Requires BLOCKS_API_KEY.
license: MIT
metadata:
  version: "0.1.0"
---

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
| 401 | Missing or malformed `Authorization` header |
| 403 | Bad key, or key for a different environment |
| 404 | Session not in your workspace, or artifact not attached to it |
| 422 | Bad `limit`, `page`, `type`, `role`, `direction`, non-UUID id, comma lists |
