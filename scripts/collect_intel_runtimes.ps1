param(
    [string]$Executable = "install\Nays2DH.exe",
    [string]$Destination = "install"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Executable)) {
    throw "Solver executable not found: $Executable"
}

$dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if ($null -eq $dumpbin) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "dumpbin.exe and vswhere.exe were not found"
    }
    $dumpbinPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -find "VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe" |
        Select-Object -First 1
    if (-not $dumpbinPath) {
        throw "dumpbin.exe was not found in Visual Studio"
    }
} else {
    $dumpbinPath = $dumpbin.Source
}

$dependencyLines = & $dumpbinPath /dependents $Executable
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin failed with exit code $LASTEXITCODE"
}

$runtimeNames = $dependencyLines |
    ForEach-Object {
        if ($_ -match '^\s*([A-Za-z0-9_.-]+\.dll)\s*$') { $Matches[1] }
    } |
    Where-Object { $_ -match '^(libif|libiomp|libmmd|svml|libirc)' } |
    Sort-Object -Unique

if (-not $runtimeNames) {
    throw "No Intel runtime dependencies were reported by dumpbin"
}

$compilerRoot = "${env:ProgramFiles(x86)}\Intel\oneAPI\compiler"
if (-not (Test-Path -LiteralPath $compilerRoot)) {
    throw "Intel compiler directory not found: $compilerRoot"
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
foreach ($runtimeName in $runtimeNames) {
    $candidate = Get-ChildItem -LiteralPath $compilerRoot -Recurse `
        -File -Filter $runtimeName |
        Where-Object { $_.FullName -notmatch '\\bin32\\' } |
        ForEach-Object {
            $headers = & $dumpbinPath /headers $_.FullName
            if ($LASTEXITCODE -eq 0 -and $headers -match '8664 machine') {
                $_
            }
        } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw "Required Intel runtime was not found: $runtimeName"
    }
    Copy-Item -LiteralPath $candidate.FullName -Destination $Destination -Force
    Write-Host "Collected $runtimeName from $($candidate.DirectoryName)"
}
