# Runs Open NPC's in-game tests in a Morrowind test copy (install them first: python tools/deploy.py <copy> --test).
# The copy shares Morrowind's own settings with the Steam game (resolution, controls, volume, in the registry), so they're
# backed up before the run, and put back exactly if the run changed them. With -Windowed the game runs in a window for the
# test, and the setting is put back afterwards the same way. The game is closed by its own process id.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [int]$TimeoutSeconds = 300,
    [switch]$Windowed,
    # (someone else starts the game, as a double-click does; this waits for it. A fullscreen game started from this
    # background shell never became the active window, lost its screen, and crashed rebuilding its graphics)
    [switch]$External,
    # A Windows shortcut to the copy's Morrowind.exe (start-in = the copy): opened through Explorer, as a double-click is.
    [string]$Shortcut,
    # How many times to start the game again when it crashes while loading its data (a random crash, not hers)
    [int]$Retries = 5,
    # Runs tools/standin_ai.js on 127.0.0.1:41799 for the run (her AI in the tests), and stops it after
    [switch]$StandIn
)

$standinProc = $null
if ($StandIn) {
    $js = Join-Path $PSScriptRoot 'standin_ai.js'
    $slog = Join-Path (Split-Path $Game -Parent) 'morrowind-work\standin_questions.jsonl'
    Remove-Item $slog -ErrorAction SilentlyContinue
    $standinProc = Start-Process -FilePath node -ArgumentList "`"$js`"", 41799, "`"$slog`"" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 1
    "stand-in AI started, PID $($standinProc.Id) (questions logged to $slog)"
}

$key = 'HKCU\Software\Classes\VirtualStore\MACHINE\SOFTWARE\WOW6432Node\Bethesda Softworks\Morrowind'
$psKey = 'HKCU:\Software\Classes\VirtualStore\MACHINE\SOFTWARE\WOW6432Node\Bethesda Softworks\Morrowind'
$backups = Join-Path (Split-Path $Game -Parent) 'morrowind-work\backups'
New-Item -ItemType Directory -Force $backups | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$before = Join-Path $backups "morrowind-settings-$stamp-before.reg"
$after = Join-Path $backups "morrowind-settings-$stamp-after.reg"
reg export $key $before /y | Out-Null

if ($Windowed) { Set-ItemProperty -Path $psKey -Name 'Fullscreen' -Value 0 -Type DWord }

$results = Join-Path $Game 'Data Files\MWSE\opennpc_test_results.txt'
$photoAsk = Join-Path $Game 'Data Files\MWSE\opennpc_photo.txt'
$photos = Join-Path (Split-Path $Game -Parent) 'morrowind-work\photos'
New-Item -ItemType Directory -Force $photos | Out-Null
Remove-Item $photoAsk -ErrorAction SilentlyContinue

# (a photo of the game's window, as it is on the screen)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class OpenNpcWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[OpenNpcWin]::SetProcessDPIAware() | Out-Null
function Save-Photo($proc, $path) {
    $proc.Refresh()
    $rect = New-Object OpenNpcWin+RECT
    [OpenNpcWin]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) | Out-Null
    $w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
    # (only the game's own picture: on this PC it draws its screen size in the window's top-left corner, and the rest of
    # the window shows whatever is behind it)
    # (a copy whose game file reads HKCU\Software\Bethesda Softworks\Morrowind has its own size there)
    $size = Get-ItemProperty -Path 'HKCU:\Software\Bethesda Softworks\Morrowind' -ErrorAction SilentlyContinue
    if (-not $size) { $size = Get-ItemProperty -Path $psKey -ErrorAction SilentlyContinue }
    if ($size -and $size.'Screen Width' -gt 0) { $w = [Math]::Min($w, [int]$size.'Screen Width'); $h = [Math]::Min($h, [int]$size.'Screen Height') }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
$mwseLog = Join-Path $Game 'MWSE.log'
$exe = Join-Path $Game 'Morrowind.exe'

