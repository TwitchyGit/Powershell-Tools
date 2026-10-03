# Learner guide

Use this course as a hands-on workbook. Run the examples, inspect the output, then make small controlled edits.

## How to work through a script

1. Read the comment-based help at the top of the file.
2. Run the script with no arguments.
3. Inspect the object properties returned by the script.
4. Re-run the script with `Format-List *` only after capturing the raw object shape.
5. Change one input value or fixture field.
6. Predict which output field should change.
7. Run the script again and compare the result.

## Exercise pattern

Each exercise should follow this pattern:

- Run: execute the script in a fresh shell.
- Inspect: identify the object type, key properties and exit code.
- Modify: adjust a safe local value or fixture record.
- Break: introduce one controlled invalid value.
- Fix: restore valid input and explain the validation result.
- Extend: add one useful field to the output object.

## Evidence to capture

For each unit, keep these notes:

- Script name.
- Input source.
- Output object properties.
- Expected success condition.
- Expected failure condition.
- Exit code behavior.
- Live-system checks that are not covered by local samples.

## Local safety

The scripts use local sample data. AD-shaped records are not live AD results. CyberArk-shaped records are not live PVWA results. AutoSys runfiles are sample output. Deployment examples do not call `git`, `ssh` or a network service.
