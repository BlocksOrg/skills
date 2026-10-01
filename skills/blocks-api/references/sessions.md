# Sessions reference

Detail for the `blocks-api` skill: query parameters, response fields, Python
recipes, and quirks verified against the live API. One file per API area;
this one covers sessions, messages, and artifacts.

All requests: `Authorization: ApiKey $BLOCKS_API_KEY`, base URL
`https://api.blocks.team`, paths under `/rest/v1`.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/sessions/{session_id}` | Session metadata and `plan_artifact_ids` |
| GET | `/sessions/{session_id}/messages` | All messages on a session |
| GET | `/sessions/{session_id}/threads/{thread_id}/messages` | Messages on one thread |
| GET | `/sessions/{session_id}/artifacts/{artifact_id}` | Download link for a plan or file |

## Query parameters for `/messages`

Both message endpoints accept the same parameters. Array parameters repeat the
key: `type=message&type=tool_call`. Comma lists (`type=a,b`) return 422 and the
bracket form (`type[]=a`) is silently ignored.

| Param | Type | Default | Allowed | Notes |
| --- | --- | --- | --- | --- |
| `type` | string[] | `message`, `final_message` | `message`, `final_message`, `tool_call` | `tool_call` must be requested explicitly |
| `role` | string[] | `assistant` | `user`, `assistant` | Repeatable. Older deployments accept one value only and return 422 when repeated |
| `thread_id` | uuid | none | | Ignored on the threaded URL form. Unknown id returns 200 with empty `items` |
| `gts` | number | none | epoch seconds | Returns messages with `ts` strictly greater than the cursor |
| `page` | number | `1` | >= 1 | 1-indexed |
| `limit` | number | `50` | 1 to 100 | |
| `direction` | string | `asc` | `asc`, `desc` | Sorted by `ts`. Omit it for transcript reads |

## Session object

`GET /sessions/{session_id}`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid | |
| `title` | string | |
| `pull_requests` | object[] | PRs the session opened, each with `url` and `status` |
| `source_url` | string or null | Where the session was started from, if any |
| `is_archived` | boolean | |
| `is_private` | boolean | |
| `plan_artifact_ids` | uuid[] | Latest artifact for each plan the agent wrote, oldest plan first. Empty when no plan |
| `session_group_id` | uuid or null | Present, not yet documented publicly |
| `session_html_url` | string | Link to the session in the Blocks dashboard |
| `thread_id` | null | Always `null` on this endpoint |
| `created_at`, `updated_at` | ISO 8601 | |
| `_links.self` | object | `href` to this session |
| `_links.messages` | object | `href` to the session's messages |
| `_links.thread`, `_links.final_message` | null | Always `null` on this endpoint |

## Message object

Items in `/messages` responses.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid | |
| `chat_id` | uuid | The session |
| `chat_thread_id` | uuid or null | One thread per user turn. `null` for system notices, which you can skip |
| `task_id` | uuid | Agent invocation that produced the message |
| `role` | string | `user` or `assistant` |
| `type` | string | `message`, `final_message`, or `tool_call` |
| `message` | string | Body. For `tool_call` it is a JSON-encoded string `{"__name__": "<tool>", "input": "<args>"}` with no result |
| `ts` | number or null | Epoch seconds, may be fractional. Use as the `gts` cursor |
| `created_at`, `updated_at` | ISO 8601 | |

Response envelope: `items`, `meta` (`total`, `page`, `limit`, `total_pages`),
`_links.self` and `_links.new_messages` (the latter carries the `gts` cursor only).

## Artifact object

`GET /sessions/{session_id}/artifacts/{artifact_id}`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid | |
| `url` | string | Presigned download link, valid 6 days. Fetch without the `Authorization` header |
| `file_name` | string | e.g. `plan.md` |
| `file_path` | string | Path inside the agent's sandbox when captured |
| `file_size_in_kb` | number | |
| `mime_type` | string | e.g. `text/markdown` |
| `kind` | string | `plan` or `file` |
| `plan_id` | uuid or null | Groups iterations of one plan. `null` when `kind` is `file` |
| `created_at` | ISO 8601 | |

There is no list endpoint. Artifact IDs come from the session's
`plan_artifact_ids`. Older iterations of a plan stay downloadable by their own ID.

## Python recipes

```python
import json, os, requests

