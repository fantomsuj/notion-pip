# Perch handoff protocol

The only cross-app page handoff in v1 is:

```text
perch://pin?url=<percent-encoded-notion-page-url>&source=chrome-extension
```

## Contract

- Scheme: `perch`
- Action/host: `pin`
- Required query fields: exactly one `url` and one `source`
- Supported source in this slice: `chrome-extension`
- Maximum outer URL length: 4,096 UTF-8 bytes

The nested `url` must use HTTPS, have no username or password, use the exact host `app.notion.com`, `notion.com`, or `www.notion.com`, and end in a component containing a 32-hex-character Notion page ID. Legacy `notion.so` and `www.notion.so` links are also accepted. Hyphens in a UUID are ignored for identity. All accepted non-app hosts canonicalize to `www.notion.com`; every accepted host retains its percent-encoded path. Canonical URLs have no query or fragment.

Example:

```text
perch://pin?url=https%3A%2F%2Fwww.notion.com%2FProject-Roadmap-0123456789abcdef0123456789abcdef&source=chrome-extension
```

## Trust boundary

`source` is untrusted UX metadata. It never grants capabilities or changes URL validation. Unknown actions and sources are rejected. The implementation must not log the outer URL, its full query, credentials, or tokens; telemetry may record only a sanitized acceptance/rejection event and the allowlisted source.

Application URL delivery and panel replacement consume this parser contract.
