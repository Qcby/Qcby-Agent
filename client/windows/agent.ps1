param(
    [string]$ServerUrl = "http://146.56.140.150:8080/api/v1/report",
    [string]$AgentId = $env:COMPUTERNAME,
    [int]$IntervalSeconds = 15,
    [string]$Token = "change-me-token",
    [string]$Region = "",
    [string]$ISP = "",
    [string[]]$Tags = @()
)

$ErrorActionPreference = 'Stop'
function Get-StringValue {
    param(
        $Primary,
        $Fallback = ''
    )
    if ($null -ne $Primary -and [string]$Primary -ne '') { return [string]$Primary }
    if ($null -ne $Fallback -and [string]$Fallback -ne '') { return [string]$Fallback }
    return ''
}

function Test-ContainsCjk {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '[\u3400-\u9fff]'
}

function Join-UniqueParts {
    param(
        [string[]]$Parts,
        [string]$Separator = ' '
    )
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($part in $Parts) {
        $text = [string]$part
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $trimmed = $text.Trim()
            if ($trimmed -and -not $result.Contains($trimmed)) {
                [void]$result.Add($trimmed)
            }
        }
    }
    return ($result -join $Separator)
}

function Normalize-GeoPayload {
    param(
        $Geo,
        [string]$Source,
        [bool]$PreferChinese = $false,
        [string]$PublicIp = ''
    )
    $countryCode = Get-StringValue $Geo.country_code (Get-StringValue $Geo.countryCode '')
    $countryName = Get-StringValue $Geo.country (Get-StringValue $Geo.country_name '')
    $regionName = Get-StringValue $Geo.regionName (Get-StringValue $Geo.region_name $Geo.region)
    $cityName = Get-StringValue $Geo.city (Get-StringValue $Geo.city_name '')
    $locationLabelRaw = Get-StringValue $Geo.location_label $Geo.location
    $connIsp = ''
    if ($Geo.connection) { $connIsp = Get-StringValue $Geo.connection.isp $Geo.connection.org }
    $ispName = Get-StringValue $Geo.isp (Get-StringValue $Geo.organization (Get-StringValue $Geo.org $connIsp))

    $countryNameZh = Get-StringValue $Geo.country_name_zh (Get-StringValue $Geo.country_zh '')
    $regionNameZh = Get-StringValue $Geo.region_name_zh (Get-StringValue $Geo.region_zh $Geo.regionNameZh)
    $cityNameZh = Get-StringValue $Geo.city_name_zh (Get-StringValue $Geo.city_zh '')
    $locationLabelZh = Get-StringValue $Geo.location_label_zh $Geo.location_zh

    if ($PreferChinese -or (Test-ContainsCjk $countryName)) {
        $countryNameZh = Get-StringValue $countryNameZh $countryName
    }
    if ($PreferChinese -or (Test-ContainsCjk $regionName)) {
        $regionNameZh = Get-StringValue $regionNameZh $regionName
    }
    if ($PreferChinese -or (Test-ContainsCjk $cityName)) {
        $cityNameZh = Get-StringValue $cityNameZh $cityName
    }
    if ($PreferChinese -or (Test-ContainsCjk $locationLabelRaw)) {
        $locationLabelZh = Get-StringValue $locationLabelZh $locationLabelRaw
    }

    if (-not $locationLabelZh) {
        $locationLabelZh = Join-UniqueParts -Parts @($countryNameZh, $regionNameZh, $cityNameZh) -Separator ' '
    }

    $primaryCountry = Get-StringValue $countryNameZh $countryName
    $primaryRegion = Get-StringValue $regionNameZh $regionName
    $primaryCity = Get-StringValue $cityNameZh $cityName
    $locationLabel = Get-StringValue $locationLabelZh $locationLabelRaw
    if (-not $locationLabel) {
        $locationLabel = Join-UniqueParts -Parts @($(if ($primaryCountry) { $primaryCountry } else { $countryCode }), $primaryRegion, $primaryCity) -Separator ' '
    }

    return [ordered]@{
        public_ip = $PublicIp
        country_code = $countryCode
        country_name = $primaryCountry
        country_name_zh = $countryNameZh
        region_name = $primaryRegion
        region_name_zh = $regionNameZh
        city_name = $primaryCity
        city_name_zh = $cityNameZh
        location_label = $locationLabel
        location_label_zh = $locationLabelZh
        isp_name = $ispName
        geo_source = $Source
    }
}

function Get-IpAddresses {
    try {
        return @(Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
            Select-Object -ExpandProperty IPAddress -Unique)
    }
    catch {
        return @()
    }
}

