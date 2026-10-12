# claude-session-restore kurulumu. Tekrar tekrar çalıştırılabilir (idempotent): zaten kurulu olanı
# yeniden eklemez, eski sürümün profil bloğunu günceller. Değiştirdiği her dosyanın yanına .bak-<zaman> yedeği bırakır.
#
#   pwsh -File install.ps1                      # varsayılan: ~/.claude
#   pwsh -File install.ps1 -ConfigDir ~/.claude, ~/.claude-work   # birden fazla Claude config dizini
#   pwsh -File install.ps1 -SkipTerminal        # Windows Terminal ayarlarına dokunma
param(
    [string[]]$ConfigDir = @(Join-Path $HOME '.claude'),
    [switch]$SkipTerminal
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
function Backup($path) { Copy-Item -LiteralPath $path "$path.bak-$stamp"; }

# 1) Betikleri sabit yere kopyala (hook'lar ve profil buradan çağırır; repo taşınsa da bozulmaz)
New-Item -ItemType Directory -Force $InstallDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'src\*.ps1') $InstallDir -Force
Write-Host "✓ Betikler: $InstallDir" -ForegroundColor Green

# 2) Claude Code hook'ları
$registry = Join-Path $InstallDir 'cc-session-registry.ps1'
foreach ($dir in $ConfigDir) {
    $file = Join-Path $dir 'settings.json'
    $s = if (Test-Path $file) { Get-Content $file -Raw | ConvertFrom-Json -AsHashtable } else { [ordered]@{} }
    if (-not $s.hooks) { $s.hooks = [ordered]@{} }
    $changed = $false
    foreach ($ev in $HookEvents.Keys) {
        $entries = @($s.hooks[$ev] | Where-Object { $_ })
        if (-not ($entries | Where-Object { Test-OurHook $_ })) {
            $s.hooks[$ev] = $entries + (New-RegistryHook $registry $HookEvents[$ev])
            $changed = $true
        }
    }
    if ($changed) {
        if (Test-Path $file) { Backup $file } else { New-Item -ItemType Directory -Force $dir | Out-Null }
        $s | ConvertTo-Json -Depth 32 | Set-Content $file -Encoding utf8
        Write-Host "✓ Hook'lar eklendi: $file" -ForegroundColor Green
    } else {
        Write-Host "• Hook'lar zaten kurulu: $file" -ForegroundColor DarkGray
    }
}

# 3) PowerShell profili (eski sürümün bloğu varsa yerinde güncellenir)
$profilePath = $PROFILE.CurrentUserCurrentHost
$p = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
if ($p -match $ProfileBlockPattern) {
    $new = [regex]::Replace($p, $ProfileBlockPattern, { $ProfileBlock.TrimEnd() })
} else {
    $new = $p.TrimEnd() + "`r`n`r`n" + $ProfileBlock
}
if ($new -ne $p) {
    if (Test-Path $profilePath) { Backup $profilePath } else { New-Item -ItemType Directory -Force (Split-Path $profilePath) | Out-Null }
    Set-Content $profilePath $new -Encoding utf8 -NoNewline
    Write-Host "✓ Profil güncellendi: $profilePath" -ForegroundColor Green
} else {
    Write-Host "• Profil zaten güncel: $profilePath" -ForegroundColor DarkGray
}

# 4) Windows Terminal: düzeni sakla + oturum açılışında başla
if (-not $SkipTerminal) {
    $wtFiles = @(Get-TerminalSettingsFiles)
    if (-not $wtFiles) { Write-Host '! Windows Terminal ayar dosyası bulunamadı, atlandı' -ForegroundColor Yellow }
    foreach ($wt in $wtFiles) {
        $t = Get-Content $wt -Raw
        $n = $t
        foreach ($k in $TerminalSettings.Keys) { $n = Set-JsoncTopLevel $n $k $TerminalSettings[$k] }
        if ($n -ne $t) {
            Backup $wt
            Set-Content $wt $n -Encoding utf8 -NoNewline
            Write-Host "✓ Windows Terminal ayarlandı: $wt" -ForegroundColor Green
        } else {
            Write-Host "• Windows Terminal zaten ayarlı: $wt" -ForegroundColor DarkGray
        }
    }
}

Write-Host ''
Write-Host 'Bitti. Açık Claude sekmeleri bir sonraki mesajda kayda geçer; yeni sekmeler profil sayesinde hazır.' -ForegroundColor Cyan
