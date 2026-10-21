# Ortak tanımlar: hook, profil, gecko sarmalayıcısı ve kurtarma betiği dot-source eder.
$CcRegistryDir = Join-Path $HOME '.claude\session-registry'
$CcLiveFile    = Join-Path $CcRegistryDir 'live.json'   # o an çalışan oturumların anlık görüntüsü
$CcRecoverLog  = Join-Path $CcRegistryDir 'recover.log'

# Kayıttaki Claude süreci hâlâ aynı süreç mi? (PID yeniden kullanımına karşı başlangıç zamanı da karşılaştırılır)
function Test-CcEntryAlive($e) {
    if (-not $e.claudePid -or -not $e.claudeStart) { return $false }
    $p = Get-Process -Id $e.claudePid -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    [math]::Abs(($p.StartTime.ToUniversalTime() - ([datetime]$e.claudeStart).ToUniversalTime()).TotalSeconds) -lt 2
}

# --resume konuşmayı yalnızca açıldığı klasörün proje dizininde (~/.claude/projects/<kodlanmış yol>) arar.
# Kayıttaki klasör bir alt dizinse (oturum içinde cd yapılmışsa) konuşmanın gerçekten durduğu üst klasörü bul.
function Resolve-CcResumeCwd([string]$SessionId, [string]$Cwd, [string]$ConfigDir) {
    $projects = Join-Path ($ConfigDir ? $ConfigDir : (Join-Path $HOME '.claude')) 'projects'
    $tx = Get-ChildItem $projects -Filter "$SessionId.jsonl" -Recurse -Depth 1 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $tx) { return $Cwd }
    for ($d = $Cwd; $d; $d = Split-Path $d -Parent) {
        if (($d -replace '[^a-zA-Z0-9]', '-') -eq $tx.Directory.Name) { return $d }   # Claude'un klasör kodlaması
    }
    return $Cwd
}

function Get-CcEntries {
    Get-ChildItem $CcRegistryDir -Filter '*-*-*-*-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        try { Get-Content $_.FullName -Raw | ConvertFrom-Json } catch { }
    } | Where-Object { $_.sessionId }
}

# Çalışan oturumların listesini live.json'a yazar. Çökmede Windows Terminal düzeni kaydedemediği için
# açılışta hangi oturumların geri açılacağı buradan okunur (cc-recover.ps1).
function Update-CcLiveSnapshot {
    $live = @(Get-CcEntries | Where-Object { Test-CcEntryAlive $_ } |
        Sort-Object { if ($_.created) { [datetime]$_.created } else { [datetime]$_.updated } } |
        Select-Object sessionId, cwd, configDir, launcher, wtSession, created, updated)
    $tmp = "$CcLiveFile.$PID.tmp"
    ConvertTo-Json -InputObject $live -Depth 5 | Set-Content $tmp -Encoding utf8
    Move-Item -Force $tmp $CcLiveFile
}
