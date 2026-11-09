# NinjaOne Auto-Tag

Two NinjaOne automation scripts that tag devices automatically.

| File | Tags a device by |
|---|---|
| `Tag-DevicesByHostname.ps1` | Its hostname, or its Active Directory OU |
| `Tag-DevicesBySubnet.ps1` | The IP subnet it is on (one location tag; swapped when the device moves) |

Both run on the endpoint as SYSTEM through the NinjaOne agent. No API credentials, nothing to install.

Tags can then drive dynamic policies, groups, saved searches, and automation targeting.

---

## Setup

### 1. Create the tags

**Administration → Devices → Tags.** Create every tag the script will apply, spelled exactly as in the script.

The scripts cannot create tags. If a tag is missing, the run fails with `FAILED <tag> - create this tag in NinjaOne first`.

### 2. Edit the table

Open the script and edit the block between the `EDIT THIS` lines.

**Hostname:**

```powershell
$MatchOn = 'Hostname'          # or 'OU'

$rules = [ordered]@{
    'APP*'   = 'App-Server'    # starts with APP
    '*SQL*'  = 'SQL-Server'    # contains SQL
    '*-LT'   = 'Laptop'        # ends with -LT
}
```

`*` matches any characters, `?` matches one. Matching is case insensitive. A device gets a tag for **every** rule it matches.

To match on Active Directory OU, set `$MatchOn = 'OU'` and write rules like `'*OU=Finance*' = 'Finance'`. This needs no RSAT and no credentials; the computer account reads its own OU.

**Subnet:**

```powershell
$subnetTags = @{
    '10.1.20.0/22'    = 'Main Office'
    '10.1.106.0/24'   = 'Houston'
    '10.1.120.0/23'   = 'Denver'
    '10.1.120.64/27'  = 'Denver - Lab'
    '192.168.0.0/16'  = 'Remote / Home'
}

$noMatchTag = ''               # optional tag for devices on no listed subnet
```

- Several subnets can share one tag.
- The most specific subnet wins, so a `/27` inside a `/23` works. Order in the table does not matter.
- Every IPv4 address on the device is checked (Wi-Fi, Ethernet, VPN). The most specific match across all of them wins.
- A device carries one location tag at a time. When it matches a different subnet, the old location tag is removed and the new one applied. Tags that are not in the table are never touched.
- A device on no listed subnet keeps whatever it has, unless `$noMatchTag` is set.

### 3. Add it to the Automation library

**Administration → Library → Automation → Add → New Script**

| Setting | Value |
|---|---|
| Language | PowerShell |
| Operating system | Windows |
| Run As | System |

Paste the script and save.

### 4. Test on one device

Run it on one device from the device page (**Run → Automation**). Check the output in the device's **Activities**, and confirm the tag appears on the device.

### 5. Schedule it

Add it as a **scheduled script** in the policy (or a scheduled task) so new devices get tagged, and devices that move get re-tagged. Daily is typical for subnet tagging; hostname tags only change when a device is renamed.

---

## Output

| Line | Meaning |
|---|---|
| `tagged  <tag>` | Tag applied |
| `ok  <tag> (already applied)` | Device already had it. Not an error |
| `removed  <tag> (old location)` | Subnet script: old location tag removed after a move |
| `FAILED  <tag> - create this tag in NinjaOne first` | Tag does not exist in NinjaOne |
| `No rule matched` / `Match: none` | Nothing in the table applies. Exits 0 |

Exit code `0` = success or nothing to do, `1` = a tag could not be applied (or the subnet table has a typo).

---

## Things to know

**The tag cmdlets only work inside an automation.** Run from a normal PowerShell window, RDP or SSH, `Set-NinjaTag` fails with "Access to tags is possible only from automation script". Run the script from NinjaOne.

**`Set-NinjaTag` does not throw on a missing tag.** It prints "No tag with this name found" and the exit code stays 0. Both scripts check the text, so a missing tag shows as `FAILED`.

**Re-applying a tag the device already has is an error**, not a no-op. Both scripts treat it as success, so scheduled re-runs don't report failures on devices that are already correct.

**Subnet tagging uses the device's own IP**, not its public IP. A remote device shows its home or hotspot address unless it is on the VPN; add a catch-all like `192.168.0.0/16` if you want those tagged.

---

## Related

To **move** devices into the right Organization and Location by subnet, rather than tag them, see [ninjaone-device-mover](https://github.com/rsnydercontact-prog/ninjaone-device-mover).
