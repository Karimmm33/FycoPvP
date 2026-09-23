<#
.SYNOPSIS
    Build the release zip that users download.

.DESCRIPTION
    The whole point of this script is the folder name inside the archive.

    GitHub's own "Code -> Download ZIP" names the archive after the BRANCH, so
    it extracts as FycoPvP-main. WoW matches an addon's folder name against its
    .toc, so FycoPvP-main\FycoPvP.toc never appears in the AddOns list at all --
    and Data.lua looks Voice\ and Textures\ up by the absolute path
    Interface\AddOns\FycoPvP\, so even forced to load it would find no media.

    This produces dist\FycoPvP-<version>.zip with a single top-level FycoPvP\
    folder, which is what makes "extract into AddOns and it works" true. Attach
    it to the GitHub release; never point people at Download ZIP.

    The version is read from FycoPvP.toc so it cannot drift from the addon.

.EXAMPLE
    .\scripts\package.ps1
    gh release create v1.17.0 .\dist\FycoPvP-1.17.0.zip --title "FycoPvP 1.17.0" --notes-file notes.md
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# Must match deploy.ps1: what a user gets is what you tested against.
$rootFiles  = @("FycoPvP.toc", "Core.lua", "Data.lua", "README.md", "LICENSE")
$mirrorDirs = @("Modules", "Textures", "Voice")

# --- version, from the .toc --------------------------------------------------
$tocPath = Join-Path $root "FycoPvP.toc"
$match   = Select-String -Path $tocPath -Pattern '^##\s*Version:\s*(.+)$'
if (-not $match) { throw "could not read '## Version:' from FycoPvP.toc" }
$version = $match.Matches[0].Groups[1].Value.Trim()
Write-Host "version: $version"

# --- stage -------------------------------------------------------------------
$dist  = Join-Path $root "dist"
$stage = Join-Path $dist "stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$addon = Join-Path $stage "FycoPvP"
New-Item -ItemType Directory -Path $addon -Force | Out-Null

foreach ($f in $rootFiles) {
    $src = Join-Path $root $f
    if (-not (Test-Path $src)) { throw "missing from project: $f" }
    Copy-Item $src -Destination (Join-Path $addon $f) -Force
}
foreach ($d in $mirrorDirs) {
    $src = Join-Path $root $d
    if (-not (Test-Path $src)) { throw "missing from project: $d\" }
    Copy-Item $src -Destination (Join-Path $addon $d) -Recurse -Force
}

# --- zip ---------------------------------------------------------------------
$zip = Join-Path $dist "FycoPvP-$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $addon -DestinationPath $zip -Force

# --- verify, because a broken archive is invisible until a user unzips it ----
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $names = $z.Entries | ForEach-Object { $_.FullName }
    $stray = $names | Where-Object { $_ -notlike "FycoPvP/*" }
    if ($stray) { throw "archive has entries outside FycoPvP/: $($stray -join ', ')" }
    if ($names -notcontains "FycoPvP/FycoPvP.toc") { throw "archive has no FycoPvP/FycoPvP.toc" }
    $count = $z.Entries.Count
} finally { $z.Dispose() }

Remove-Item $stage -Recurse -Force

$kb = "{0:N0}" -f ((Get-Item $zip).Length / 1KB)
Write-Host ""
Write-Host "  $zip" -ForegroundColor Green
Write-Host "  $count entries, all under FycoPvP/, toc present, $kb KB" -ForegroundColor Green
