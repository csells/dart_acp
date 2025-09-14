#!/bin/bash

for test in $(dart example/acpcomply/acpcomply.dart --agent claude-code --list-tests 2>&1 | grep "^required\\."); do
  echo -n "$test: "
  result=$(dart example/acpcomply/acpcomply.dart --agent claude-code --test "$test" 2>&1 | tail -5 | grep -o "PASS\|FAIL" | head -1)
  echo "$result"
done