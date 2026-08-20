# Contextual Notion Connection release checklist

Run this feature checklist alongside [External Beta Readiness](BETA_READINESS.md)
against the exact signed release candidate.

- [ ] Context Suggestions is off by default and does not prompt before the
  setting is enabled.
- [ ] Granting, denying, and revoking Accessibility access produces the
  documented Settings state and leaves ordinary reveal behavior available.
- [ ] Valid HTTPS pages work in each documented browser; `notion.id` deep links
  normalize only from the native Notion app.
- [ ] Lookalike hosts, unsupported schemes/sources, malformed URLs, and routes
  without a 32-character page ID are silent no-context results.
- [ ] An empty Perch auto-opens an exact page through the normal activation,
  persistence, and recents path.
- [ ] An occupied Perch never changes page automatically; different pages show
  a slim dismissible **Open Here** action and the same page shows nothing.
- [ ] Global shortcut, menu-bar Show, status-item peek, handle restore, edge
  pull, and Restore Current shelf paths capture the source before Perch focus.
- [ ] A newer reveal, explicit pinned/recent selection, permission revocation,
  source termination, and timeout all invalidate older results.
- [ ] VoiceOver identifies the Open Here and dismiss controls; Reduce Motion and
  multiple Spaces/displays preserve normal reveal behavior.
- [ ] Unified logs contain no detected URL, title, or page identifier.

Record build, owner, date, browser/Notion versions, and evidence in
[the manual matrix](MANUAL_TEST_MATRIX.md).