BASE_URL = os.environ.get("BLOCKS_API_BASE_URL", "https://api.blocks.team")
HEADERS = {"Authorization": f"ApiKey {os.environ['BLOCKS_API_KEY']}"}


def get(path, **params):
    r = requests.get(f"{BASE_URL}/rest/v1{path}", headers=HEADERS, params=params)
    r.raise_for_status()
    return r.json()


def all_items(path, **params):
    """Follow page/total_pages. Pass list values to repeat a key."""
    page = 1
    while True:
        body = get(path, page=page, limit=100, **params)
        yield from body["items"]
        if page >= body["meta"]["total_pages"]:
            return
        page += 1
```

### Fetch both roles, with the fallback for older deployments

```python
def messages(session_id, types):
    """User and assistant items of the given type(s), oldest first."""
    path = f"/sessions/{session_id}/messages"
    try:
        return list(all_items(path, type=types, role=["user", "assistant"]))
    except requests.HTTPError as e:
        if e.response.status_code != 422:
            raise
        # Older deployments: role is single-valued. Two calls, merge by ts.
        users = all_items(path, type=types, role="user")
        assistants = all_items(path, type=types)
        return sorted([*users, *assistants], key=lambda m: m["ts"] or 0)
```

### Get up to speed on a session

```python
def catch_up(session_id):
    session = get(f"/sessions/{session_id}")

    plan = None
    if session.get("plan_artifact_ids"):
        artifact = get(f"/sessions/{session_id}/artifacts/{session['plan_artifact_ids'][-1]}")
        if artifact["kind"] == "plan":
            plan = requests.get(artifact["url"]).text  # presigned, no auth header

    transcript = [m for m in messages(session_id, "message") if m["chat_thread_id"] is not None]
    return session, plan, transcript
```

### Full transcript with tool calls decoded

```python
def full_transcript(session_id):
    for m in messages(session_id, ["message", "tool_call"]):
        if m["type"] == "tool_call":
            call = json.loads(m["message"])
            name = call.pop("__name__", "?")
            yield m["chat_thread_id"], "tool", f"{name} {json.dumps(call)[:200]}"
        else:
            yield m["chat_thread_id"], m["role"], m["message"]
```

### Poll for new messages

```python
import time
from urllib.parse import parse_qs, urlparse


def poll(session_id, thread_id=None, interval=5, timeout=600):
    """Yield new final_message items as they arrive. Returns on timeout."""
    params = {"type": "final_message"}
    if thread_id:
        params["thread_id"] = thread_id
    deadline = time.time() + timeout
    while time.time() < deadline:
        body = get(f"/sessions/{session_id}/messages", **params)
        yield from body["items"]
        # new_messages.href carries only the gts cursor, so keep your own filters.
        href = body["_links"]["new_messages"]["href"]
        params["gts"] = parse_qs(urlparse(href).query)["gts"][0]
        time.sleep(interval)
```

## Verified quirks

Observed on live sessions produced by two different agents.

- Validation failures return 422, not 400: bad `limit`, `page`, `type`, `role`,
  `direction`, non-UUID ids, and comma-separated lists.
- Default sort is `ts` ascending when `direction` is omitted. `direction=desc` flips it.
- `_links.self.href` drops the query parameters you sent, and `_links.new_messages.href`
  keeps only `gts`. Rebuild pagination and polling URLs with your own filters.
- In every finished thread the last `message` equals the `final_message` exactly,
  so the default `type` filter returns the final text twice.
- Each thread has exactly one `role=user` item, of type `message`.
- Items with `chat_thread_id: null` are system notices (for example sandbox
  lifecycle warnings), not part of the conversation.
- An unknown `thread_id` filter returns 200 with empty `items`, not 404.
- `tool_call.message` holds only the invocation; tool results are not exposed.
- No rate-limit headers are returned. The limit is 100 requests per minute per key.
- Missing `Authorization` header returns 401; a wrong key, or a key for a
  different environment, returns 403.
