# PowerShell profilinden dot-source edilir. Bu WT sekmesine (WT_SESSION) ait, artık çalışmayan
# bir Claude oturumu kayıtlıysa (restart/WT kapanması sonrası) onu aynı klasörde --resume ile açar.
& {
    $dir = Join-Path $HOME '.claude\session-registry'
    if (-not (Test-Path $dir)) { return }

    # 30 günden eski artık kayıtları temizle (kapatılmış sekmelerden kalanlar)
    Get-ChildItem $dir -Filter *.json | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item -Force

    $file = Join-Path $dir "$($env:WT_SESSION).json"
    if (-not (Test-Path $file)) { return }
    $e = Get-Content $file -Raw | ConvertFrom-Json
    if (-not $e.sessionId) { return }

    # Oturum hâlâ çalışıyorsa (ör. claude'un açtığı alt shell) dokunma
    if ($e.claudePid) {
        $p = Get-Process -Id $e.claudePid -ErrorAction SilentlyContinue
        if ($p -and $e.claudeStart -and
            [math]::Abs(($p.StartTime.ToUniversalTime() - ([datetime]$e.claudeStart).ToUniversalTime()).TotalSeconds) -lt 2) { return }
    }
    if ($e.transcriptPath -and -not (Test-Path $e.transcriptPath)) { Remove-Item $file -Force; return }
    if (-not (Test-Path $e.cwd)) { return }

    Set-Location $e.cwd
    Write-Host "↻ Claude oturumu geri yükleniyor: $($e.sessionId)  ($($e.cwd))" -ForegroundColor Cyan
    $prevCfg = $env:CLAUDE_CONFIG_DIR
    $env:CC_RESTORE_GUARD = '1'
    if ($e.configDir) { $env:CLAUDE_CONFIG_DIR = $e.configDir }
    try {
        switch ($e.launcher) {
            'gecko'       { gecko --resume $e.sessionId }
            default       { claude --resume $e.sessionId }   # configDir set ise = myclaude
        }
    }
    finally {
        $env:CLAUDE_CONFIG_DIR = $prevCfg
        Remove-Item Env:CC_RESTORE_GUARD -ErrorAction SilentlyContinue
    }
}
