# Testing Specification

This document describes the testing strategy, structure, and conventions for this repository. It exists to keep tests reliable, fail‑loud, and easy to evolve as the codebase grows.

## Overview

We test two primary surfaces:

- AcpClient library (transport, session lifecycle, routing, security providers)
- Example CLI app (example/main.dart)

For each surface we keep both unit and end‑to‑end (E2E) coverage:

- Unit: fast tests, fine‑grained, use mocks/test doubles, no external processes
- E2E: real adapters over ACP (subprocess), realistic behavior, capability‑gated

We also keep a small set of spec sanity tests and low‑level unit tests for shared utilities.

## Test Structure

- AcpClient
  - E2E: `test/acp_client_e2e_test.dart`
  - Unit: `test/acp_client_unit_test.dart`
- CLI app
  - E2E: `test/cli_app_e2e_test.dart`
  - Unit: `test/cli_app_unit_test.dart`
- Spec sanity and shared utilities
  - Spec coverage: `test/acp_spec_coverage_test.dart`
  - Transport: `test/stdin_transport_test.dart`
  - FS jail: `test/unit_fs_jail_test.dart`
- Helpers and fixtures
  - Capability gating: `test/helpers/adapter_caps.dart`
  - Echo agent for tests: `test/agents/echo_agent.dart`
  - Real adapter config: `test/test_settings.json`

## E2E Tests

E2E tests run against real ACP adapters/configurations defined in `test/test_settings.json`. They must not use mocks or stubs for ACP interactions.

- Settings source: both AcpClient and CLI E2E tests consistently use `test/test_settings.json`.
- Adapter capability gating: Use `test/helpers/adapter_caps.dart` to list initialize results via the CLI and skip tests only for features that are actually negotiated at initialize (e.g., `session/load`).
  - Use `skipIfMissingAll(agent, [patterns], name)` for initialize‑time features only.
  - Do not gate runtime behaviors (plans, diffs, available commands, terminal content) on initialize capabilities; assert based on observed `session/update` instead.
- Failure policy: E2E tests fail loudly. Do not mask JSON parsing issues or network/process errors. If an output line cannot be parsed as JSON when the test expects JSON, the test should fail.
- Cleanup: When using temporary directories, check existence before deleting in `addTearDown` (avoid try/catch in assertions path).

### AcpClient (E2E)
- File: `test/acp_client_e2e_test.dart`
- Uses `Settings.loadFromFile('test/test_settings.json')`
- Exercises:
  - Session creation, prompt streaming, cancellation
  - Session replay (if adapter supports loadSession)
  - File read/write tool calls
  - Plans and diffs (observed via updates; not gated by initialize caps)
  - Terminal / execute (enabled when a TerminalProvider is configured; not gated by initialize caps)

### CLI app (E2E)
- File: `test/cli_app_e2e_test.dart`
- Spawns the CLI via `Process.start('dart', ['example/main.dart', '--settings', <test_settings.json>, ...])`
- Exercises:
  - `--list-caps` (jsonl/json)
  - `--list-commands` (jsonl/text)
  - Text output path with a simple prompt
  - Strict JSONL parsing (no try/catch) for JSON modes

## Unit Tests

Unit tests run quickly, cover logic in isolation, and may use mocks.

### AcpClient (Unit)
- File: `test/acp_client_unit_test.dart`
- Includes:
  - Basic `AcpClient` smoke tests (transport lifecycle, helpers)
  - `SessionManager` routing tests across all `session/update` kinds
  - Capability JSON shape tests
  - StopReason mapping tests
  - A mock‑agent integration over `StdinTransport` (in unit scope)

### CLI app (Unit)
- File: `test/cli_app_unit_test.dart`
- Includes:
  - Argument parsing (`example/args.dart`) for flags, output modes, prompt capture
  - `example/settings.dart` parsing for valid/invalid files (temp files)

### Spec Sanity
- File: `test/acp_spec_coverage_test.dart`
- Verifies the library models and enums are consistent with the ACP spec (stop reasons, update kinds, capability scaffolding).

### Transport Unit
- File: `test/stdin_transport_test.dart`
- Ensures the low‑level transport channel read/write behavior and protocol taps work independently of higher layers.

### FS Jail Unit
- File: `test/unit_fs_jail_test.dart`
- Validates workspace jail behavior and path handling separate from AcpClient/CLI flows.

## Helpers & Fixtures

- `test/helpers/adapter_caps.dart`
  - Runs the CLI with `--list-caps` to fetch adapter capabilities.
  - Caches results in memory to avoid repeated process launches within one test run.
  - Provides `skipIfMissingAll` and `skipUnlessAny` helpers.

- `test/agents/echo_agent.dart`
  - A small echo agent for deterministic behavior in E2E.

- `test/test_settings.json`
  - Canonical configuration for E2E runs.
  - Expected to define adapter entries for names referenced by tests (e.g., `gemini`, `claude-code`, `echo`).

## Conventions & Guidelines

- Naming: keep `_unit_test.dart` and `_e2e_test.dart` suffixes for clarity.
- Mocks:
  - E2E tests: no mocks.
  - Unit tests: mocks allowed, including mock agents and in‑memory sinks.
- Fail‑loud:
  - Do not wrap subject‑under‑test calls in try/catch to suppress failures.
  - Use `expect(() => call(), throwsA(...))` for negative paths.
  - For JSONL parsing tests, `jsonDecode` should throw on invalid input; do not skip malformed lines.
- Cleanup:
  - Use `addTearDown` to remove temp resources and check `exists()` before deletion.
- Capability gating:
  - Only gate tests for features negotiated at initialize (e.g., `session/load`).
  - Do not gate runtime features (plans, diffs, available commands, terminal content) on initialize data; assert on observed behavior.
  - Keep capability pattern strings simple and lower‑case (helper matches keys recursively) when you do gate by initialize.
- Timeouts:
  - E2E tests have explicit `Timeout` annotations tuned per adapter.
  - Keep unit tests fast; avoid arbitrary sleeps.

## Running Tests

- All tests:
  - `dart test`
- E2E only:
  - Marked with `tags: 'e2e'`
  - `dart test -t e2e`
- Excluding E2E:
  - `dart test -x e2e`

Ensure adapters referenced in `test/test_settings.json` are installed and accessible on PATH before running E2E.

## Notes on the Example CLI

- Argument parsing lives in `example/args.dart`; `example/main.dart` consumes `CliArgs` and fails loud (no special exception handling) to surface errors directly.
- Troubleshooting guidance for common errors (auth required, invalid settings, empty prompt) is documented in `README.md`.
