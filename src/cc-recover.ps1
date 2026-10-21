# Çökme/elektrik kesintisi sonrası kurtarma. Windows Terminal düzeni yalnızca düzgün kapanışta kaydeder;
# çökmede sekmeler eski WT_SESSION'larla gelmez ve cc-restore.ps1 hiçbir oturumu bulamaz.
# Bu betik açılıştan sonra ilk shell tarafından (cc-restore.ps1) gizli olarak başlatılır:
#   - Bekler; anlık görüntüdeki oturumlardan herhangi biri canlanırsa WT düzeni geri gelmiş demektir → çık.
#   - Hiçbiri canlanmazsa (çökme) hepsini "claude-restore" adlı yeni bir WT penceresinde sekme olarak açar.
# Elle: pwsh -File cc-recover.ps1 -Snapshot <json> -NoWait
param(
    [Parameter(Mandatory)][string]$Snapshot,
    [int]$WaitSeconds = 90,
    [switch]$NoWait
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'cc-common.ps1')
function Log($m) { Add-Content $CcRecoverLog ("{0:o} {1}" -f (Get-Date), $m) -Encoding utf8 }

$sessions = @(Get-Content $Snapshot -Raw | ConvertFrom-Json)
Log "kurtarma başladı: $($sessions.Count) oturum, snapshot=$Snapshot"
if (-not $sessions) { Remove-Item $Snapshot -Force; return }

function Get-AliveSessionIds { @(Get-CcEntries | Where-Object { Test-CcEntryAlive $_ } | ForEach-Object sessionId) }

if (-not $NoWait) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $alive = Get-AliveSessionIds
        if ($sessions | Where-Object { $_.sessionId -in $alive }) {
            Log 'WT düzeni geri gelmiş (oturumlar canlanıyor) → kurtarmaya gerek yok'
            Remove-Item $Snapshot -Force
            return
        }
    }
}

$alive  = Get-AliveSessionIds
Clear-CcInheritedEnv   # wt.exe yeni sekmelere bu sürecin ortamını aktarır
$opener = Join-Path $PSScriptRoot 'cc-open.ps1'
$seen   = @{}
foreach ($s in $sessions) {
    if ($seen[$s.sessionId] -or $s.sessionId -in $alive) { continue }
    $seen[$s.sessionId] = $true
    $cwd = if ($s.cwd -and (Test-Path $s.cwd)) { $s.cwd } else { $HOME }
    $title = Split-Path $cwd -Leaf
    $cmd = @('-NoExit', '-File', $opener, '-SessionId', $s.sessionId, '-Cwd', $cwd, '-Launcher', ($s.launcher ?? 'claude'))
    if ($s.configDir) { $cmd += @('-ConfigDir', $s.configDir) }
    # "-w claude-restore": ilk çağrı bu adla yeni pencere açar, sonrakiler aynı pencereye sekme ekler
    & wt.exe -w claude-restore new-tab --title $title -d $cwd pwsh @cmd
    Log "açıldı: $($s.sessionId) [$($s.launcher)] $cwd"
    Start-Sleep -Milliseconds 700   # sekmeler sırayla eklensin

    # Eski sekmenin kaydı artık geçersiz (o WT_SESSION bir daha gelmeyecek); yeni sekme kendi kaydını yazacak
    if ($s.wtSession) { Remove-Item (Join-Path $CcRegistryDir "$($s.wtSession).json") -Force -ErrorAction SilentlyContinue }
}
Remove-Item $Snapshot -Force
Log 'kurtarma bitti'
