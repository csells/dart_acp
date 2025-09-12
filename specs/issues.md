# Issues

This file tracks various issues related to the dart_acp implementation.

## Known Issues (Reported)

*None at this time - no issues have been reported to GitHub yet.*

---

## Discovered Issues (Not Yet Reported)

## Gemini Model Compatibility

### Certain Gemini Models Break ACP
Some Gemini models have bugs in their experimental ACP implementation that cause `session/prompt` requests to fail.

**Status:** Needs to be reported to Gemini team

**Affected Models:**
- `gemini-2.0-flash-exp` - Fails on first prompt
- `gemini-2.5-flash` - Fails on first prompt
- Default model (when `GEMINI_MODEL` is not set) - Works for single prompt but fails on multiple prompts to same session

**Symptoms:**
- JSON-RPC error -32603 (internal error)
- Error message: "Request contains an invalid argument" or "Internal error"
- Some models fail on the first prompt
- Default model fails only when sending multiple prompts to the same session

**Root Cause:**
- Bug in Gemini's experimental ACP implementation
- Different models have different limitations
- Not an issue with the dart_acp client library (confirmed by comparing with Zed's implementation)

**Workaround:**
- For single prompts per session: Use default model (don't set `GEMINI_MODEL`)
- For multiple prompts per session: Currently no known working Gemini model
- Remove any `"env": {"GEMINI_MODEL": "..."}` from settings.json
- Test specific models before using them in production

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