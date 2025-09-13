# Issues

This file tracks various issues related to the dart_acp implementation.

## Known Issues (Reported)

*None at this time - no issues have been reported to GitHub yet.*

---

## Discovered Issues (Not Yet Reported)

## Gemini Model Compatibility

### Certain Gemini Models Break ACP
Some Gemini models have bugs in their experimental ACP implementation that cause `session/prompt` requests to fail.

**Status:** Partially improved in gemini-cli v0.6.0-nightly (as of Sep 13, 2025)

**Test Results (Sep 13, 2025):**
- Default model (when `GEMINI_MODEL` is not set) - Works for single prompt but **still fails** on multiple prompts to same session
- `gemini-2.0-flash-exp` - **Still broken** (returns empty output)
- `gemini-2.5-flash` - **Now works** for single prompts (was broken before)

**Symptoms:**
- JSON-RPC error -32603 (internal error)
- Error message: "Request contains an invalid argument" or "Internal error"
- Multiple prompts to the same session still fail with default model
- gemini-2.0-flash-exp returns empty output instead of failing with error

**Root Cause:**
- Bug in Gemini's experimental ACP implementation
- Different models have different limitations
- Not an issue with the dart_acp client library (confirmed by comparing with Zed's implementation)

**Workaround:**
- For single prompts per session: Use default model or gemini-2.5-flash
- For multiple prompts per session: **Still no known working Gemini model**
- Avoid gemini-2.0-flash-exp entirely (returns empty output)
- Test specific models before using them in production

**E2E Test Status (Updated after fixing tool call merging bug in dart_acp):**
- `create/manage sessions and cancellation` - **FAILS** (multiple prompts issue - Gemini agent limitation)
- `session replay via sessionUpdates` - **PASSES**
- `file read operations` - **PASSES** (fixed by tool call merging)
- `file write operations` - **PASSES** (fixed by tool call merging)
- `execute via terminal or execute tool` - **SKIPPED** (Gemini doesn't report execute tool calls - agent limitation)

**Note:** File read/write tests now pass after fixing dart_acp's tool call update merging bug. The execute test is still skipped as Gemini doesn't report terminal/execute tool calls in a way the test expects (agent limitation, not a dart_acp bug).

## Test Suite

### E2E Tests
Some E2E tests may fail or hang due to timing issues with real agents:

1. **Gemini tests** 
   - Will fail if `GEMINI_MODEL` is set to an incompatible model
   - Solution: Ensure test/test_settings.json doesn't override GEMINI_MODEL

2. **Claude-code "file read operations"**
   - May timeout or fail to read files in test environment
   - The agent works correctly in manual testing
   - May be related to how claude-code handles rapid test scenarios

### Workarounds
- Run tests with specific agents: `dart test --tags e2e -n "gemini"` 
- Use manual testing for verification: `dart example/main.dart -a gemini "prompt"`
- The echo agent tests should always pass: `dart test --tags e2e -n "echo"`

---

# Recently Fixed Issues

## Echo Agent Path Resolution in CLI Tests
- **Status**: ✅ Fixed
- **Fixed in**: test/cli_app_e2e_test.dart
- **Issue**: Echo agent tests were failing with exit code 254 because they couldn't find the echo agent when tests changed working directory to sandbox temp folders
- **Root Cause**: The echo agent path in test_settings.json is relative (`test/agents/echo_agent.dart`), but tests properly use temp directories as sandboxes for isolation
- **Solution**: Added `setUpAll`/`tearDownAll` to dynamically create a temporary settings file with absolute paths for the echo agent, preserving test isolation while fixing path resolution
- **Impact**: All 7 echo agent tests now pass with proper sandbox isolation

## Tool Call Update Merging Bug (MAJOR FIX)
- **Status**: ✅ RESOLVED
- **Fixed in**: 
  - lib/src/models/tool_types.dart - Added `merge()` method to ToolCall
  - lib/src/session/session_manager.dart - Added tool call tracking map and proper merge semantics

### Root Cause Analysis
The test failures were NOT due to agents failing to perform operations. The operations succeeded, but tests failed due to implementation bugs in how dart_acp handled tool call updates.

**Problem**: dart_acp incorrectly overwrote tool call fields when receiving updates with null values.

**Evidence from debug test**:
```
Tool call: toolu_01V7wFd2nTeYnXbvxoftm3md
  Kind: ToolKind.edit      # Initial: has kind
  Title: Write /private/...  # Initial: has title
  Status: ToolCallStatus.pending

Tool call: toolu_01V7wFd2nTeYnXbvxoftm3md  
  Kind: null               # Update: nullifies kind
  Title: null              # Update: nullifies title
  Status: ToolCallStatus.completed
```

**Incorrect behavior (before fix)**:
- `ToolCallUpdate` created a completely new `ToolCall` from JSON
- If update fields were null, they overwrote existing values
- Tests checked final state, which had been nullified

**Correct behavior per ACP spec** (as implemented in Zed):
- Tool call updates should MERGE fields, not replace them
- Only update fields that are explicitly provided (non-null)
- Preserve existing field values when update doesn't include them

### Implementation Fix
Following Zed's pattern from `acp_thread.rs`:

1. **Added `merge()` method to ToolCall** (`lib/src/models/tool_types.dart`):
```dart
ToolCall merge(Map<String, dynamic> update) => ToolCall(
  toolCallId: toolCallId, // ID never changes
  status: update['status'] != null
      ? ToolCallStatus.fromWire(update['status'] as String?)
      : status,
  title: update['title'] as String? ?? title,
  kind: update['kind'] != null
      ? ToolKind.fromWire(update['kind'] as String?)
      : kind,
  // ... only updates non-null fields
);
```

2. **Added tool call tracking to SessionManager** (`lib/src/session/session_manager.dart`):
```dart
final Map<String, Map<String, ToolCall>> _toolCalls = {};
```

3. **Implemented proper update handling**:
- `tool_call`: Creates and stores new tool call
- `tool_call_update`: Merges fields into existing tool call
- Preserves existing metadata when update fields are null

### Test Results After Fix
✅ **Claude-code tests**: All passing
- File write operations: PASS
- Terminal operations: PASS
- File read operations: PASS

✅ **Gemini tests**: Mostly passing
- File write operations: PASS (was failing, now fixed!)
- File read operations: PASS (was failing, now fixed!)
- Terminal operations: SKIPPED (agent limitation - doesn't report execute tool calls)
- Multiple prompts: FAILS (agent limitation with session handling)

**Impact**: Fixed failing tests for both Claude-code and Gemini file operations. The fix brings dart_acp into compliance with the ACP specification as implemented by Zed.

## CLI Test Path Handling
- **Status**: ✅ Fixed
- **Fixed in**: test/cli_app_e2e_test.dart
- **Issue**: Inconsistent use of relative vs absolute paths when spawning subprocesses in tests
- **Solution**: Standardized to use `path.join(Directory.current.path, 'example', 'main.dart')` for all Process.start calls

## Agent Crash Error Handling
- **Fixed in**: stdio_transport.dart lines 77-93
- **Issue**: When agent process crashes immediately (e.g., `false` command), client would get broken pipe error instead of meaningful error message
- **Solution**: Added early detection of process exit after spawn with 100ms delay, throwing clear StateError if process exits immediately
- **Status**: ✅ Fixed (pending commit)

## sessionUpdates Replay Missing TurnEnded
- **Fixed in**: session_manager.dart line 170
- **Issue**: `sessionUpdates()` method was not including TurnEnded markers in replay buffer, causing tests to hang waiting for a TurnEnded that would never come
- **Solution**: Added TurnEnded to the replay buffer when emitted so it can be properly replayed
- **Status**: ✅ Fixed (pending commit)

## Invalid Session ID Handling
- **Fixed in**: session_manager.dart
- **Issue**: Invalid session IDs were returning empty streams instead of throwing errors
- **Solution**: Now throws `ArgumentError` for unknown session IDs
- **Status**: ✅ Fixed (pending commit)