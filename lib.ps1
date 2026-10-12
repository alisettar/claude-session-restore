# install.ps1 / uninstall.ps1 ortak tanımları
$InstallDir  = Join-Path $HOME '.claude-tools\session-restore'
$RegistryDir = Join-Path $HOME '.claude\session-registry'
$HookMarker  = 'cc-session-registry'
$HookEvents  = [ordered]@{ SessionStart = 'start'; UserPromptSubmit = 'prompt'; SessionEnd = 'end' }
$TerminalSettings = [ordered]@{ firstWindowPreference = '"persistedWindowLayout"'; startOnUserLogin = 'true' }

# Profil bloğu. gecko sarmalayıcısı yalnızca gecko kuruluysa tanımlanır; restore satırı en sonda olmalı.
$ProfileBlockPattern = '(?s)# >>> claude session restore.*?# <<< claude session restore <<<\r?\n?'
$ProfileBlock = @'
# >>> claude session restore (restart sonrası sekmedeki Claude oturumunu geri açar) >>>
if (Test-Path "$env:USERPROFILE\.claude-tools\gecko.ps1") { function gecko { & "$env:USERPROFILE\.claude-tools\session-restore\cc-gecko-wrap.ps1" @args } }
if ($env:WT_SESSION -and -not $env:CC_RESTORE_GUARD) { . "$env:USERPROFILE\.claude-tools\session-restore\cc-restore.ps1" }
# <<< claude session restore <<<

'@

function New-RegistryHook([string]$script, [string]$arg) {
    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'pwsh'; args = @('-NoProfile', '-NonInteractive', '-File', $script, $arg) }) }
}

function Test-OurHook($entry) { ($entry | ConvertTo-Json -Depth 10 -Compress) -match $HookMarker }

function Get-TerminalSettingsFiles {
    @(
        Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Microsoft.WindowsTerminal*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'LocalState\settings.json' }
        Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'   # paketsiz kurulum
    ) | Where-Object { Test-Path $_ }
}

# WT settings.json JSONC (yorum içerebilir) olduğundan parse edip yeniden yazmak yerine metin üzerinde
# en üst seviye anahtarı günceller ya da ilk '{' sonrasına ekler.
function Set-JsoncTopLevel([string]$text, [string]$key, [string]$jsonValue) {
    $pattern = '(?m)^(\s*)"' + [regex]::Escape($key) + '"\s*:\s*[^,\r\n]+'
    if ($text -match $pattern) {
        return [regex]::Replace($text, $pattern, { param($m) "$($m.Groups[1].Value)`"$key`": $jsonValue" }, 1)
    }
    return ([regex]'\{\r?\n').Replace($text, "{`r`n    `"$key`": $jsonValue,`r`n", 1)
}

function Remove-JsoncTopLevel([string]$text, [string]$key) {
    [regex]::Replace($text, '(?m)^\s*"' + [regex]::Escape($key) + '"\s*:\s*[^,\r\n]+,?\r?\n', '')
}
