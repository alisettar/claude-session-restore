# claude-session-restore kaldırma. install.ps1'in eklediklerini geri alır; yedek bırakır.
#   pwsh -File uninstall.ps1 [-ConfigDir ...] [-KeepTerminalLayout] [-KeepRegistry]
param(
    [string[]]$ConfigDir = @(Join-Path $HOME '.claude'),
    [switch]$KeepTerminalLayout,   # WT'nin düzen saklama/girişte başlama ayarları kalsın
    [switch]$KeepRegistry          # ~/.claude/session-registry kayıtları kalsın
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach ($dir in $ConfigDir) {
    $file = Join-Path $dir 'settings.json'
    if (-not (Test-Path $file)) { continue }
    $s = Get-Content $file -Raw | ConvertFrom-Json -AsHashtable
    if (-not $s.hooks) { continue }
    $before = $s | ConvertTo-Json -Depth 32
    foreach ($ev in @($s.hooks.Keys)) {
        $s.hooks[$ev] = @($s.hooks[$ev] | Where-Object { $_ -and -not (Test-OurHook $_) })
        if ($s.hooks[$ev].Count -eq 0) { $s.hooks.Remove($ev) }
    }
    $after = $s | ConvertTo-Json -Depth 32
    if ($after -ne $before) {
        Copy-Item $file "$file.bak-$stamp"
        Set-Content $file $after -Encoding utf8
        Write-Host "✓ Hook'lar kaldırıldı: $file" -ForegroundColor Green
    }
}

$profilePath = $PROFILE.CurrentUserCurrentHost
if ((Test-Path $profilePath) -and ((Get-Content $profilePath -Raw) -match $ProfileBlockPattern)) {
    Copy-Item $profilePath "$profilePath.bak-$stamp"
    $p = [regex]::Replace((Get-Content $profilePath -Raw), '(\r?\n)*' + $ProfileBlockPattern, "`r`n")
    Set-Content $profilePath $p -Encoding utf8 -NoNewline
    Write-Host "✓ Profil bloğu kaldırıldı: $profilePath" -ForegroundColor Green
}

if (-not $KeepTerminalLayout) {
    foreach ($wt in Get-TerminalSettingsFiles) {
        $t = Get-Content $wt -Raw; $n = $t
        foreach ($k in $TerminalSettings.Keys) { $n = Remove-JsoncTopLevel $n $k }
        if ($n -ne $t) {
            Copy-Item $wt "$wt.bak-$stamp"
            Set-Content $wt $n -Encoding utf8 -NoNewline
            Write-Host "✓ Windows Terminal ayarları kaldırıldı: $wt" -ForegroundColor Green
        }
    }
}

if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force; Write-Host "✓ Silindi: $InstallDir" -ForegroundColor Green }
if (-not $KeepRegistry -and (Test-Path $RegistryDir)) { Remove-Item $RegistryDir -Recurse -Force; Write-Host "✓ Silindi: $RegistryDir" -ForegroundColor Green }
