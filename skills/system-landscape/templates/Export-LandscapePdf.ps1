<#
.SYNOPSIS
    Renders the filled landscape HTML to a PDF using the browser already
    installed on this machine.

.DESCRIPTION
    Uses Microsoft Edge or Google Chrome in headless mode. Both ship the same
    print engine the browser uses for Ctrl+P, so the PDF matches what you see
    on screen — including the dark background, which most other HTML-to-PDF
    converters drop.

    Nothing is installed and nothing is downloaded. If neither browser is
    present, open the HTML and print to PDF by hand: Ctrl+P, A3 landscape,
    margins none, and "Background graphics" turned ON. Without that last
    option the page comes out white.

.PARAMETER HtmlPath
    The filled landscape HTML file.

.PARAMETER OutputPath
    Where to write the PDF. Defaults to the HTML path with a .pdf extension.

.EXAMPLE
    .\Export-LandscapePdf.ps1 -HtmlPath .\acme-landscape.html

.EXAMPLE
    .\Export-LandscapePdf.ps1 -HtmlPath .\acme-landscape.html -OutputPath C:\Temp\landscape.pdf
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$HtmlPath,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $HtmlPath)) {
    throw "HTML file not found: $HtmlPath"
}

$html = (Resolve-Path $HtmlPath).Path

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::ChangeExtension($html, '.pdf')
}

# Edge first: present on every supported Windows install.
$candidates = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)

$browser = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $browser) {
    throw @"
No Edge or Chrome found in the usual locations.

Open the HTML in any browser and print to PDF instead:
  Ctrl+P, Destination "Save as PDF", A3 landscape, Margins none,
  and turn ON "Background graphics" (without it the page prints white).
"@
}

Write-Host "Browser : $(Split-Path -Leaf $browser)"
Write-Host "Source  : $html"
Write-Host "Output  : $OutputPath"

$fileUri = ([System.Uri]$html).AbsoluteUri

$browserArgs = @(
    '--headless'
    '--disable-gpu'
    '--no-pdf-header-footer'
    '--virtual-time-budget=5000'
    "--print-to-pdf=`"$OutputPath`""
    "`"$fileUri`""
)

$proc = Start-Process -FilePath $browser -ArgumentList $browserArgs -NoNewWindow -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    throw "Browser exited with code $($proc.ExitCode). Print the HTML by hand instead."
}

if (-not (Test-Path $OutputPath)) {
    throw 'The browser reported success but produced no file. Print the HTML by hand instead.'
}

$size = [math]::Round((Get-Item $OutputPath).Length / 1KB)
Write-Host "Done. $size KB" -ForegroundColor Green
Write-Host ''
Write-Host 'Check the PDF before sending it: the page size is set in the HTML' -ForegroundColor DarkGray
Write-Host '(@page A3 landscape). If content is cut off, there are too many' -ForegroundColor DarkGray
Write-Host 'items in a panel - this page is a summary, not the full inventory.' -ForegroundColor DarkGray
