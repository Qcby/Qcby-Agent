param(
    [string]$ServerHost = "",
    [int]$Port = 8080,
    [string]$Token = "",
    [string]$AgentId = $env:COMPUTERNAME,
    [int]$IntervalSeconds = 30,
    [string]$Region = "",
    [string]$ISP = "",
    [string[]]$Tags = @(),
    [string]$InstallDir = "$env:ProgramData\\Qcby-Agent",
    [string]$TaskName = "Qcby-Agent-Client",
    [string]$RawBase = $(if ($env:QCBY_AGENT_RAW_BASE) { $env:QCBY_AGENT_RAW_BASE } else { 'https://raw.githubusercontent.com/Qcby/Qcby-Agent/main' }),
    [switch]$Uninstall,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

function U {
    param([string]$Text)
    return [regex]::Unescape($Text)
}

function Read-Value {
    param(
        [string]$Prompt,
        [string]$Default = ''
    )
    $answer = Read-Host ("{0}{1}" -f $Prompt, $(if ($Default) { " [$Default]" } else { '' }))
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw (U '\u8bf7\u4ee5\u7ba1\u7406\u5458 PowerShell \u7a97\u53e3\u8fd0\u884c install.ps1\u3002')
    }
}

function Remove-Client {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    if (Test-Path $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force }
    Write-Host ((U '\u5df2\u5378\u8f7d Windows \u5ba2\u6237\u7aef\uff1a') + $TaskName)
}

function Get-PublicIp {
    foreach ($url in @('https://api4.ipify.org', 'https://api.ip.sb/ip', 'https://api.ipify.org')) {
        try {
            $value = (Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 8).ToString().Trim()
            if ($value) { return $value }
        } catch {}
    }
    return ''
}

function Get-PrivateIp {
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
            Select-Object -First 1 -ExpandProperty IPAddress
        if ($ip) { return $ip.ToString().Trim() }
    } catch {}
    return ''
}

function Get-CacheBustedUrl {
    param([string]$RelativePath)
    $base = $RawBase.TrimEnd('/')
    $join = "$base/$RelativePath"
    $sep = $(if ($join -like '*?*') { '&' } else { '?' })
    return "$join${sep}t=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}

function Get-AgentDownloadUrls {
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return @(
        ("{0}/client/windows/agent.ps1?t={1}" -f $RawBase.TrimEnd('/'), $stamp),
        ("https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/client/windows/agent.ps1?t={0}" -f $stamp),
        ("https://raw.githubusercontent.com/Qcby/Qcby-Agent/HEAD/client/windows/agent.ps1?t={0}" -f $stamp),
        ("https://cdn.jsdelivr.net/gh/Qcby/Qcby-Agent@main/client/windows/agent.ps1?t={0}" -f $stamp)
    )
}

function Get-AgentSourcePath {
    $repoAgent = Join-Path $PSScriptRoot 'agent.ps1'
    if (Test-Path $repoAgent) { return $repoAgent }

    $tempAgent = Join-Path $env:TEMP "qcby-agent-agent.ps1"
    $lastError = $null
    foreach ($downloadUrl in (Get-AgentDownloadUrls)) {
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempAgent -UseBasicParsing
            if ((Test-Path $tempAgent) -and (Get-Item $tempAgent).Length -gt 0) {
                return $tempAgent
            }
        } catch {
            $lastError = $_
        }
    }
    if (Test-Path $tempAgent) { Remove-Item -LiteralPath $tempAgent -Force -ErrorAction SilentlyContinue }
    if ($lastError) {
        throw ((U '\u8fdc\u7a0b\u4e0b\u8f7d agent.ps1 \u5931\u8d25\uff0c\u6240\u6709\u56de\u9000\u5730\u5740\u5747\u4e0d\u53ef\u7528\u3002\u6700\u540e\u9519\u8bef\uff1a') + ' ' + $lastError.Exception.Message)
    }
    throw (U '\u8fdc\u7a0b\u4e0b\u8f7d agent.ps1 \u5931\u8d25\uff0c\u672a\u83b7\u53d6\u5230\u53ef\u7528\u6587\u4ef6\u3002')
}

