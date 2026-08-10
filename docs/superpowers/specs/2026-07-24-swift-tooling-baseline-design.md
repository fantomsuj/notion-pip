# Curated Swift Tooling Baseline

**Date:** 2026-07-24

## Goal

Adopt compiler, formatting, lint, and dead-code checks that provide useful
feedback immediately without forcing a broad rewrite of existing Swift source,
embedded JavaScript, or test fixtures.

## Current State

- The package uses Swift tools 6.2 and compiles in Swift 6 language mode.
- A build with `-warnings-as-errors` succeeds.
- SwiftLint 0.63.2 and SwiftFormat 0.59.1 are installed on the current
  development machine, but the repository does not configure or invoke them.
- Default SwiftLint rules report 185 findings after generated files are
  excluded. Most are formatting, test-size, and threshold findings.
- Default SwiftFormat rules would change 52 of 90 files. The largest categories
  include `hoistTry`, indentation, number formatting, and import sorting.
- Periphery is not installed.
- The repository has no CI workflow or committed development-tool manifest.

## Rollout Strategy

Use a curated, immediately clean baseline. The blocking check will enforce a
small set of high-signal rules across the repository. Broader rules can be added
later only when the codebase passes them without a stored violation baseline.

The tooling change may make a small mechanical cleanup for the formatter rules
selected in this design. It must not reformat embedded JavaScript or introduce
unrelated source refactors.

## Components

### Compiler and Tests

`script/check_swift.sh` will run the full Swift test suite with compiler warnings
promoted to errors:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -Xswiftc -warnings-as-errors
```

This is the authoritative type and concurrency check. The package already uses
Swift 6 mode, so no separate type checker or concurrency mode flag is needed.

### SwiftFormat

Add `.swiftformat` with an explicit Swift version, repository exclusions, and a
small allowlist of safe mechanical rules. Initial rules will cover whitespace,
blank-line hygiene, and unambiguous spacing. Rules that broadly restructure
expressions, indentation, numeric literals, imports, or `try` placement will
remain disabled.

`script/lint_swift.sh` will run SwiftFormat in lint mode against `Sources`,
`Tests`, and `Package.swift`. Developers may run SwiftFormat without `--lint`
to apply the same configuration.

### SwiftLint

Add `.swiftlint.yml` with:

- explicit `Sources`, `Tests`, and `Package.swift` scope;
- `.build`, `.swiftpm`, `dist`, generated resources, and vendored assets
  excluded;
- an allowlist of correctness-oriented rules;
- no file-length, type-length, function-length, line-length, or subjective
  complexity gates;
- strict exit behavior so a configured warning fails the lint command.

The initial allowlist will prefer rules for unsafe force operations, duplicate
imports, suspicious control flow, unused bindings or parameters, and other
unambiguous defects. A selected rule that finds reasonable existing code must
either receive a narrowly documented exception or be deferred; the design will
not store a blanket SwiftLint baseline.

### Periphery

Add `script/analyze_swift.sh` for dead-code analysis. It will:

- verify that Periphery is installed and print a direct setup instruction when
  it is missing;
- analyze the Swift package using the selected full Xcode toolchain;
- remain separate from `script/check_swift.sh`;
- report findings through its normal nonzero exit status.

Periphery is advisory during this rollout because AppKit delegates, selectors,
and runtime entry points may require explicit retention annotations or
configuration. A future change may promote it to the blocking check after its
findings are reviewed.

### Tool Installation

Add a `Brewfile` documenting SwiftFormat, SwiftLint, and Periphery as optional
development dependencies. Do not run `brew bundle` from Conductor setup and do
not make these tools prerequisites for building or launching Perch.

Each wrapper script will detect missing tools and print the command needed to
install the development bundle. Every wrapper that invokes Swift tooling will
set:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

This avoids SourceKit lookup failures under non-interactive shells.

### Conductor

Extend `.conductor/settings.toml` with shared run entries for:

- the blocking Swift check; and
- advisory dead-code analysis.

The existing app run command remains the default, and `run_mode` remains
`nonconcurrent` because launching a build can conflict with another running app
instance. Shared Conductor settings take effect for new workspaces after this
change is merged into the remote default branch.

### Documentation

Update `README.md` with:

- the blocking check command;
- the fast lint command;
- the formatter command;
- the advisory Periphery command; and
- the optional `brew bundle` setup command.

The existing clone-to-run workflow remains unchanged.

## Error Handling

Wrapper scripts will use `set -euo pipefail`, resolve the repository root from
their own path, and fail with concise diagnostics when full Xcode or a required
blocking tool is missing. The advisory analysis script will distinguish a
missing Periphery installation from actual dead-code findings.

## Validation

Configuration and wrapper scripts are treated as the approved TDD exception for
configuration work. They will be validated with command-level red and green
probes:

1. Confirm the lint wrapper rejects an intentionally nonconforming temporary
   Swift fixture without modifying repository source.
2. Confirm the lint wrapper passes on the repository.
3. Confirm the blocking check passes with warnings promoted to errors.
4. Confirm the formatter is idempotent by running lint after its one-time
   mechanical cleanup.
5. Confirm the advisory script gives the expected installation diagnostic when
   Periphery is unavailable, or completes a scan when it is installed.
6. Confirm the full existing Swift test suite passes.
7. Inspect `git diff --check` and the final diff to ensure no unrelated source,
   signing, entitlement, or generated-resource changes were introduced.

## Non-Goals

- Adding or changing a hosted CI provider.
- Enforcing every SwiftLint or SwiftFormat default rule.
- Refactoring production or test code to satisfy size metrics.
- Making development linters prerequisites for running the app.
- Changing Swift, macOS deployment, signing, entitlement, or public API
  contracts.