function Get-PublicIp {
    $endpoints = @(
        'https://api4.ipify.org',
        'https://api.ip.sb/ip',
        'https://api.ipify.org'
    )
    foreach ($url in $endpoints) {
        try {
            $value = (Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 8).ToString().Trim()
            if ($value) { return $value }
        }
        catch {}
    }
    return ''
}

function Get-GeoInfo {
    $publicIp = Get-PublicIp
    $result = [ordered]@{
        public_ip = $publicIp
        country_code = ''
        country_name = ''
        country_name_zh = ''
        region_name = ''
        region_name_zh = ''
        city_name = ''
        city_name_zh = ''
        location_label = ''
        location_label_zh = ''
        isp_name = ''
        geo_source = ''
    }
    if (-not $publicIp) { return $result }
    try {
        foreach ($geoQuery in @(
            [pscustomobject]@{ Url = ("http://ip-api.com/json/{0}?lang=zh-CN" -f $publicIp); Source = 'ip-api-zh'; PreferChinese = $true },
            [pscustomobject]@{ Url = ("https://ipwho.is/{0}" -f $publicIp); Source = 'ipwho.is'; PreferChinese = $false },
            [pscustomobject]@{ Url = ("https://api.ip.sb/geoip/{0}" -f $publicIp); Source = 'api.ip.sb'; PreferChinese = $false }
        )) {
            try {
                $geo = Invoke-RestMethod -Uri $geoQuery.Url -Method Get -TimeoutSec 10
                if (-not $geo) { continue }
                $failed = ($geo.status -eq 'fail') -or ($null -ne $geo.success -and -not [bool]$geo.success)
                if ($failed) { continue }
                $normalized = Normalize-GeoPayload -Geo $geo -Source $geoQuery.Source -PreferChinese:$geoQuery.PreferChinese -PublicIp $publicIp
                if ($normalized.country_code -or $normalized.country_name -or $normalized.location_label) {
                    return $normalized
                }
            }
            catch {}
        }
    }
    catch {}
    return $result
}

function Get-DockerVersion {
    try {
        $ver = docker version --format '{{.Server.Version}}' 2>$null
        if ($LASTEXITCODE -eq 0) { return $ver.Trim() }
    }
    catch {}
    return $null
}

function Get-DockerStats {
    $result = [ordered]@{ docker_running = $false; docker_containers_running = 0; docker_containers_total = 0 }
    try {
        docker info > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            $result.docker_running = $true
            $result.docker_containers_running = @(docker ps -q 2>$null).Count
            $result.docker_containers_total = @(docker ps -aq 2>$null).Count
        }
    }
    catch {}
    return $result
}

function Get-NetworkSnapshot {
    $stats = Get-NetAdapterStatistics | Where-Object { $_.ReceivedBytes -ge 0 -and $_.SentBytes -ge 0 }
    $rx = ($stats | Measure-Object -Property ReceivedBytes -Sum).Sum
    $tx = ($stats | Measure-Object -Property SentBytes -Sum).Sum
    return [ordered]@{ rx = [double]$rx; tx = [double]$tx; ts = Get-Date }
}


function Get-UptimeSeconds {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $boot = $os.LastBootUpTime
        if (-not $boot) { return 0 }
        return [int][math]::Max(0, ((Get-Date) - [datetime]$boot).TotalSeconds)
    }
    catch {
        return 0
    }
}

function Get-SystemFlavorTag {
    param([string]$Caption)
    $v = $Caption.ToLowerInvariant()
    if ($v -match 'windows 11') { return 'win11' }
    if ($v -match 'windows 10') { return 'win10' }
    if ($v -match 'server 2025') { return 'server2025' }
    if ($v -match 'server 2022') { return 'server2022' }
    if ($v -match 'server 2019') { return 'server2019' }
    return 'windows'
}

function Merge-Tags {
    param(
        [string[]]$ManualTags,
        [string]$FlavorTag,
        [hashtable]$GeoInfo
    )
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($tag in $ManualTags) {
        if ($tag) {
            foreach ($piece in ($tag -split ',')) {
                $clean = $piece.Trim()
                if ($clean) { $list.Add($clean) }
            }
        }
    }
    $list.Add('windows')
    if ($FlavorTag) { $list.Add($FlavorTag) }
    if ($GeoInfo.country_code) { $list.Add($GeoInfo.country_code.ToLower()) }
    if ($GeoInfo.location_label) { $list.Add($GeoInfo.location_label) }

    $seen = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($item in $list) {
        if (-not $seen.ContainsKey($item)) {
            $seen[$item] = $true
            $out.Add($item)
        }
    }
    return @($out)
}

