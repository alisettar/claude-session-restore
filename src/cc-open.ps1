# Bir Claude oturumunu bu shell'de, kendi klasöründe ve kendi launcher/config'iyle --resume eder.
# cc-recover.ps1 yeni WT sekmelerini bununla açar:  pwsh -NoExit -File cc-open.ps1 -SessionId <id> -Cwd <dir> ...
param(
    [Parameter(Mandatory)][string]$SessionId,
    [Parameter(Mandatory)][string]$Cwd,
    [string]$ConfigDir,
    [string]$Launcher = 'claude'
)
. (Join-Path $PSScriptRoot 'cc-common.ps1')
Clear-CcInheritedEnv   # ikinci savunma hattı: alt oturum işareti miras kalmışsa kayıt kapanmasın
$Cwd = Resolve-CcResumeCwd $SessionId $Cwd $ConfigDir
if (Test-Path $Cwd) { Set-Location $Cwd }
Write-Host "↻ Claude oturumu geri yükleniyor: $SessionId  ($Cwd)" -ForegroundColor Cyan
if ($ConfigDir) { $env:CLAUDE_CONFIG_DIR = $ConfigDir }
switch ($Launcher) {
    'gecko' { gecko --resume $SessionId }   # profildeki sarmalayıcı; kaydı yeniden yazar
    default { claude --resume $SessionId }
}
