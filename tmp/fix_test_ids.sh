#!/bin/bash

# Find all optional test files with response IDs and fix them
for file in /Users/csells/Code/dart_acp/example/acpcomply/compliance-tests/optional.*.jsont; do
  # Check if file contains response with id field
  if grep -q '"response".*{.*"id".*:.*[0-9]' "$file"; then
    echo "Fixing $(basename $file)"
    # Remove "id": number, from response blocks
    perl -i -pe 's/("response"\s*:\s*\{)\s*"id"\s*:\s*\d+\s*,\s*/$1\n              /g' "$file"
  fi
done

echo "Done fixing IDs"