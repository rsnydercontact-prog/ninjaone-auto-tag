<#
    TAG DEVICES BY SUBNET (location tagging)
    NinjaOne automation script. Run As: System.

    Reads the device's IPv4 addresses, finds the subnet they belong to in the
    table below, and applies that subnet's tag. When a device moves to another
    site, the old location tag is removed and the new one applied, so run it
    on a schedule.

    BEFORE YOU RUN IT
    1. Create every tag in the table under Administration > Devices > Tags.
       Set-NinjaTag cannot create tags.
    2. Run it from the Automation library, a policy, or a scheduled task.
       The tag cmdlets refuse to run from a normal PowerShell window, RDP or SSH.

    HOW A MATCH IS CHOSEN
    Every IPv4 address on the device is checked against every subnet. The most
    specific match wins (a /27 beats a /23 beats a /16), so you can list a
    small subnet inside a bigger one. Order in the table does not matter.

    Exit codes: 0 = success or no match, 1 = tag could not be applied.
#>

# --- EDIT THIS ---------------------------------------------------------------
# subnet (CIDR)      =  tag to apply
# Several subnets can share one tag.
$subnetTags = @{
    '10.1.20.0/22'     = 'Main Office'
    '10.1.106.0/24'    = 'Houston'
    '10.1.110.0/24'    = 'Dallas'
    '10.1.120.0/23'    = 'Denver'
    '10.1.120.64/27'   = 'Denver - Lab'      # more specific, wins over 10.1.120.0/23
    '172.16.0.0/16'    = 'VPN'
    '192.168.0.0/16'   = 'Remote / Home'
}

# Tag for devices that match none of the subnets. Leave '' to do nothing.
# When set, old location tags are also removed from unmatched devices.
$noMatchTag = ''
# -----------------------------------------------------------------------------


function ConvertTo-UInt32 {
    param([string]$Ip)
    # Strip leading zeros first: .NET reads 10.1.070.0 as octal otherwise.
    $clean = ($Ip.Split('.') | ForEach-Object { [int]$_ }) -join '.'
    $bytes = ([System.Net.IPAddress]::Parse($clean)).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Test-IPInSubnet {
    param([string]$Ip, [string]$Cidr)
    $network, $prefix = $Cidr.Split('/')
    $prefix = [int]$prefix
    if ($prefix -eq 0) { return $true }
    # Build the mask in 64-bit and trim to 32, so no prefix length overflows.
    $mask = [uint32](([uint64]4294967295 -shl (32 - $prefix)) -band [uint64]4294967295)
    return ((ConvertTo-UInt32 $Ip) -band $mask) -eq ((ConvertTo-UInt32 $network) -band $mask)
}

function Invoke-TagCmd {
    # The tag cmdlets report through output and errors inconsistently.
    # A missing tag prints a message and does NOT throw. Capture everything.
    param([scriptblock]$Command)
    return (& $Command 2>&1 | Out-String).Trim()
}


# Check the table before touching anything.
foreach ($cidr in $subnetTags.Keys) {
    $ok = $cidr -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})$' -and
          [int]$Matches[1] -le 255 -and [int]$Matches[2] -le 255 -and
          [int]$Matches[3] -le 255 -and [int]$Matches[4] -le 255 -and [int]$Matches[5] -le 32
    if (-not $ok) { Write-Output "Bad subnet in the table: '$cidr'. Use the form 10.1.20.0/24."; exit 1 }
}

$ipAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
    $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown'
} | ForEach-Object { $_.IPAddress })

Write-Output "Device      : $env:COMPUTERNAME"
Write-Output "IP addresses: $($ipAddresses -join ', ')"

# Most specific match across every address on the device.
$best = $null
foreach ($ip in $ipAddresses) {
    foreach ($cidr in $subnetTags.Keys) {
        if (-not (Test-IPInSubnet -Ip $ip -Cidr $cidr)) { continue }
        $prefix = [int]$cidr.Split('/')[1]
        if (-not $best -or $prefix -gt $best.Prefix) {
            $best = [pscustomobject]@{ Ip = $ip; Cidr = $cidr; Prefix = $prefix; Tag = $subnetTags[$cidr] }
        }
    }
}

if ($best) {
    $wanted = $best.Tag
    Write-Output "Match       : $($best.Ip) is in $($best.Cidr) -> $wanted"
}
elseif ($noMatchTag) {
    $wanted = $noMatchTag
    Write-Output "Match       : none -> $wanted"
}
else {
    Write-Output "Match       : none. No subnet in the table covers this device. Nothing changed."
    exit 0
}

# Every tag this script manages. Only these are ever removed.
$managedTags = @($subnetTags.Values) + @($noMatchTag) | Where-Object { $_ } | Select-Object -Unique

$current = @(Get-NinjaTag 2>$null | Where-Object { $_ })
Write-Output "Current tags: $(if ($current) { $current -join ', ' } else { '(none)' })"
Write-Output ""

foreach ($tag in $current) {
    if ($managedTags -contains $tag -and $tag -ne $wanted) {
        $out = Invoke-TagCmd { Remove-NinjaTag -Name $tag }
        if ($out) { Write-Output "WARNING  could not remove old location tag '$tag': $out" }
        else      { Write-Output "removed  $tag  (old location)" }
    }
}

if ($current -contains $wanted) {
    Write-Output "ok       $wanted  (already applied)"
    exit 0
}

$out = Invoke-TagCmd { Set-NinjaTag -Name $wanted }
if ($out -match 'already assigned') {
    Write-Output "ok       $wanted  (already applied)"
}
elseif ($out -match 'No tag with this name found') {
    Write-Output "FAILED   $wanted  - create this tag in NinjaOne first"
    exit 1
}
elseif ($out) {
    Write-Output "FAILED   $wanted  - $out"
    exit 1
}
else {
    Write-Output "tagged   $wanted"
}

exit 0
