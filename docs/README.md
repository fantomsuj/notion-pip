# Documentation map

Notion PiP's documentation serves several different purposes. Use this map to
choose the right source and to understand how much authority it carries.

When documents disagree, the checked-out source and tests are authoritative.
The current documents below describe the intended product and operating
contracts. Course material, research, plans, and specifications provide
orientation or rationale, but they do not override the current implementation.

## Current authoritative documentation

- [Project README](../README.md) — current product behavior, requirements,
  build and launch instructions, privacy boundaries, and development signing.
- [Handoff protocol](HANDOFF_PROTOCOL.md) — the current cross-app URL contract
  and validation rules.
- [Manual test matrix](MANUAL_TEST_MATRIX.md) — current manual verification for
  windowing, Spaces, shortcuts, login items, and other macOS integrations.
- [External beta readiness](BETA_READINESS.md) — the current release gate and
  beta checklist.
- [Upstream reuse record](UPSTREAM_REUSE.md) — provenance, licensing context,
  reused behavior, and explicit reuse exclusions.

For implementation details, consult [`Sources/`](../Sources) and
[`Tests/`](../Tests) directly. Public behavior and release claims should be
verified there before changing them or relying on them operationally.

## Maintainer and course material

The [repository course](course/README.md) is a teaching and maintenance aid tied
to the **August 3, 2026 source snapshot**. It includes Quick Capture,
personal-token API access, and other architecture removed on August 10, 2026.
Some source links therefore no longer resolve, and the course must not be read
as a description of the current checkout.

Two course references remain especially useful for finding ownership and
planning changes, provided their names and flows are checked against current
source and tests:

- [Architecture map](course/ARCHITECTURE_MAP.md) — subsystem ownership and
  cross-layer runtime flows from the course snapshot.
- [Change guide](course/CHANGE_GUIDE.md) — owning-layer, diagnostic, testing,
  and verification guidance.

The [course index](course/README.md) links the full lecture series, file atlas,
glossary, condensed talk, and presenter guide. Treat all of them as snapshot
material with the same August 3 boundary.

## Research

- [Open-source reference research](OPEN_SOURCE_RESEARCH.md) — external projects
  studied for implementation and product patterns. References are not runtime
  dependencies; verify recommendations against current product decisions.
- [Product research report](PRODUCT_RESEARCH_REPORT.md) — product opportunities
  explored on July 30, 2026. Its Quick Capture direction was superseded on
  August 10, so it is retained as historical research rather than current
  product guidance.

## Historical plans and specifications

- [Modularity roadmap](MODULARITY_ROADMAP.md) — records earlier modularity work
  around capture and delivery subsystems that are no longer in the current
  architecture.
- [`superpowers/specs/`](superpowers/specs) — dated design proposals that record
  the reasoning and intended scope behind individual changes.
- [`superpowers/plans/`](superpowers/plans) — dated implementation plans that
  record how those changes were expected to be delivered.

Plans and specifications may describe work that changed during implementation,
was later removed, or was never adopted. Use them for design archaeology only,
and confirm every claim against the current source, tests, and authoritative
documentation above.
