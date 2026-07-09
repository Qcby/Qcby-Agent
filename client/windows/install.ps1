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
    [string]$Action = "",
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

function Get-ConfigFilePath { Join-Path $InstallDir 'agent-config.ps1' }
function Get-AgentFilePath { Join-Path $InstallDir 'agent.ps1' }
function Get-RunnerFilePath { Join-Path $InstallDir 'run-agent.ps1' }

function Read-ExistingConfig {
    $configPath = Get-ConfigFilePath
    if (-not (Test-Path $configPath)) { return $null }
    . $configPath
    return $AgentConfig
}

function Test-ClientInstalled {
    return (Test-Path (Get-ConfigFilePath)) -or (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Remove-Client {
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    if (Test-Path $InstallDir) { Remove-Item -LiteralPath $InstallDir -Recurse -Force }
    Write-Host ((U '\u5df2\u5378\u8f7d Windows \u5ba2\u6237\u7aef\uff1a') + $TaskName)
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

function Save-Config {
    param(
        [hashtable]$Config
    )
    $configFile = Get-ConfigFilePath
    $tagsLiteral = (($Config.Tags | ForEach-Object { "'{0}'" -f ($_.Replace("'", "''")) }) -join ', ')
    $configContent = @"
`$AgentConfig = @{
    ServerUrl = '$($Config.ServerUrl)'
    AgentId = '$($Config.AgentId)'
    IntervalSeconds = $($Config.IntervalSeconds)
    Token = '$($Config.Token)'
    Region = '$($Config.Region)'
    ISP = '$($Config.ISP)'
    Tags = @($tagsLiteral)
}
"@
    Set-Content -Encoding UTF8 -Path $configFile -Value $configContent
}

function Ensure-AgentFiles {
    $agentFile = Get-AgentFilePath
    $sourceAgent = Get-AgentSourcePath
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -LiteralPath $sourceAgent -Destination $agentFile -Force

    $runnerFile = Get-RunnerFilePath
    $configFile = Get-ConfigFilePath
    $runnerContent = @"
`$ErrorActionPreference = 'Stop'
. `"$configFile`"
& `"$agentFile`" @AgentConfig
"@
    Set-Content -Encoding UTF8 -Path $runnerFile -Value $runnerContent
}

function Register-AgentTask {
    $runnerFile = Get-RunnerFilePath
    $taskAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runnerFile`""
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $task = New-ScheduledTask -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    Register-ScheduledTask -TaskName $TaskName -InputObject $task | Out-Null
}

function Prompt-Config {
    $existing = Read-ExistingConfig
    $serverHostDefault = ''
    $portDefault = '8080'
    $tokenDefault = 'change-me-token'
    $agentIdDefault = $env:COMPUTERNAME
    $intervalDefault = '30'
    $regionDefault = ''
    $ispDefault = ''
    $tagsDefault = ''

    if ($existing) {
        $serverUri = [Uri]$existing.ServerUrl
        $serverHostDefault = $serverUri.Host
        $portDefault = "$($serverUri.Port)"
        $tokenDefault = [string]$existing.Token
        $agentIdDefault = [string]$existing.AgentId
        $intervalDefault = "$([int]$existing.IntervalSeconds)"
        $regionDefault = [string]$existing.Region
        $ispDefault = [string]$existing.ISP
        $tagsDefault = @($existing.Tags) -join ','
    }

    if (-not $ServerHost) { $ServerHost = Read-Value -Prompt (U '\u670d\u52a1\u7aef IP / \u57df\u540d') -Default $serverHostDefault }
    if (-not $Port) { $Port = [int](Read-Value -Prompt (U '\u670d\u52a1\u7aef\u7aef\u53e3') -Default $portDefault) }
    if (-not $Token) { $Token = Read-Value -Prompt (U '\u0041\u0067\u0065\u006e\u0074\u0020\u0054\u006f\u006b\u0065\u006e') -Default $tokenDefault }
    if (-not $AgentId) { $AgentId = Read-Value -Prompt (U '\u0041\u0067\u0065\u006e\u0074\u0020\u0049\u0044') -Default $agentIdDefault }
    if (-not $IntervalSeconds) { $IntervalSeconds = [int](Read-Value -Prompt (U '\u4e0a\u62a5\u95f4\u9694\u79d2\u6570') -Default $intervalDefault) }
    if (-not $Region) { $Region = Read-Value -Prompt (U '\u533a\u57df\uff08\u53ef\u7559\u7a7a\uff09') -Default $regionDefault }
    if (-not $ISP) { $ISP = Read-Value -Prompt (U '\u8fd0\u8425\u5546 / \u7ebf\u8def\uff08\u53ef\u7559\u7a7a\uff09') -Default $ispDefault }
    if (-not $Tags -or $Tags.Count -eq 0) {
        $rawTags = Read-Value -Prompt (U '\u6807\u7b7e\uff0c\u9017\u53f7\u5206\u9694\uff08\u53ef\u7559\u7a7a\uff09') -Default $tagsDefault
        if ($rawTags) { $Tags = @($rawTags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { $Tags = @() }
    }

    return @{
        ServerUrl = "http://$ServerHost`:$Port/api/v1/report"
        AgentId = $AgentId
        IntervalSeconds = [int]$IntervalSeconds
        Token = $Token
        Region = $Region
        ISP = $ISP
        Tags = @($Tags)
    }
}

function Install-OrReconfigure {
    $config = Prompt-Config
    Save-Config -Config $config
    Ensure-AgentFiles
    Register-AgentTask
    if (-not $NoStart) { Start-Agent }

    Write-Host ""
    Write-Host (U '\u0051\u0063\u0062\u0079\u002d\u0041\u0067\u0065\u006e\u0074\u0020\u0057\u0069\u006e\u0064\u006f\u0077\u0073 \u5ba2\u6237\u7aef\u5df2\u5b89\u88c5\u3002')
    Write-Host ((U '  \u670d\u52a1\u7aef\u4e0a\u62a5\u5730\u5740\uff1a') + $config.ServerUrl)
    Write-Host ((U '  \u5b89\u88c5\u76ee\u5f55\uff1a') + $InstallDir)
    Write-Host ((U '  \u8ba1\u5212\u4efb\u52a1\uff1a') + $TaskName)
    Write-Host (U '  \u5df2\u914d\u7f6e\u4e3a\u540e\u53f0\u9759\u9ed8\u8fd0\u884c\u3001\u5f00\u673a\u81ea\u542f\u3001\u65e0 cmd \u95ea\u5c4f\u3002')
}

function Upgrade-Agent {
    $existing = Read-ExistingConfig
    if (-not $existing) {
        throw (U '\u672a\u68c0\u6d4b\u5230\u5df2\u6709\u914d\u7f6e\uff0c\u8bf7\u5148\u6267\u884c\u5b89\u88c5\u3002')
    }
    Ensure-AgentFiles
    Register-AgentTask
    if (-not $NoStart) { Restart-Agent }
    Write-Host (U '\u5df2\u4fdd\u7559\u539f\u6709\u914d\u7f6e\u5b8c\u6210\u5347\u7ea7\u3002')
}

function Start-Agent {
    $runnerFile = Get-RunnerFilePath
    if (-not (Test-Path $runnerFile)) {
        throw (U '\u672a\u68c0\u6d4b\u5230\u5df2\u5b89\u88c5\u7684 Windows \u5ba2\u6237\u7aef\uff0c\u8bf7\u5148\u5b89\u88c5\u3002')
    }
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
    Start-Process -FilePath 'PowerShell.exe' -ArgumentList "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runnerFile`"" -WindowStyle Hidden
    Write-Host (U '\u5ba2\u6237\u7aef\u5df2\u542f\u52a8\u3002')
}

function Stop-Agent {
    Get-CimInstance Win32_Process |
        Where-Object { $_.Name -match 'powershell|pwsh' -and $_.CommandLine -match [regex]::Escape((Get-RunnerFilePath)) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
    Write-Host (U '\u5ba2\u6237\u7aef\u5df2\u505c\u6b62\u3002')
}

function Restart-Agent {
    Stop-Agent
    Start-Agent
}

function Show-Status {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host (U '\u672a\u68c0\u6d4b\u5230\u5df2\u5b89\u88c5\u7684 Windows \u5ba2\u6237\u7aef\u3002')
        return
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ((U '\u8ba1\u5212\u4efb\u52a1\uff1a') + " $TaskName")
    Write-Host ((U '\u4efb\u52a1\u72b6\u6001\uff1a') + " $($task.State)")
    Write-Host ((U '\u4e0a\u6b21\u8fd0\u884c\uff1a') + " $($info.LastRunTime)")
    Write-Host ((U '\u4e0a\u6b21\u7ed3\u679c\uff1a') + " $($info.LastTaskResult)")
    if (Test-Path (Get-ConfigFilePath)) {
        . (Get-ConfigFilePath)
        Write-Host ((U '\u4e0a\u62a5\u5730\u5740\uff1a') + " $($AgentConfig.ServerUrl)")
    }
}

function Show-LogHint {
    Write-Host (U '\u5f53\u524d Windows \u5ba2\u6237\u7aef\u4e3a\u540e\u53f0\u9759\u9ed8\u8fd0\u884c\u3002')
    Write-Host (U '\u5982\u9700\u6392\u67e5\uff0c\u8bf7\u624b\u52a8\u6267\u884c\uff1a')
    Write-Host "  PowerShell -ExecutionPolicy Bypass -File `"$((Get-AgentFilePath))`" -ServerUrl `"<your-url>`" -Token `"<your-token>`""
}

function Show-Menu {
    Write-Host (U '\u8bf7\u9009\u62e9\u64cd\u4f5c\uff1a')
    Write-Host (U '1) \u5b89\u88c5')
    Write-Host (U '2) \u5347\u7ea7')
    Write-Host (U '3) \u5378\u8f7d')
    Write-Host (U '4) \u542f\u52a8')
    Write-Host (U '5) \u91cd\u542f')
    Write-Host (U '6) \u505c\u6b62')
    Write-Host (U '7) \u67e5\u770b\u72b6\u6001')
    Write-Host (U '8) \u67e5\u770b\u65e5\u5fd7\u8bf4\u660e')
    Write-Host (U '9) \u91cd\u65b0\u914d\u7f6e')
    Write-Host (U '0) \u9000\u51fa')
    $choice = Read-Host (U '\u8f93\u5165\u6570\u5b57')
    switch ($choice) {
        '1' { Install-OrReconfigure }
        '2' { Upgrade-Agent }
        '3' { Remove-Client }
        '4' { Start-Agent }
        '5' { Restart-Agent }
        '6' { Stop-Agent }
        '7' { Show-Status }
        '8' { Show-LogHint }
        '9' { Install-OrReconfigure }
        '0' { return }
        default { throw (U '\u65e0\u6548\u9009\u62e9\u3002') }
    }
}

Ensure-Admin

if ($Uninstall) {
    Remove-Client
    exit 0
}

switch ($Action.ToLowerInvariant()) {
    'install' { Install-OrReconfigure; exit 0 }
    'update' { Install-OrReconfigure; exit 0 }
    'upgrade' { Upgrade-Agent; exit 0 }
    'uninstall' { Remove-Client; exit 0 }
    'start' { Start-Agent; exit 0 }
    'restart' { Restart-Agent; exit 0 }
    'stop' { Stop-Agent; exit 0 }
    'status' { Show-Status; exit 0 }
    'logs' { Show-LogHint; exit 0 }
    'reconfigure' { Install-OrReconfigure; exit 0 }
    '' { Show-Menu; exit 0 }
    default { throw ((U '\u672a\u77e5\u64cd\u4f5c\uff1a') + " $Action") }
}
