# Invoked with a fixed operation and a base64 JSON payload by network_setup.py.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload64)) | ConvertFrom-Json
$pcIP='192.168.137.1'; $boardIP='192.168.137.2'; $boardIPs=@('192.168.137.2','192.168.137.3','192.168.137.4'); $udpPorts=@('16001','16002','16003')
function Netsh([string[]]$Arguments) {
    $output= & "$env:SystemRoot\System32\netsh.exe" @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {throw ($output -join "`n")}
    return ($output -join "`n")
}
function Coexistence([int]$Index) {
    $text=Netsh -Arguments @('interface','ipv4','show','interfaces',"interface=$Index",'level=verbose')
    foreach ($line in ($text -split "`n")) {
        if ($line -match 'DHCP.*(?:coexistence|共存|并存|共用).*[:：]\s*(.*?)\s*$') {
            switch -Regex ($Matches[1].Trim()) {
                '^(enabled|已启用|启用|已啟用|啟用)$' {return $true}
                '^(disabled|已禁用|禁用|已停用|停用)$' {return $false}
            }
        }
    }
    return $null
}
function SelectedAdapter {
    if ([string]$p.guid -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {throw '无效网卡标识。'}
    $found=@(Get-NetAdapter -Physical | Where-Object {($_.InterfaceGuid.ToString().Trim('{}')) -ieq $p.guid})
    if ($found.Count -ne 1 -or $found[0].ifIndex -ne [int]$p.index) {throw '网卡已变化，请重新扫描。'}
    return $found[0]
}
function PortKey($Values) {
    $items=@()
    foreach ($v in ((@($Values) -join ',') -split ',')) {
        if ($v -notmatch '^(1600[1-3])(?:-(1600[1-3]))?$') {return '!'}
        $first=[int]$Matches[1];$last=$first;if($Matches[2]){$last=[int]$Matches[2]}
        if($last -lt $first){return '!'}
        for($n=$first;$n -le $last;$n++){$items+="$n"}
    }
    return (($items | Sort-Object -Unique) -join ',')
}
function AddressKey($Values) {
    $items=@()
    foreach ($v in ((@($Values) -join ',') -split ',')) {
        $v=$v -replace '/32$',''
        if($v -notmatch '^192\.168\.137\.([234])(?:-192\.168\.137\.([234]))?$'){return '!'}
        $first=[int]$Matches[1];$last=$first;if($Matches[2]){$last=[int]$Matches[2]}
        if($last -lt $first){return '!'}
        for($n=$first;$n -le $last;$n++){$items+="192.168.137.$n"}
    }
    return (($items | Sort-Object -Unique) -join ',')
}
function RuleName {
    if ([string]$p.name -notmatch '^PCBAOI\.MultiCam\.Demo\.[0-9a-f]{32}$') {throw '无效规则标识。'}
    return [string]$p.name
}
try {
    $value=$null
    switch ($p.operation) {
        inventory {
            $ips=@(Get-NetIPAddress -AddressFamily IPv4)
            $interfaces=@(Get-NetIPInterface -AddressFamily IPv4)
            $dns=@(Get-DnsClientServerAddress -AddressFamily IPv4)
            $defaults=@(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
            $adapters=@(foreach ($a in @(Get-NetAdapter -Physical)) {
                $i=$a.ifIndex;$ipif=$interfaces | Where-Object InterfaceIndex -eq $i | Select-Object -First 1
                [ordered]@{guid=$a.InterfaceGuid.ToString().Trim('{}');index=[int]$i;name=$a.Name;description=$a.InterfaceDescription;
                    up=($a.Status -eq 'Up');wireless=([int]$a.NdisPhysicalMedium -in @(1,9));dhcp=([int]$ipif.Dhcp -eq 1);
                    coexistence=$(if ($a.Status -eq 'Up') {Coexistence $i} else {$null});
                    addresses=@($ips | Where-Object InterfaceIndex -eq $i | ForEach-Object {@{ip=$_.IPAddress;prefix=[int]$_.PrefixLength;state=$_.AddressState.ToString();origin=$_.PrefixOrigin.ToString()}});
                    gateways=@($defaults | Where-Object InterfaceIndex -eq $i | Select-Object -ExpandProperty NextHop | Sort-Object -Unique);
                    dns=@($dns | Where-Object InterfaceIndex -eq $i | ForEach-Object {$_.ServerAddresses})}
            })
            $wlan=(& "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>&1 | Out-String)
            $value=@{adapters=$adapters;wlan_text=$wlan;all_addresses=@($ips | ForEach-Object {@{ip=$_.IPAddress;prefix=[int]$_.PrefixLength;index=[int]$_.InterfaceIndex}});
                ports=@(Get-NetUDPEndpoint -LocalPort $udpPorts -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)}
        }
        coexistence {
            $a=SelectedAdapter;$setting=if ($p.enabled) {'enabled'} else {'disabled'}
            $null=Netsh -Arguments @('interface','ipv4','set','interface',"interface=$($a.ifIndex)","dhcpstaticipcoexistence=$setting",'store=active')
        }
        add_ip {
            $a=SelectedAdapter
            if ($a.Status -ne 'Up') {throw '网卡已断开。'}
            $existing=@(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $pcIP -ErrorAction SilentlyContinue)
            if ($existing.Count -gt 0) {$value=@{added=$false}}
            else {
                $null=Netsh -Arguments @('interface','ipv4','add','address',"name=$($a.ifIndex)","address=$pcIP",'mask=255.255.255.0','store=active','skipassource=true')
                $value=@{added=$true}
            }
        }
        remove_ip {
            $a=SelectedAdapter
            if (@(Get-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $pcIP -ErrorAction SilentlyContinue).Count -gt 0) {
                Remove-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $pcIP -Confirm:$false
            }
        }
        rule_get {
            $a=SelectedAdapter;$name=RuleName
            $r=Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
            $value=$false
            if ($r) {
                $address=$r | Get-NetFirewallAddressFilter;$port=$r | Get-NetFirewallPortFilter
                $program=$r | Get-NetFirewallApplicationFilter;$iface=$r | Get-NetFirewallInterfaceFilter
                $value=($r.Enabled.ToString() -eq 'True' -and $r.Direction.ToString() -eq 'Inbound' -and $r.Action.ToString() -eq 'Allow' -and
                    $port.Protocol -in @('UDP','17') -and (PortKey $port.LocalPort) -eq (PortKey $udpPorts) -and $address.LocalAddress -eq $pcIP -and
                    (AddressKey $address.RemoteAddress) -eq (AddressKey $boardIPs) -and $program.Program -eq $p.program -and $iface.InterfaceAlias -eq $a.Name)
            }
        }
        rule_add {
            $a=SelectedAdapter;$name=RuleName
            if (-not (Test-Path -LiteralPath $p.program -PathType Leaf)) {throw '接收程序路径无效。'}
            if (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue) {
                # This UUID name comes only from our own journal; never replace broad existing rules.
                Remove-NetFirewallRule -Name $name
            }
            $null=New-NetFirewallRule -Name $name -DisplayName 'PCB AOI 三通道接收' -Group 'PCB AOI MultiCam Demo' -Direction Inbound -Action Allow -Enabled True -Protocol UDP -LocalPort $udpPorts -LocalAddress $pcIP -RemoteAddress $boardIPs -Program $p.program -InterfaceAlias $a.Name -Profile Any
        }
        rule_remove {
            $null=SelectedAdapter;$name=RuleName
            Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        }
        dhcp_restore {
            $a=SelectedAdapter
            Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Dhcp Enabled
        }
        health {
            $route=@(Find-NetRoute -RemoteIPAddress $boardIP -ErrorAction SilentlyContinue | Select-Object -ExpandProperty InterfaceIndex -Unique)
            $ping=[Net.NetworkInformation.Ping]::new()
            try {$reply=$ping.Send($boardIP,800);$reachable=($reply.Status -eq [Net.NetworkInformation.IPStatus]::Success)} catch {$reachable=$false} finally {$ping.Dispose()}
            $value=@{route_ok=($route.Count -eq 1 -and $route[0] -eq [int]$p.index);ping=$reachable}
        }
        default {throw '不支持的网络操作。'}
    }
    @{ok=$true;value=$value} | ConvertTo-Json -Depth 10 -Compress
} catch {
    @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Depth 4 -Compress
    exit 1
}
