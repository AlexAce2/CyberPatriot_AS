UserAccountAudit - Windows local account audit (C#/.NET 9)

Build:
  dotnet build "UserAccountAudit.csproj"

Run:
  - From bash: chmod +x ./run-audit.sh && ./run-audit.sh
  - Or from PowerShell: .\run-audit.ps1
  - Or: dotnet run --project "UserAccountAudit.csproj" -c Release

Outputs:
  user_audit.json  (full structured output)
  user_audit.csv   (CSV summary)

Notes:
  - Uses built-in "net user" and "net localgroup" commands to avoid external deps.
  - No admin required for read-only auditing; some remediation actions require elevation.
