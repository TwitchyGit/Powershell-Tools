# Argument completers

This section shows how argument completers turn known command metadata into friendly choices.

Run:

```powershell
./Invoke-ArgumentCompleterLesson.ps1
./Invoke-ArgumentCompleterLesson.ps1 -View RegistrationPlan
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- command and parameter matching
- input-prefix filtering
- completion text shape
- a registration plan without changing the session

The script does not call `Register-ArgumentCompleter`.
