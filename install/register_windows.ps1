#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers IP Change Notifier in Windows Task Scheduler.

.DESCRIPTION
    Creates a single scheduled task with THREE triggers so the notifier
    fires reliably even when the PC was in sleep mode:

      1. At user logon          — covers fresh boot / user switch
      2. On wake from sleep     — covers sleep/hibernate resume (30-sec delay
                                   lets the network adapter come back online)
      3. On network connected   — covers late-joining Wi-Fi / VPN (10-sec delay)

.NOTES
    Run from an elevated (Administrator) PowerShell prompt, or let
    register_windows.bat handle elevation automatically.

    To remove the task later:
        schtasks /Delete /TN "IPChangeNotifier" /F
#>

$ErrorActionPreference = 'Stop'

$TaskName   = 'IPChangeNotifier'
$ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'ip_notifier.py'

# --- Verify script exists ---
if (-not (Test-Path $ScriptPath)) {
    Write-Error "ip_notifier.py not found at: $ScriptPath"
    exit 1
}

# --- Locate Python executable (use pythonw.exe for headless / no-console execution) ---
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Error "Python not found in PATH. Install Python and ensure it is on PATH."
    exit 1
}
# pythonw.exe lives beside python.exe and suppresses the console window entirely
$PythonExe = Join-Path (Split-Path $pythonCmd.Source) 'pythonw.exe'
if (-not (Test-Path $PythonExe)) {
    Write-Warning "pythonw.exe not found next to python.exe; falling back to python.exe (console window will appear)."
    $PythonExe = $pythonCmd.Source
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "  Registering '$TaskName' in Task Scheduler" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "  Python : $PythonExe"
Write-Host "  Script : $ScriptPath"
Write-Host ''

# ---------------------------------------------------------------------------
# Action
# ---------------------------------------------------------------------------
$action = New-ScheduledTaskAction -Execute $PythonExe -Argument "`"$ScriptPath`""

# ---------------------------------------------------------------------------
# Trigger 1 — At user logon
# ---------------------------------------------------------------------------
$t1 = New-ScheduledTaskTrigger -AtLogOn

# ---------------------------------------------------------------------------
# Trigger 2 — Wake from sleep / hibernate
#   Event: System log, source Power-Troubleshooter, Event ID 1
#   30-second delay gives the network adapter time to reconnect after waking.
# ---------------------------------------------------------------------------
$evtClass = Get-CimClass -Namespace 'root/Microsoft/Windows/TaskScheduler' `
                         -ClassName 'MSFT_TaskEventTrigger'

$t2 = New-CimInstance -CimClass $evtClass -ClientOnly
$t2.Subscription = @'
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">
      *[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]
    </Select>
  </Query>
</QueryList>
'@
$t2.Delay   = 'PT30S'   # ISO 8601 duration — 30 seconds
$t2.Enabled = $true

# ---------------------------------------------------------------------------
# Trigger 3 — Network profile connected
#   Event: NetworkProfile/Operational, Event ID 10000 (network connected)
#   10-second delay lets DHCP finish assigning the new IP.
# ---------------------------------------------------------------------------
$t3 = New-CimInstance -CimClass $evtClass -ClientOnly
$t3.Subscription = @'
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational">
    <Select Path="Microsoft-Windows-NetworkProfile/Operational">
      *[System[EventID=10000]]
    </Select>
  </Query>
</QueryList>
'@
$t3.Delay   = 'PT10S'   # ISO 8601 duration — 10 seconds
$t3.Enabled = $true

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances  IgnoreNew `
    -StartWhenAvailable `   # run as soon as possible if a trigger was missed
    -Hidden                 # suppress any UI / console window at the task level

# ---------------------------------------------------------------------------
# Principal — run as the current interactive user with highest privileges
# ---------------------------------------------------------------------------
$principal = New-ScheduledTaskPrincipal `
    -UserId    $env:USERNAME `
    -LogonType Interactive `
    -RunLevel  Highest

# ---------------------------------------------------------------------------
# Remove old task (if any) then register
# ---------------------------------------------------------------------------
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$task = Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $t1, $t2, $t3 `
    -Settings  $settings `
    -Principal $principal `
    -Force

if ($task) {
    Write-Host "[OK] Task '$TaskName' registered successfully." -ForegroundColor Green
    Write-Host ''
    Write-Host 'Triggers configured:'
    Write-Host '  1. At user logon'
    Write-Host '  2. On wake from sleep / hibernate  (30-second delay)'
    Write-Host '  3. On network profile connected    (10-second delay)'
    Write-Host ''
    Write-Host 'To verify in Task Scheduler: taskschd.msc'
    Write-Host "To remove the task: schtasks /Delete /TN `"$TaskName`" /F"
    Write-Host ''
} else {
    Write-Error "Task registration failed. Check Task Scheduler for details."
    exit 1
}
