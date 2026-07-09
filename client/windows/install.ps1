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
        throw "请以管理员 PowerShell 运行 install.ps1。"
    }
}

function Remove-Client {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    if (Test-Path $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force }
    Write-Host "已卸载 Windows 客户端：$TaskName"
}

Ensure-Admin

if ($Uninstall) {
    Remove-Client
    exit 0
}

if (-not $ServerHost) { $ServerHost = Read-Value -Prompt '服务端 IP / 域名' -Default '146.56.140.150' }
if (-not $Token) { $Token = Read-Value -Prompt 'Agent Token' -Default 'change-me-token' }
if (-not $AgentId) { $AgentId = Read-Value -Prompt 'Agent ID' -Default $env:COMPUTERNAME }
if (-not $Region) { $Region = Read-Value -Prompt '区域（可留空）' }
if (-not $ISP) { $ISP = Read-Value -Prompt '运营商 / 线路（可留空）' }
if (-not $Tags -or $Tags.Count -eq 0) {
    $rawTags = Read-Value -Prompt '标签，逗号分隔（可留空）'
    if ($rawTags) { $Tags = @($rawTags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}

$repoAgent = Join-Path $PSScriptRoot 'agent.ps1'
if (-not (Test-Path $repoAgent)) {
    throw "未找到 agent.ps1：$repoAgent"
}

$serverUrl = "http://$ServerHost`:$Port/api/v1/report"
$agentFile = Join-Path $InstallDir 'agent.ps1'
$configFile = Join-Path $InstallDir 'agent-config.ps1'
$runnerFile = Join-Path $InstallDir 'run-agent.ps1'

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -LiteralPath $repoAgent -Destination $agentFile -Force

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
Write-Host "Qcby-Agent Windows 客户端已安装。"
Write-Host "  服务端上报地址: $serverUrl"
Write-Host "  安装目录: $InstallDir"
Write-Host "  计划任务: $TaskName"
Write-Host "  已配置为后台静默运行、开机自启、无 cmd 闪屏。"
Write-Host ""
Write-Host "卸载命令："
Write-Host "  PowerShell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TaskName `"$TaskName`" -InstallDir `"$InstallDir`" -Uninstall"
