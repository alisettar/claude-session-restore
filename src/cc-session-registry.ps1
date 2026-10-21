# Claude Code hook: hangi WT sekmesinde (WT_SESSION) hangi Claude oturumunun açık olduğunu kaydeder.
# Kullanım (settings.json hooks): cc-session-registry.ps1 start|prompt|end   (hook JSON'u stdin'den gelir)
param([string]$Event = 'start')
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'cc-common.ps1')

if (-not $env:WT_SESSION) { exit 0 }   # Windows Terminal dışında çalışan oturumlar takip edilmez
$in = [Console]::In.ReadToEnd() | ConvertFrom-Json
if (-not $in.session_id) { exit 0 }

$file = Join-Path $CcRegistryDir "$($env:WT_SESSION).json"
$cur  = if (Test-Path $file) { Get-Content $file -Raw | ConvertFrom-Json }

if ($Event -eq 'end') {
    # Yalnızca kullanıcının bilinçli çıkışında sil; restart/kill durumunda kayıt kalır = geri yüklenecek
    if ($in.reason -in 'prompt_input_exit', 'logout' -and $cur.sessionId -eq $in.session_id) {
        Remove-Item $file -Force
        Update-CcLiveSnapshot
    }
    exit 0
}

# Her prompt'ta çağrılır; kayıt zaten güncelse yalnızca anlık görüntüyü tazele
if ($Event -eq 'prompt' -and $cur.sessionId -eq $in.session_id -and $cur.launcher -and $cur.claudePid) {
    Update-CcLiveSnapshot
    exit 0
}

# Ata süreçler arasında claude.exe'yi bul (canlılık kontrolü için PID + başlangıç zamanı)
$p = Get-Process -Id $PID
$claude = $null
for ($i = 0; $i -lt 6 -and $p; $i++) {
    $p = $p.Parent
    # Otomatik güncelleme çalışan binary'yi claude.exe.old.<ts>.<pid> olarak yeniden adlandırır → süreç adı da değişir
    if ($p.Name -match '^claude(\.exe\.old\.[\d.]+)?$') { $claude = $p; break }
}

# Hangi launcher ile açıldı? gecko.ps1 yerel vLLM'e yönlendirmek için ANTHROPIC_BASE_URL set eder
# (gecko normalde cc-gecko-wrap.ps1 ile kaydedilir; bu yalnızca güvenlik ağı). myclaude = configDir.
$launcher = if ($env:ANTHROPIC_BASE_URL) { 'gecko' } else { 'claude' }
$same = $cur.sessionId -eq $in.session_id
$now  = (Get-Date).ToUniversalTime().ToString('o')

New-Item -ItemType Directory -Force $CcRegistryDir | Out-Null
$entry = [ordered]@{
    wtSession      = $env:WT_SESSION
    launcher       = $launcher
    sessionId      = $in.session_id
    # Oturumun ilk klasörü saklanır (--resume konuşmayı o proje klasöründe arar); sonradan cd yapılsa da değişmez
    cwd            = if ($same -and $cur.cwd) { $cur.cwd } else { $in.cwd }
    transcriptPath = $in.transcript_path
    configDir      = $env:CLAUDE_CONFIG_DIR
    claudePid      = $claude.Id
    claudeStart    = if ($claude) { $claude.StartTime.ToUniversalTime().ToString('o') }
    created        = if ($same -and $cur.created) { $cur.created } else { $now }   # sekme sırası tahmini için
    updated        = $now
}
$tmp = "$file.tmp"
$entry | ConvertTo-Json | Set-Content -Path $tmp -Encoding utf8
Move-Item -Force $tmp $file
Update-CcLiveSnapshot
exit 0
