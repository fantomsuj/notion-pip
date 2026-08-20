# Product research update: contextual Notion connection

The historical [product research report](PRODUCT_RESEARCH_REPORT.md) rejected
ambient app-aware switching because it could surprise users, collect more
context than necessary, and weaken Perch's one-calm-surface thesis. The
reveal-time exact connection keeps that constraint.

The user supplies intent by revealing Perch. Perch performs one narrow URL
check at that boundary, never replaces an occupied page, and requires a second
explicit **Open Here** action to switch. An empty Perch may open the exact page
because there is no existing context to displace. Timeouts, permission loss,
invalid sources, and stale results return to established behavior.

This interaction advances the primary job—keep the relevant page in reach—by
removing workspace navigation without turning Perch into an ambient observer.
The success questions for field testing are:

1. Does reveal-to-relevant-page time decrease?
2. Do users understand why an occupied PiP is never replaced automatically?
3. Is **Open Here** discoverable without becoming distracting?
4. Which documented browsers expose focused URL attributes reliably?
5. Do permission and privacy explanations match user expectations?

No detected URL, title, or identifier telemetry is proposed. Compatibility and
value should be evaluated through consented manual studies and support reports.
