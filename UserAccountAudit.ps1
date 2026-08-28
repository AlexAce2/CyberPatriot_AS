param(
    [string]$OutputDirectory = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Convert-To-CsvCell {
    param([AllowEmptyString()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    $text = $text.Replace("`r", ' ').Replace("`n", ' ')

    if ($text.Contains(',') -or $text.Contains('"')) {
        return '"' + $text.Replace('"', '""') + '"'
    }

    return $text
}

$timestamp = Get-Date -Format 'yyyyMMddTHHmmss'
$csvPath = Join-Path $OutputDirectory "user_audit_$timestamp.csv"
$jsonPath = Join-Path $OutputDirectory "user_audit_$timestamp.json"

if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$adminGroupMembers = @()
try {
    $adminGroupMembers = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Select-Object -ExpandProperty Name)
}
catch {
    $adminGroupMembers = @()
}

$results = foreach ($user in Get-CimInstance Win32_UserAccount -Filter "LocalAccount = True" | Sort-Object Name) {
    $userName = [string]$user.Name
    $fullName = [string]$user.FullName
    $isAdmin = $false
    if ($userName -eq 'Administrator' -or $adminGroupMembers -contains $userName) {
        $isAdmin = $true
    }

    $groups = @()
    if (Get-Command Get-LocalGroup -ErrorAction SilentlyContinue) {
        foreach ($group in Get-LocalGroup -ErrorAction SilentlyContinue) {
            try {
                $members = @(Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                if ($members -contains $userName) {
                    $groups += $group.Name
                }
            }
            catch {
                # ignore group lookup failures
            }
        }
    }

    $accountActive = if ($user.Disabled) { 'Disabled' } else { 'Active' }
    $passwordRequired = if ($user.PasswordRequired) { 'Yes' } else { 'No' }
    $passwordExpires = 'Not available'
    $passwordLastSet = 'Not available'
    $lastLogon = 'Not available'

    [pscustomobject]@{
        UserName = $userName
        FullName = $fullName
        IsAdmin = $isAdmin
        AccountActive = $accountActive
        PasswordRequired = $passwordRequired
        PasswordExpires = $passwordExpires
        PasswordLastSet = $passwordLastSet
        LastLogon = $lastLogon
        Comment = [string]$user.Description
        Groups = ($groups -join '; ')
        Flags = if ($user.Disabled) { 'AccountDisabled' } else { '' }
    }
}

$csvLines = @(
    'UserName,FullName,IsAdmin,AccountActive,PasswordRequired,PasswordExpires,PasswordLastSet,LastLogon,Comment,Groups,Flags'
)
foreach ($entry in $results) {
    $csvLines += @(
        (Convert-To-CsvCell $entry.UserName),
        (Convert-To-CsvCell $entry.FullName),
        (Convert-To-CsvCell $entry.IsAdmin),
        (Convert-To-CsvCell $entry.AccountActive),
        (Convert-To-CsvCell $entry.PasswordRequired),
        (Convert-To-CsvCell $entry.PasswordExpires),
        (Convert-To-CsvCell $entry.PasswordLastSet),
        (Convert-To-CsvCell $entry.LastLogon),
        (Convert-To-CsvCell $entry.Comment),
        (Convert-To-CsvCell $entry.Groups),
        (Convert-To-CsvCell $entry.Flags)
    ) -join ','
}

$csvLines | Set-Content -Path $csvPath -Encoding UTF8

$results | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "User audit complete."
Write-Host "CSV: $csvPath"
Write-Host "JSON: $jsonPath"

return $results
