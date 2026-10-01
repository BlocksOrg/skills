---
name: blocks-api
description: >
  Use when working with the Blocks REST API to inspect existing agent sessions:
  fetch a session by ID, read its transcript (user prompts and assistant replies),
  and drill into tool calls when more detail is needed. Trigger on "Blocks session",
  "Blocks API", "fetch session transcript", "session ID", or any request to read
  what a Blocks agent did in a session. Requires BLOCKS_API_KEY.
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

## Getting up to speed on a session

Do these in order and stop as soon as you have enough:

1. Fetch the session for metadata and `plan_artifact_ids`.
2. If there is a plan, read it first. It holds most of the useful information.
3. Read the transcript overview (one call).
4. Pull tool calls only if you still need to know how something was done.

## 1. Fetch a session

```bash
curl "$BASE_URL/rest/v1/sessions/$SESSION_ID" -H "$AUTH"
```

Useful fields: `title`, `pull_requests`, `source_url`, `is_archived`,
`plan_artifact_ids`, `session_html_url`, `_links.messages`.
`thread_id` and `_links.final_message` are always `null` on this endpoint.

## 2. Read the plan, if there is one

`plan_artifact_ids` has one entry per plan the agent wrote, already pointing
at that plan's latest version, oldest plan first. Take the last entry.

```bash
PLAN_ARTIFACT_ID=$(curl -s "$BASE_URL/rest/v1/sessions/$SESSION_ID" -H "$AUTH" | jq -r '.plan_artifact_ids[-1]')
PLAN_URL=$(curl -s "$BASE_URL/rest/v1/sessions/$SESSION_ID/artifacts/$PLAN_ARTIFACT_ID" -H "$AUTH" | jq -r '.url')
curl -s "$PLAN_URL"   # presigned, valid 6 days, NO Authorization header
```

The artifact response includes `kind` (`plan` or `file`), `file_name`,
`mime_type`, `plan_id`, `created_at`. Confirm `kind == "plan"`.
Skip this step when `plan_artifact_ids` is empty.

## 3. Transcript overview

```bash
curl "$BASE_URL/rest/v1/sessions/$SESSION_ID/messages?type=message&role=user&role=assistant" -H "$AUTH"
```

- Returns user prompts and assistant messages, oldest first. Do not pass `direction`.
- Each thread (`chat_thread_id`) is one user turn. The last assistant `message`
  in a finished thread is its final reply.
- Skip items with `chat_thread_id: null` (system notices).
- A thread whose last item is the user prompt is still running.

Why `type=message` and not the API default (`message,final_message`):
the last `message` of a finished thread is identical to its `final_message`,
so the default doubles the final text.

**Fallback if `role=user&role=assistant` returns 422** (older deployments):
make two calls, `?type=message&role=user` and `?type=message`, merge by `ts`.

## 4. More detail, only when needed

- **Tool calls:** add `type=tool_call`, e.g. `?type=message&type=tool_call&role=user&role=assistant`.
  `message` is a JSON string `{"__name__": "<tool>", "input": "<args>"}`. Invocation only, no result.
- **Outcomes only:** `?type=final_message` gives one completed reply per thread.
- **One thread:** `?thread_id=<id>` or `/sessions/{id}/threads/{thread_id}/messages`.

## Pagination and polling

`page`, `limit` (1-100, default 50), `meta.total_pages`.
`_links.new_messages.href` carries the `gts` cursor for incremental reads, but only the cursor.
Both `_links` drop your filters. Rebuild pagination and polling URLs yourself.

## Errors

| Status | Meaning |
| --- | --- |
| 401 | Missing or malformed `Authorization` header |
| 403 | Bad key, or key for a different environment |
| 404 | Session not in your workspace, or artifact not attached to it |
| 422 | Bad `limit`, `page`, `type`, `role`, `direction`, non-UUID id, comma lists |

Array params repeat the key (`type=a&type=b`). Unknown thread id returns 200 with empty `items`.

## Reference

`references/sessions.md` has full field tables, Python recipes, and verified quirks.
Docs: https://docs.blocks.team/rest-api/sessions/get, .../sessions/messages, .../sessions/artifacts
