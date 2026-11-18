# Exercises the setup's install logic in a temp folder. Never touches the real game folder.
param([string]$RealExe = 'E:\Steam\steamapps\common\Danganronpa 2 Goodbye Despair\DR2_us.exe')
$ErrorActionPreference = 'Stop'
$asm = [Reflection.Assembly]::LoadFile('F:\Update Alterrego\DR2Autosave\out\setup\DR2_Autosave_Setup.exe')
$I = $asm.GetType('DR2AutosaveSetup.Installer')
$ST = $asm.GetType('DR2AutosaveSetup.ModSettings')
function Call($name, [object[]]$a) {
    $plain = [object[]]@($a | ForEach-Object { $_.PSObject.BaseObject })
    try { return $I.GetMethod($name).Invoke($null, $plain) }
    catch [Reflection.TargetInvocationException] { throw $_.Exception.InnerException }
}
function Settings($m, $n, $b) { $s = [Activator]::CreateInstance($ST); $ST.GetField('IntervalMinutes').SetValue($s, $m); $ST.GetField('ShowNotification').SetValue($s, $n); $ST.GetField('KeepBackups').SetValue($s, $b); $s }
$script:fails = 0
function Check($label, $ok) { if ($ok) { "ok    $label" } else { "FAIL  $label"; $script:fails++ } }
function Refused($label, [scriptblock]$f, $text) {
    try { & $f; Check "$label (expected refusal)" $false }
    catch {
        $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException } # PowerShell wraps reflection errors
        Check $label ($e.GetType().Name -eq 'InstallerException' -and $e.Message -match $text)
    }
}
function NewGame { $d = Join-Path $root ([guid]::NewGuid()); New-Item -ItemType Directory $d | Out-Null; Copy-Item $RealExe "$d\DR2_us.exe"; $d }
function Names($d) { (Get-ChildItem $d -Force | ForEach-Object Name | Sort-Object) -join ',' }

$root = Join-Path $env:TEMP ("dr2setup_" + [guid]::NewGuid()); New-Item -ItemType Directory $root | Out-Null
try {
    $d = NewGame
    Check 'empty folder is Missing' ((Call CheckGame @("$root\nope")).ToString() -eq 'Missing')
    Check 'real exe is Supported' ((Call CheckGame @($d)).ToString() -eq 'Supported')

    $bad = Join-Path $root 'bad'; New-Item -ItemType Directory $bad | Out-Null
    Set-Content "$bad\DR2_us.exe" 'not a game'
    Check 'garbage exe is WrongVersion' ((Call CheckGame @($bad)).ToString() -eq 'WrongVersion')
    Refused 'wrong version is refused' { Call Install @($bad, (Settings 5 $true $true)) } 'not supported'
    Check 'refusal leaves folder clean' ((Names $bad) -eq 'DR2_us.exe')

    Call Install @($d, (Settings 15 $false $true)) | Out-Null
    Check 'install adds dll and ini only' ((Names $d) -eq 'd3dx9_43.dll,dr2_autosave.ini,DR2_us.exe')
    Check 'mod detected' (Call IsModInstalled @($d))
    $r = Call ReadSettings @($d)
    Check 'settings round trip' ($ST.GetField('IntervalMinutes').GetValue($r) -eq 15 -and -not $ST.GetField('ShowNotification').GetValue($r) -and $ST.GetField('KeepBackups').GetValue($r))
    Call Install @($d, (Settings 30 $true $false)) | Out-Null
    Check 'reinstall updates settings' ($ST.GetField('IntervalMinutes').GetValue((Call ReadSettings @($d))) -eq 30)
    Check 'reinstall leaves no temp files' ((Names $d) -eq 'd3dx9_43.dll,dr2_autosave.ini,DR2_us.exe')

    Set-Content "$d\dr2_autosave.ini" "IntervalMinutes=abc`r`nKeepBackups`r`nIntervalMinutes=7"
    Check 'bad ini falls back to defaults' ($ST.GetField('IntervalMinutes').GetValue((Call ReadSettings @($d))) -eq 5)

    Set-Content "$d\dr2_autosave.log" 'x'
    Call Uninstall @($d) | Out-Null
    Check 'uninstall restores clean folder' ((Names $d) -eq 'DR2_us.exe')

    $d = NewGame; Set-Content "$d\d3dx9_43.dll" 'someone else'
    Call Install @($d, (Settings 5 $true $true)) | Out-Null
    Check 'foreign dll is kept aside' ((Get-Content "$d\d3dx9_43.dll.original") -eq 'someone else')
    Call Uninstall @($d) | Out-Null
    Check 'foreign dll is restored' ((Get-Content "$d\d3dx9_43.dll") -eq 'someone else' -and -not (Test-Path "$d\d3dx9_43.dll.original"))

    Set-Content "$d\d3dx9_43.dll.original" 'older'
    Refused 'two foreign dlls are refused' { Call Install @($d, (Settings 5 $true $true)) } 'Another mod'
    Check 'refusal keeps both files' ((Get-Content "$d\d3dx9_43.dll") -eq 'someone else' -and (Get-Content "$d\d3dx9_43.dll.original") -eq 'older')

    $d = NewGame; Call Install @($d, (Settings 5 $true $true)) | Out-Null
    $lock = [IO.File]::Open("$d\d3dx9_43.dll", 'Open', 'Read', 'None')
    Refused 'locked dll reports an error' { Call Install @($d, (Settings 10 $true $true)) } 'could not be changed|denied'
    $lock.Close()
    Check 'failed update leaves no temp file' (-not (Test-Path "$d\d3dx9_43.dll.new"))
    Check 'failed update keeps the mod' (Call IsModInstalled @($d))

    $d = NewGame; Set-Content "$d\d3dx9_43.dll" 'someone else'
    $lock = [IO.File]::Open("$d\d3dx9_43.dll", 'Open', 'Read', 'None')
    Refused 'locked foreign dll reports an error' { Call Install @($d, (Settings 5 $true $true)) } 'could not be changed|denied'
    $lock.Close()
    Check 'foreign dll survives a failed install' ((Get-Content "$d\d3dx9_43.dll") -eq 'someone else')

    function Entry($name, [byte[]]$data) { $n = [Text.Encoding]::ASCII.GetBytes($name); [BitConverter]::GetBytes($n.Length) + $n + [BitConverter]::GetBytes($data.Length) + $data }
    $end = [BitConverter]::GetBytes([uint32]3735928559)
    $auto = [Text.Encoding]::ASCII.GetBytes('DR2 Autosave....'); $mine = [Text.Encoding]::ASCII.GetBytes('Danganronpa 2...')
    $v = Join-Path $root 'saves'; New-Item -ItemType Directory $v | Out-Null
    [IO.File]::WriteAllBytes("$v\savedata.vfs", [byte[]]((Entry 'data0000.bin' $mine) + (Entry 'data0027.bin' $auto) + (Entry 'data0028.bin' $mine) + $end))
    Check 'counts only player saves in slots 28-30' ((Call PlayerSavesInAutosaveSlots @($v)) -eq 1)
    [IO.File]::WriteAllBytes("$v\savedata.vfs", [byte[]](255,255,255,1,2,3))
    Check 'corrupt save file does not crash' ((Call PlayerSavesInAutosaveSlots @($v)) -eq 0)
    [IO.File]::WriteAllBytes("$v\savedata.vfs", [byte[]]((Entry 'data0028.bin' $mine)[0..20]))
    Check 'truncated save file does not crash' ((Call PlayerSavesInAutosaveSlots @($v)) -eq 0)
}
finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
"failures: $script:fails"
exit $script:fails
