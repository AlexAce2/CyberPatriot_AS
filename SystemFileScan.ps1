param(
    [string]$Path = (Get-Location).Path
)

$resolvedPath = $null
try {
    $resolvedPath = (Resolve-Path -Path $Path -ErrorAction Stop).Path
}
catch {
    Write-Error "Path not found: $Path"
    exit 1
}

Write-Host "Scanning: $resolvedPath"

$files = Get-ChildItem -Path $resolvedPath -File -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $fullPath = $_.FullName.ToLowerInvariant()
        -not ($fullPath.Contains('\\windows\\') -or
              $fullPath.Contains('\\program files') -or
              $fullPath.Contains('\\program files (x86)\\') -or
              $fullPath.Contains('\\$recycle.bin\\') -or
              $fullPath.Contains('\\appdata\\local\\packages\\') -or
              $fullPath.Contains('\\system volume information\\'))
    } |
    Where-Object {
        $extension = $_.Extension.ToLowerInvariant()
        $suspicious = '.exe', '.dll', '.bat', '.cmd', '.ps1', '.vbs', '.js', '.jar', '.msi', '.lnk'
        $extension -in $suspicious -or $_.Length -gt 10MB
    } |
    Sort-Object Length -Descending |
    Select-Object -First 50

if (-not $files) {
    Write-Host "No suspicious files found."
    exit 0
}

Write-Host "Found suspicious files:"
$files | ForEach-Object {
    Write-Host ("{0,12} bytes  {1}" -f $_.Length, $_.FullName)
}

exit 0
