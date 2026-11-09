<#
    TAG DEVICES BY HOSTNAME (or Active Directory OU)
    NinjaOne automation script. Run As: System.

    Matches the device's hostname against a table of patterns and applies a
    tag for every pattern that matches.

    BEFORE YOU RUN IT
    1. Create every tag in the table under Administration > Devices > Tags.
       Set-NinjaTag cannot create tags.
    2. Run it from the Automation library, a policy, or a scheduled task.
       The tag cmdlets refuse to run from a normal PowerShell window, RDP or SSH.

    TO MATCH ON ACTIVE DIRECTORY OU INSTEAD OF HOSTNAME
    Set $MatchOn = 'OU'. The lookup needs no RSAT and no credentials: running as
    SYSTEM on a domain-joined device, the computer account can read the
    directory itself.

    Exit codes: 0 = success, 1 = one or more tags failed to apply.
#>

# --- EDIT THIS ---------------------------------------------------------------
# 'Hostname' or 'OU'
$MatchOn = 'Hostname'

# pattern to match  =  tag to apply
# Wildcards: * = any characters, ? = one character. Case insensitive.
#   'APP*'   hostname starts with APP
#   '*SQL*'  hostname contains SQL
#   '*-LT'   hostname ends with -LT
$rules = [ordered]@{
    'APP*'                = 'App-Server'
    '*SQL*'               = 'SQL-Server'
    '*-LT'                = 'Laptop'
    # OU examples, used when $MatchOn = 'OU':
    # '*OU=Finance*'      = 'Finance'
    # '*OU=Kiosks*'       = 'Kiosk'
}
# -----------------------------------------------------------------------------


function Set-TagChecked {
    # Set-NinjaTag reports three different ways: silence on success, a
    # Write-Error when the tag is already on the device, and plain output
    # (no error, exit code still 0) when the tag does not exist. Capture all
    # of it and sort it out here.
    param([string]$Tag)

    $out = (Set-NinjaTag -Name $Tag 2>&1 | Out-String).Trim()

    if ($out -match 'already assigned')            { return "ok      $Tag  (already applied)" }
    if ($out -match 'No tag with this name found') { return "FAILED  $Tag  - create this tag in NinjaOne first" }
    if ($out -ne '')                               { return "FAILED  $Tag  - $out" }
    return "tagged  $Tag"
}


if ($MatchOn -eq 'OU') {
    try {
        $dn    = ([ADSISearcher]"(sAMAccountName=$env:COMPUTERNAME`$)").FindOne().Properties['distinguishedname'][0]
        $value = $dn -replace '^CN=[^,]+,', ''    # drop the computer name, keep the OU path
    }
    catch {
        Write-Output "Could not read this computer's OU from Active Directory: $_"
        Write-Output "Is the device domain-joined and able to reach a domain controller?"
        exit 1
    }
}
else {
    $value = $env:COMPUTERNAME
}

Write-Output "Device  : $env:COMPUTERNAME"
Write-Output "Matching: $value"
Write-Output ""

$matched = 0
$failed  = 0

foreach ($pattern in $rules.Keys) {
    if ($value -notlike $pattern) { continue }
    $matched++
    $line = Set-TagChecked -Tag $rules[$pattern]
    Write-Output $line
    if ($line -like 'FAILED*') { $failed++ }
}

Write-Output ""
if ($matched -eq 0) {
    Write-Output "No rule matched. Nothing to tag."
    exit 0
}
if ($failed -gt 0) {
    Write-Output "Finished with $failed failure(s)."
    exit 1
}
Write-Output "Done."
exit 0
