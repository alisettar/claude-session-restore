# PowerShell profilinden dot-source edilir. Bu WT sekmesine (WT_SESSION) ait, artık çalışmayan
# bir Claude oturumu kayıtlıysa (restart/WT kapanması sonrası) onu aynı klasörde --resume ile açar.
& {
    . "$env:USERPROFILE\.claude-tools\session-restore\cc-common.ps1"
    if (-not (Test-Path $CcRegistryDir)) { return }

    # Açılıştan sonraki ilk shell: live.json açılıştan eskiyse kurtarmayı arka planda başlat. Dosyayı
    # atomik olarak taşıyan tek shell kazanır; düzgün restart'ta kurtarma oturumların canlandığını görüp çıkar.
    $boot = (Get-Date).AddMilliseconds(-[Environment]::TickCount64)
    if ((Test-Path $CcLiveFile) -and (Get-Item $CcLiveFile).LastWriteTime -lt $boot) {
        $snap = Join-Path $CcRegistryDir ("live.{0:yyyyMMdd-HHmmss}.recover.json" -f $boot)
        try {
            Move-Item $CcLiveFile $snap -ErrorAction Stop
            Start-Process pwsh -WindowStyle Hidden -ArgumentList @('-NoProfile', '-File',
                "$env:USERPROFILE\.claude-tools\session-restore\cc-recover.ps1", '-Snapshot', $snap)
        } catch { }
    }

    # 30 günden eski artık kayıtları temizle (kapatılmış sekmelerden kalanlar)
    Get-ChildItem $CcRegistryDir -Filter *.json | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item -Force

    $file = Join-Path $CcRegistryDir "$($env:WT_SESSION).json"
    if (-not (Test-Path $file)) { return }
    $e = Get-Content $file -Raw | ConvertFrom-Json
    if (-not $e.sessionId) { return }

    # Oturum hâlâ çalışıyorsa (ör. claude'un açtığı alt shell) dokunma
    if (Test-CcEntryAlive $e) { return }
    if ($e.transcriptPath -and -not (Test-Path $e.transcriptPath)) { Remove-Item $file -Force; return }
    $cwd = Resolve-CcResumeCwd $e.sessionId $e.cwd $e.configDir
    if (-not (Test-Path $cwd)) { return }

    Set-Location $cwd
    Write-Host "↻ Claude oturumu geri yükleniyor: $($e.sessionId)  ($cwd)" -ForegroundColor Cyan
    $prevCfg = $env:CLAUDE_CONFIG_DIR
    Clear-CcInheritedEnv
    $env:CC_RESTORE_GUARD = '1'
    if ($e.configDir) { $env:CLAUDE_CONFIG_DIR = $e.configDir }
    try {
        switch ($e.launcher) {
            'gecko' { gecko --resume $e.sessionId }
            default { claude --resume $e.sessionId }   # configDir set ise = myclaude
        }
    }
    finally {
        $env:CLAUDE_CONFIG_DIR = $prevCfg
        Remove-Item Env:CC_RESTORE_GUARD -ErrorAction SilentlyContinue
    }
}