Ensure-Admin

if ($Uninstall) {
    Remove-Client
    exit 0
}

if (-not $ServerHost) {
    $ServerHost = Read-Value -Prompt (U '\u670d\u52a1\u7aef IP / \u57df\u540d')
}
if (-not $Token) { $Token = Read-Value -Prompt (U '\u0041\u0067\u0065\u006e\u0074\u0020\u0054\u006f\u006b\u0065\u006e') -Default 'change-me-token' }
if (-not $AgentId) { $AgentId = Read-Value -Prompt (U '\u0041\u0067\u0065\u006e\u0074\u0020\u0049\u0044') -Default $env:COMPUTERNAME }
if (-not $Region) { $Region = Read-Value -Prompt (U '\u533a\u57df\uff08\u53ef\u7559\u7a7a\uff09') }
if (-not $ISP) { $ISP = Read-Value -Prompt (U '\u8fd0\u8425\u5546 / \u7ebf\u8def\uff08\u53ef\u7559\u7a7a\uff09') }
if (-not $Tags -or $Tags.Count -eq 0) {
    $rawTags = Read-Value -Prompt (U '\u6807\u7b7e\uff0c\u9017\u53f7\u5206\u9694\uff08\u53ef\u7559\u7a7a\uff09')
    if ($rawTags) { $Tags = @($rawTags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}

$sourceAgent = Get-AgentSourcePath

$serverUrl = "http://$ServerHost`:$Port/api/v1/report"
$agentFile = Join-Path $InstallDir 'agent.ps1'
$configFile = Join-Path $InstallDir 'agent-config.ps1'
$runnerFile = Join-Path $InstallDir 'run-agent.ps1'

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -LiteralPath $sourceAgent -Destination $agentFile -Force

$tagsLiteral = ($Tags | ForEach-Object { "'{0}'" -f ($_.Replace("'", "''")) }) -join ', '
$configContent = @"
`$AgentConfig = @{
    ServerUrl = '$serverUrl'
    AgentId = '$AgentId'
    IntervalSeconds = $IntervalSeconds
    Token = '$Token'
    Region = '$Region'
    ISP = '$ISP'
    Tags = @($tagsLiteral)
}
"@
Set-Content -Encoding UTF8 -Path $configFile -Value $configContent

$runnerContent = @"
`$ErrorActionPreference = 'Stop'
. `"$configFile`"
& `"$agentFile`" @AgentConfig
"@
Set-Content -Encoding UTF8 -Path $runnerFile -Value $runnerContent

$taskAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runnerFile`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$task = New-ScheduledTask -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings

try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
Register-ScheduledTask -TaskName $TaskName -InputObject $task | Out-Null

if (-not $NoStart) {
    Start-Process -FilePath 'PowerShell.exe' -ArgumentList "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runnerFile`"" -WindowStyle Hidden
}

Write-Host ""
Write-Host (U '\u0051\u0063\u0062\u0079\u002d\u0041\u0067\u0065\u006e\u0074\u0020\u0057\u0069\u006e\u0064\u006f\u0077\u0073 \u5ba2\u6237\u7aef\u5df2\u5b89\u88c5\u3002')
Write-Host ((U '  \u670d\u52a1\u7aef\u4e0a\u62a5\u5730\u5740\uff1a') + $serverUrl)
Write-Host ((U '  \u5b89\u88c5\u76ee\u5f55\uff1a') + $InstallDir)
Write-Host ((U '  \u8ba1\u5212\u4efb\u52a1\uff1a') + $TaskName)
Write-Host (U '  \u5df2\u914d\u7f6e\u4e3a\u540e\u53f0\u9759\u9ed8\u8fd0\u884c\u3001\u5f00\u673a\u81ea\u542f\u3001\u65e0 cmd \u95ea\u5c4f\u3002')
Write-Host ""
Write-Host (U '\u5378\u8f7d\u547d\u4ee4\uff1a')
Write-Host "  PowerShell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TaskName `"$TaskName`" -InstallDir `"$InstallDir`" -Uninstall"