$osInfo = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
$diskSize = [math]::Round((($disk | Measure-Object -Property Size -Sum).Sum / 1GB), 2)
$memTotalMb = [math]::Round($osInfo.TotalVisibleMemorySize / 1024, 0)
$geo = Get-GeoInfo
$flavorTag = Get-SystemFlavorTag -Caption $osInfo.Caption
$mergedTags = Merge-Tags -ManualTags $Tags -FlavorTag $flavorTag -GeoInfo $geo
$identityBase = [ordered]@{
    agent_id = $AgentId
    hostname = $env:COMPUTERNAME
    os_type = 'windows'
    os_version = $osInfo.Caption
    ip_addresses = @(Get-IpAddresses)
    cpu_model = $cpu.Name.Trim()
    cpu_cores = [int]$cpu.NumberOfLogicalProcessors
    memory_total_mb = [int]$memTotalMb
    disk_total_gb = $diskSize
    docker_version = Get-DockerVersion
    region = $(if ($Region) { $Region } else { $geo.country_code })
    country_name = $geo.country_name
    country_name_zh = $geo.country_name_zh
    isp = $(if ($ISP) { $ISP } else { $geo.isp_name })
    public_ip = $geo.public_ip
    country_code = $geo.country_code
    region_name = $geo.region_name
    region_name_zh = $geo.region_name_zh
    city_name = $geo.city_name
    city_name_zh = $geo.city_name_zh
    location_label = $geo.location_label
    location_label_zh = $geo.location_label_zh
    geo_source = $geo.geo_source
    tags = $mergedTags
}

$lastNet = Get-NetworkSnapshot
Write-Host "[$(Get-Date -Format s)] Windows agent started -> $ServerUrl (interval ${IntervalSeconds}s)"

while ($true) {
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem
        $cpuCounter = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
        $diskNow = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        $diskUsedGb = [math]::Round(((($diskNow | Measure-Object -Property Size -Sum).Sum - ($diskNow | Measure-Object -Property FreeSpace -Sum).Sum) / 1GB), 2)
        $diskTotalGb = [math]::Round((($diskNow | Measure-Object -Property Size -Sum).Sum / 1GB), 2)
        $memFreeMb = [math]::Round($osInfo.FreePhysicalMemory / 1024, 2)
        $memUsedMb = [math]::Round($memTotalMb - $memFreeMb, 2)
        $memPercent = if ($memTotalMb -gt 0) { [math]::Round(($memUsedMb / $memTotalMb) * 100, 2) } else { 0 }
        $diskPercent = if ($diskTotalGb -gt 0) { [math]::Round(($diskUsedGb / $diskTotalGb) * 100, 2) } else { 0 }
        $procCount = (Get-Process | Measure-Object).Count
        $docker = Get-DockerStats

        $netNow = Get-NetworkSnapshot
        $elapsed = ($netNow.ts - $lastNet.ts).TotalSeconds
        if ($elapsed -le 0) { $elapsed = 1 }
        $rxMbps = [math]::Round((($netNow.rx - $lastNet.rx) * 8 / 1MB) / $elapsed, 2)
        $txMbps = [math]::Round((($netNow.tx - $lastNet.tx) * 8 / 1MB) / $elapsed, 2)
        $lastNet = $netNow

        $identity = [ordered]@{}
        foreach ($entry in $identityBase.GetEnumerator()) {
            $identity[$entry.Key] = $entry.Value
        }
        $identity.os_version = $osInfo.Caption
        $identity.ip_addresses = @(Get-IpAddresses)
        $identity.uptime_seconds = (Get-UptimeSeconds)

        $payload = [ordered]@{
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            identity = $identity
            metrics = [ordered]@{
                cpu_percent = [math]::Round($cpuCounter, 2)
                memory_used_mb = $memUsedMb
                memory_total_mb = [double]$memTotalMb
                memory_percent = $memPercent
                disk_used_gb = $diskUsedGb
                disk_total_gb = $diskTotalGb
                disk_percent = $diskPercent
                load_1 = $null
                load_5 = $null
                load_15 = $null
                process_count = $procCount
                network_rx_mbps = $rxMbps
                network_tx_mbps = $txMbps
                docker_running = $docker.docker_running
                docker_containers_running = $docker.docker_containers_running
                docker_containers_total = $docker.docker_containers_total
            }
        }

        $headers = @{ Authorization = "Bearer $Token" }
        Invoke-RestMethod -Method Post -Uri $ServerUrl -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ($payload | ConvertTo-Json -Depth 8) | Out-Null
        Write-Host "[$(Get-Date -Format s)] Reported CPU=$($payload.metrics.cpu_percent)% MEM=$memPercent% DISK=$diskPercent% RX=${rxMbps}Mbps TX=${txMbps}Mbps"
    }
    catch {
        Write-Warning "Report failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
