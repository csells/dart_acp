# Known Issues

## Gemini Agent Issues

### Rate Limit Errors
- **Status**: Active
- **Affected Versions**: Gemini CLI 0.4.1+
- **Issue**: Gemini returns rate limit errors (HTTP 429) after ~60 seconds delay
- **Impact**:
  - Tests: `gemini responds to prompt (AcpClient)` test fails with rate limit error
  - Error: `JSON-RPC error 429: Rate limit exceeded. Try again later.`
- **Workaround**: Test catches rate limit errors and marks test as skipped
- **Root Cause**: Gemini's API rate limiting, response delayed by ~60 seconds
- **Fix Applied**: SessionManager now properly sends TurnEnded after errors to close the stream

### File Write Operations Timeout
- **Status**: Active
- **Issue**: Gemini times out during file write operations
- **Impact**: `file write operations` test for Gemini is skipped
- **Workaround**: Test skipped with conditional check

### Multiple Prompts to Same Session
- **Status**: Active
- **Issue**: Gemini fails when sending multiple prompts to the same session
- **Impact**: Multiple prompt tests are skipped for Gemini
- **Notes**: Works with some models but not the default model

## Claude Code Agent Issues

None currently active.

## Test Infrastructure

### File Operations Tests
- **Fixed**: Tests were failing due to incorrect workspace root after API refactoring
- **Solution**: Updated tests to pass temp directory path to both `newSession()` and removed `workspaceRoot` from `prompt()` calls