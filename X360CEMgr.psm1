
# X360CEMgr.psm1 - Playnite PowerShell Script Extension (v1.0.0)

$global:ExtId = "X360CE_Manager_Rebirth_PS"

function Get-DataPath {
    $base = Join-Path $env:AppData "Playnite\ExtensionsData\$($global:ExtId)"
    if (-not (Test-Path $base)) { New-Item -ItemType Directory -Force -Path $base | Out-Null }
    return $base
}

$global:SettingsPath = Join-Path (Get-DataPath) "settings.json"
$global:StatePath    = Join-Path (Get-DataPath) "runstate.json"

# ---------- Persistence ----------
function Load-Settings {
    if (Test-Path $global:SettingsPath) {
        try { return Get-Content $global:SettingsPath -Raw | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{
        X360CEPath    = ""
        AssignedGames = @()   # list of Game.Id strings
    }
}

function Save-Settings($s) {
    $s | ConvertTo-Json -Depth 5 | Set-Content -Path $global:SettingsPath -Encoding UTF8
}

function To-Hashtable($obj) {
    if ($null -eq $obj) { return @{} }
    if ($obj -is [hashtable]) { return $obj }
    $ht = @{}
    $props = $obj.PSObject.Properties
    foreach ($p in $props) { $ht[$p.Name] = $p.Value }
    return $ht
}

function Load-State {
    if (Test-Path $global:StatePath) {
        try {
            $obj = Get-Content $global:StatePath -Raw | ConvertFrom-Json
            return To-Hashtable $obj
        } catch { }
    }
    return @{}
}

function Save-State($st) {
    # Ensure dictionary with string keys only
    $safe = @{}
    foreach ($k in $st.Keys) {
        $safe["$k"] = $st[$k]
    }
    ($safe | ConvertTo-Json -Depth 5) | Set-Content -Path $global:StatePath -Encoding UTF8
}

$global:Settings = Load-Settings
$global:RunState = Load-State

# ---------- Helpers ----------
function Ensure-X360CEPath {
    if (![string]::IsNullOrWhiteSpace($global:Settings.X360CEPath) -and (Test-Path $global:Settings.X360CEPath)) { return $true }
    $picked = $PlayniteApi.Dialogs.SelectFile("X360CE executable|x360ce*.exe|Executable|*.exe|All files|*.*")
    if (-not [string]::IsNullOrWhiteSpace($picked)) {
        $global:Settings.X360CEPath = $picked
        Save-Settings $global:Settings
        return $true
    }
    $PlayniteApi.Dialogs.ShowErrorMessage("X360CE path is not set. Use 'Extensions → X360CE Manager → Set X360CE Path...' to configure.")
    return $false
}

function Is-Assigned($gameId) {
    return $global:Settings.AssignedGames -contains $gameId
}

function Assign-Games($games) {
    $added = 0
    foreach ($g in $games) {
        if (-not (Is-Assigned $g.Id)) {
            $global:Settings.AssignedGames += $g.Id
            $added++
        }
    }
    if ($added -gt 0) { Save-Settings $global:Settings }
    return $added
}

function Unassign-Games($games) {
    $idsToRemove = @($games | ForEach-Object { $_.Id })
    $global:Settings.AssignedGames = @($global:Settings.AssignedGames | Where-Object { $idsToRemove -notcontains $_ })
    Save-Settings $global:Settings
}

# ---------- Menus ----------
function GetGameMenuItems {
    param($getGameMenuItemsArgs)
    $items = @()
    $section = "X360CE Manager Rebirth"

    $enable = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $enable.Description   = "Enable for selected game(s)"
    $enable.FunctionName  = "InvokeEnableForGames"
    $enable.MenuSection   = $section
    $items += $enable

    $disable = New-Object Playnite.SDK.Plugins.ScriptGameMenuItem
    $disable.Description  = "Disable for selected game(s)"
    $disable.FunctionName = "InvokeDisableForGames"
    $disable.MenuSection  = $section
    $items += $disable

    return $items
}

function GetMainMenuItems {
    param($getMainMenuItemsArgs)
    $items = @()

    $listMain = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $listMain.Description  = "List games enabled for X360CE"
    $listMain.FunctionName = "InvokeListEnabledGames"
    $listMain.MenuSection = "@X360CE Manager Rebirth"
        $items += $listMain

    $setPathMain = New-Object Playnite.SDK.Plugins.ScriptMainMenuItem
    $setPathMain.Description  = "Set X360CE Path..."
    $setPathMain.FunctionName = "InvokeSetPath"
    $setPathMain.MenuSection = "@X360CE Manager Rebirth"
        $items += $setPathMain

    return $items
}

function InvokeEnableForGames {
    param($scriptGameMenuItemActionArgs)
    Assign-Games $scriptGameMenuItemActionArgs.Games | Out-Null
    $PlayniteApi.Dialogs.ShowMessage("Assigned X360CE to $($scriptGameMenuItemActionArgs.Games.Count) game(s).")
}

function InvokeListEnabledGames {
    param($scriptGameMenuItemActionArgs)

    if (-not $global:Settings.AssignedGames -or $global:Settings.AssignedGames.Count -eq 0) {
        $PlayniteApi.Dialogs.ShowMessage("No games have X360CE enabled.", "X360CE Manager Rebirth")
        return
    }

    $names = @()
    foreach ($g in $PlayniteApi.Database.Games) {
        if ($global:Settings.AssignedGames -contains $g.Id) {
            $names += $g.Name
        }
    }

    if ($names.Count -eq 0) {
        $PlayniteApi.Dialogs.ShowMessage("No games found for the saved IDs.", "X360CE Manager Rebirth")
        return
    }

    $names = $names | Sort-Object
    $PlayniteApi.Dialogs.ShowMessage(($names -join "`n"), "Games with X360CE Enabled")
}



function InvokeDisableForGames {
    param($scriptGameMenuItemActionArgs)
    Unassign-Games $scriptGameMenuItemActionArgs.Games
    $PlayniteApi.Dialogs.ShowMessage("Removed X360CE from $($scriptGameMenuItemActionArgs.Games.Count) game(s).")
}

function InvokeSetPath {
    param($args)
    $pick = $PlayniteApi.Dialogs.SelectFile("X360CE executable|x360ce*.exe|Executable|*.exe|All files|*.*")
    if (-not [string]::IsNullOrWhiteSpace($pick)) {
        $global:Settings.X360CEPath = $pick
        Save-Settings $global:Settings
        $PlayniteApi.Dialogs.ShowMessage("Saved X360CE path:`n$pick")
    }
}

function InvokeShowPath {
    param($args)
    $p = $global:Settings.X360CEPath
    if ([string]::IsNullOrWhiteSpace($p)) { $p = "(not set)" }
    $PlayniteApi.Dialogs.ShowMessage("Current X360CE path:`n$($p)")
}

# ---------- Event Hooks ----------
function OnGameStarting {
    param($args)
    if (-not (Is-Assigned $args.Game.Id)) { return }
    if (-not (Ensure-X360CEPath)) { return }

    $workingDir = $args.Game.InstallDirectory
    if ([string]::IsNullOrWhiteSpace($workingDir) -or -not (Test-Path $workingDir)) {
        $PlayniteApi.Dialogs.ShowErrorMessage("X360CE Manager: game has no valid InstallDirectory. Skipping.")
        return
    }

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $global:Settings.X360CEPath
        $startInfo.WorkingDirectory = $workingDir
        $startInfo.UseShellExecute = $true
        $startInfo.WindowStyle = 'Hidden'

        $proc = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -ne $proc) {
            $key = $args.Game.Id.ToString()     # ensure string key
            $global:RunState[$key] = @{ Pid = $proc.Id }
            Save-State $global:RunState
        }
    } catch {
        $PlayniteApi.Dialogs.ShowErrorMessage("Failed to start X360CE: $($_.Exception.Message)")
    }
}

function OnGameStopped {
    param($args)
    $key = $args.Game.Id.ToString()
    $state = $global:RunState[$key]
    if ($null -ne $state -and $state.Pid) {
        try {
            Stop-Process -Id $state.Pid -Force -ErrorAction SilentlyContinue
        } catch { }
        $global:RunState.Remove($key) | Out-Null
        Save-State $global:RunState
        return
    }

    # Fallback: PowerShell 5.1 friendly lookup of processes via WMI
    try {
        $gameDir = $args.Game.InstallDirectory
        if (-not [string]::IsNullOrWhiteSpace($gameDir)) {
            $procs = Get-WmiObject Win32_Process -Filter "Name LIKE 'x360ce%'" -ErrorAction SilentlyContinue
            foreach ($p in $procs) {
                if ($p.ExecutablePath -and (Split-Path $p.ExecutablePath -Parent) -ieq $gameDir) {
                    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch { }
}

Export-ModuleMember -Function *