function Restore-Settings {
    reg export $key $after /y | Out-Null
    $diff = Compare-Object (Get-Content $before) (Get-Content $after)
    if ($diff) {
        reg import $before 2>$null
        "settings changed during the run; put back from $before ($(@($diff).Count) lines)"
    } else { "settings unchanged" }
}

for ($attempt = 1; $attempt -le [Math]::Max(1, $Retries); $attempt++) {
    Remove-Item $results, $mwseLog, (Join-Path $Game 'ProgramFlow.txt') -ErrorAction SilentlyContinue   # (so an old log is never read as this start's)
    $dump = Join-Path $Game 'MWSE_MiniDump.dmp'
    if (Test-Path $dump) { Move-Item $dump (Join-Path $backups "crash-$stamp-$attempt-MWSE_MiniDump.dmp") -Force }
    $runningBefore = @(Get-Process -Name Morrowind -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    if ($Shortcut) {
        Start-Process -FilePath explorer.exe -ArgumentList "`"$Shortcut`""
        $tries = 60
    } elseif ($External) {
        "waiting for the game to be started from the desktop"
        $tries = 360
    } else {
        Start-Process -FilePath $exe -WorkingDirectory $Game   # (the shell's start: its own folder as working folder)
        $tries = 40
    }
    $p = $null
    for ($i = 0; $i -lt $tries -and -not $p; $i++) {
        Start-Sleep -Milliseconds 500
        $p = Get-Process -Name Morrowind -ErrorAction SilentlyContinue | Where-Object { $runningBefore -notcontains $_.Id -and $_.Path -eq $exe } | Select-Object -First 1
    }
    if (-not $p) { "start $($attempt): the game didn't start"; Restore-Settings; if ($standinProc -and -not $standinProc.HasExited) { Stop-Process -Id $standinProc.Id -Force }; exit 1 }
    "start $($attempt): game started, PID $($p.Id)"
    # (nothing touches its window after this: changing a fullscreen game's window made it rebuild its graphics, which crashed)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
        if ((Test-Path $results) -and ((Get-Content $results -Raw) -match 'DONE')) { break }
        # (the test asks for a photo by writing its name here; it's taken of the game's window from outside)
        if (Test-Path $photoAsk) {
            $name = (Get-Content $photoAsk -Raw).Trim()
            Remove-Item $photoAsk -ErrorAction SilentlyContinue
            if ($name) {
                $shot = Join-Path $photos "$stamp-$name.png"
                try { Save-Photo $p $shot; "photo: $shot" } catch { "photo $name failed: $_" }
            }
        }
        Start-Sleep -Milliseconds 400
    }
    Start-Sleep -Seconds 2
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; "closed the game (PID $($p.Id))" } else { "game exited by itself" }

    # (a crash while the game loads its data files is the random one: start again. Anything else ends the run.)
    $log = if (Test-Path $mwseLog) { Get-Content $mwseLog -Raw } else { "" }
    $loadCrash = ($log -match 'has crashed') -and ($log -match 'resolveInternalIDs') -and -not ($log -match '\[Open NPC test\]')
    if ($loadCrash -and $attempt -lt $Retries) { "start $($attempt): the random loading crash (before any mod code); starting again"; continue }
    break
}

Restore-Settings
if ($standinProc -and -not $standinProc.HasExited) { Stop-Process -Id $standinProc.Id -Force; "stand-in AI stopped (PID $($standinProc.Id))" }

"--- results"
if (Test-Path $results) { Get-Content $results } else { "no results file (the run didn't finish)" }
"--- MWSE.log errors"
if (Test-Path $mwseLog) { Get-Content $mwseLog | Select-String -Pattern 'error|traceback|attempt to|nil value|\[Open NPC\]' | Select-Object -First 40 | ForEach-Object { $_.Line } }
"--- DXVK log"
$dx = Join-Path $Game 'Morrowind_d3d9.log'
if (Test-Path $dx) { "present, $((Get-Item $dx).Length) bytes, written $((Get-Item $dx).LastWriteTime)"; Get-Content $dx -TotalCount 12 } else { "no DXVK log (DXVK did not load)" }
