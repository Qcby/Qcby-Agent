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
        throw "Please run install.ps1 in an elevated Administrator PowerShell window."
    }
}

function Remove-Client {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    if (Test-Path $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force }
    Write-Host "Windows client removed: $TaskName"
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

function Get-AgentSourcePath {
    $repoAgent = Join-Path $PSScriptRoot 'agent.ps1'
    if (Test-Path $repoAgent) { return $repoAgent }

    $tempAgent = Join-Path $env:TEMP "qcby-agent-agent.ps1"
    $downloadUrl = Get-CacheBustedUrl -RelativePath 'client/windows/agent.ps1'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempAgent -UseBasicParsing
    if (-not (Test-Path $tempAgent)) {
        throw "Failed to download agent.ps1 from: $downloadUrl"
    }
    return $tempAgent
}

Ensure-Admin

if ($Uninstall) {
    Remove-Client
    exit 0
}

if (-not $ServerHost) {
    $defaultServerHost = Get-PublicIp
    if (-not $defaultServerHost) { $defaultServerHost = Get-PrivateIp }
    if (-not $defaultServerHost) { $defaultServerHost = $env:COMPUTERNAME }
    $ServerHost = Read-Value -Prompt 'Server host or IP (default: auto-detect this machine IP)' -Default $defaultServerHost
}
if (-not $Token) { $Token = Read-Value -Prompt 'Agent token' -Default 'change-me-token' }
if (-not $AgentId) { $AgentId = Read-Value -Prompt 'Agent ID' -Default $env:COMPUTERNAME }
if (-not $Region) { $Region = Read-Value -Prompt 'Region (optional)' }
if (-not $ISP) { $ISP = Read-Value -Prompt 'ISP / line (optional)' }
if (-not $Tags -or $Tags.Count -eq 0) {
    $rawTags = Read-Value -Prompt 'Tags, comma separated (optional)'
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
Write-Host "Qcby-Agent Windows client installed."
Write-Host "  Report URL: $serverUrl"
Write-Host "  Install dir: $InstallDir"
Write-Host "  Scheduled task: $TaskName"
Write-Host "  Mode: silent background run, auto start on boot, no cmd flash."
Write-Host ""
Write-Host "Uninstall command:"
Write-Host "  PowerShell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TaskName `"$TaskName`" -InstallDir `"$InstallDir`" -Uninstall"
