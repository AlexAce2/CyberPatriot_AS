param()
$proj = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Host "Building..."
dotnet build "$proj\UserAccountAudit.csproj" -c Release
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed"; exit 1 }
Write-Host "Running audit..."
# Run the built exe if available, otherwise use dotnet run
$exe = Join-Path $proj "bin\Release\net9.0\UserAccountAudit.exe"
if (Test-Path $exe) { & $exe } else { dotnet run --project "$proj\UserAccountAudit.csproj" -c Release }
