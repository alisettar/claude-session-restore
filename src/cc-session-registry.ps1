# Claude Code hook: hangi WT sekmesinde (WT_SESSION) hangi Claude oturumunun açık olduğunu kaydeder.
# Kullanım (settings.json hooks): cc-session-registry.ps1 start|prompt|end   (hook JSON'u stdin'den gelir)
param([string]$Event = 'start')
$ErrorActionPreference = 'SilentlyContinue'

if (-not $env:WT_SESSION) { exit 0 }   # Windows Terminal dışında çalışan oturumlar takip edilmez
$in = [Console]::In.ReadToEnd() | ConvertFrom-Json
if (-not $in.session_id) { exit 0 }

$dir  = Join-Path $HOME '.claude\session-registry'
$file = Join-Path $dir "$($env:WT_SESSION).json"
$cur  = if (Test-Path $file) { Get-Content $file -Raw | ConvertFrom-Json }

if ($Event -eq 'end') {
    # Yalnızca kullanıcının bilinçli çıkışında sil; restart/kill durumunda kayıt kalır = geri yüklenecek
    if ($in.reason -in 'prompt_input_exit', 'logout' -and $cur.sessionId -eq $in.session_id) {
        Remove-Item $file -Force
    }
    exit 0
}

# Her prompt'ta çağrılır; kayıt zaten güncelse hızlı çık
if ($Event -eq 'prompt' -and $cur.sessionId -eq $in.session_id -and $cur.launcher) { exit 0 }

# Ata süreçler arasında claude.exe'yi bul (canlılık kontrolü için PID + başlangıç zamanı)
$p = Get-Process -Id $PID
$claude = $null
for ($i = 0; $i -lt 6 -and $p; $i++) {
    $p = $p.Parent
    if ($p.Name -eq 'claude') { $claude = $p; break }
}

# Hangi launcher ile açıldı? gecko.ps1 yerel vLLM'e yönlendirmek için ANTHROPIC_BASE_URL set eder
# (gecko normalde cc-gecko-wrap.ps1 ile kaydedilir; bu yalnızca güvenlik ağı). myclaude = configDir.
$launcher = if ($env:ANTHROPIC_BASE_URL) { 'gecko' } else { 'claude' }

New-Item -ItemType Directory -Force $dir | Out-Null
$entry = [ordered]@{
    wtSession      = $env:WT_SESSION
    launcher       = $launcher
    sessionId      = $in.session_id
    # Oturumun ilk klasörü saklanır (--resume konuşmayı o proje klasöründe arar); sonradan cd yapılsa da değişmez
    cwd            = if ($cur.sessionId -eq $in.session_id -and $cur.cwd) { $cur.cwd } else { $in.cwd }
    transcriptPath = $in.transcript_path
    configDir      = $env:CLAUDE_CONFIG_DIR
    claudePid      = $claude.Id
    claudeStart    = if ($claude) { $claude.StartTime.ToUniversalTime().ToString('o') }
    updated        = (Get-Date).ToUniversalTime().ToString('o')
}
$tmp = "$file.tmp"
$entry | ConvertTo-Json | Set-Content -Path $tmp -Encoding utf8
Move-Item -Force $tmp $file
exit 0
