# gecko.ps1 --setting-sources project ile kullanıcı hook'larını yüklemez ve org'un server-managed
# ayarları varken managed-settings.json yok sayılır. Bu yüzden gecko oturumları burada kaydedilir:
# oturum bilinen bir --session-id ile başlatılır, kayıt elle yazılır, normal çıkışta silinir.
# Restart'ta finally çalışmaz → kayıt kalır → cc-restore.ps1 'gecko --resume <id>' ile geri açar.
$gecko = Join-Path $env:USERPROFILE '.claude-tools\gecko.ps1'
$uuid  = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

# WT dışı, headless (-p) ya da id'siz --resume/--continue (seçici) → kayıt yok, olduğu gibi çalıştır
$headless = $args | Where-Object { $_ -in '-p', '--print' }
$sid = $null; $picker = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -in '--resume', '-r', '--session-id') {
        if (($i + 1) -lt $args.Count -and $args[$i + 1] -match $uuid) { $sid = $args[$i + 1] } else { $picker = $true }
    }
    if ($args[$i] -in '--continue', '-c') { $picker = $true }
}
if (-not $env:WT_SESSION -or $headless -or ($picker -and -not $sid)) { & $gecko @args; return }

$extra = @()
if (-not $sid) { $sid = [guid]::NewGuid().ToString(); $extra = @('--session-id', $sid) }

$dir  = Join-Path $HOME '.claude\session-registry'
$file = Join-Path $dir "$($env:WT_SESSION).json"
New-Item -ItemType Directory -Force $dir | Out-Null
$shell = Get-Process -Id $PID
[ordered]@{
    wtSession   = $env:WT_SESSION
    launcher    = 'gecko'
    sessionId   = $sid
    cwd         = (Get-Location).Path
    configDir   = $env:CLAUDE_CONFIG_DIR
    claudePid   = $shell.Id            # gecko bu shell içinde çalışır; shell yaşıyorsa oturum yaşıyor
    claudeStart = $shell.StartTime.ToUniversalTime().ToString('o')
    updated     = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json | Set-Content $file -Encoding utf8

$env:CC_RESTORE_GUARD = '1'   # gecko'nun açtığı alt shell'ler geri yükleme yapmasın
try { & $gecko @extra @args }
finally {
    Remove-Item Env:CC_RESTORE_GUARD -ErrorAction SilentlyContinue
    $cur = Get-Content $file -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($cur.sessionId -eq $sid) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}
