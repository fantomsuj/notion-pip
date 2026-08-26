---
name: stream-to-perch
description: >-
  Streams Markdown agent output into Perch's local accept-to-paste API so the
  user can review, place the Notion cursor, and Accept. Use when the user asks
  to send a response to Perch, Notion via Perch, or to stream notes into their
  floating Notion panel.
---

# Stream Markdown to Perch

## When to use

Use this skill when the user wants your finished Markdown answer pasted into
Notion through Perch. Perch never auto-inserts. The user clicks a location in
the Notion page and presses **Accept**.

## Prerequisites

1. Perch is running on this Mac.
2. Settings → Local Agents → **Allow local agents** is enabled.
3. Discovery file exists at:
   `~/Library/Application Support/com.fantomsuj.Perch/agent-server.json`

## Protocol (accept_to_paste)

1. Read the discovery JSON (`schemaVersion`, `baseURL`, `token`). Never print
   the token to chat, logs, or commits.
2. `GET {baseURL}/status` with `Authorization: Bearer <token>`.
3. `POST {baseURL}/streams` with headers:
   - `Authorization: Bearer <token>`
   - `Content-Type: application/json`
   - `Idempotency-Key: <unique key>`
   Body:
   ```json
   {
     "client": "cursor",
     "label": "Cursor",
     "commitMode": "accept_to_paste",
     "contentType": "text/markdown"
   }
   ```
4. Stream UTF-8 Markdown chunks with increasing `sequence` starting at `0`:
   `POST {baseURL}/streams/{id}/chunks` body `{"sequence":n,"text":"..."}`.
   Cap each chunk at 32 KiB. Retry the exact previous sequence if a response
   is lost.
5. `POST {baseURL}/streams/{id}/complete` when finished. This only marks the
   stream **ready** in Perch. Do **not** expect Notion to change yet.
6. Tell the user: click in Notion where the note should go, then press
   **Accept** in Perch (or the notification action).

## Rules

- One active stream at a time. `409 stream_active` means wait or cancel.
- `410 stream_gone` means stop forwarding.
- Prefer Markdown (headings, lists, fenced code). Perch renders it live and
  pastes so Notion can convert structure.
- Never call remote Notion APIs or ask for integration tokens.
- If discovery is missing, ask the user to enable Local Agents in Perch.

## Optional helper

Repository script `script/perch_agent_client.swift` can `pipe` stdin as chunks.
