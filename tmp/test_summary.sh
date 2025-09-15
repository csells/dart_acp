#!/bin/bash

echo "Running compliance tests..."
PASS=0
FAIL=0
NA=0

for test in $(dart example/acpcomply/acpcomply.dart --list-tests 2>&1); do
  result=$(dart example/acpcomply/acpcomply.dart --agent claude-code --test "$test" 2>&1 | tail -5 | grep -o "PASS\|FAIL\|NA" | head -1)
  echo "$test: $result"
  case $result in
    PASS) ((PASS++));;
    FAIL) ((FAIL++));;
    NA) ((NA++));;
  esac
done

echo "---"
echo "Summary: PASS=$PASS, FAIL=$FAIL, NA=$NA"