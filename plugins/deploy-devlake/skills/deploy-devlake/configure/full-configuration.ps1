<#
.SYNOPSIS
    Full post-deployment DevLake configuration: connections + scopes + project in one flow.

.DESCRIPTION
    Runs Phase 2 (configure-connections.ps1) then Phase 3 (configure-scopes.ps1)
    in sequence, passing state between them automatically.

    This is a convenience wrapper for users who already have DevLake deployed
    and want to configure it end-to-end (Phases 2 + 3).

.PARAMETER DevLakeUrl
    DevLake API base URL. Auto-discovered if omitted.

.PARAMETER GitHubToken
    GitHub PAT. If omitted, retrieved from gh CLI.

.PARAMETER Organization
    GitHub organization slug (required).

.PARAMETER Enterprise
    GitHub enterprise slug (optional, for enterprise Copilot metrics).

.PARAMETER Repos
    Array of repos in "owner/repo" format. If omitted, lists from gh CLI.

.PARAMETER ReposFile
    Path to a CSV or TXT file containing repos (one "owner/repo" per line).
    Useful when tracking many repositories. Takes precedence over -Repos.

.PARAMETER ProjectName
    DevLake project name. Defaults to organization name.

.PARAMETER ConnectionType
    "github", "gh-copilot", or "both" (default).

.PARAMETER DeploymentPattern
    Regex to match deployment workflows. Default: "(?i)deploy"

.PARAMETER ProductionPattern
    Regex to match production environment. Default: "(?i)prod"

.PARAMETER SkipSync
    Skip triggering the first data sync.

.EXAMPLE
    .\full-configuration.ps1 -Organization "octodemo" -Repos "octodemo/app1"

.EXAMPLE
    .\full-configuration.ps1 -Organization "octodemo" -ReposFile ".\my-repos.csv"

.EXAMPLE
    .\full-configuration.ps1 -Organization "octodemo"
#>

param(
    [string]$DevLakeUrl,
    [string]$GitHubToken,
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [string]$Enterprise,
    [string[]]$Repos,
    [string]$ReposFile,
    [string]$ProjectName,
    [ValidateSet("github", "gh-copilot", "both")]
    [string]$ConnectionType = "both",
    [string]$DeploymentPattern = "(?i)deploy",
    [string]$ProductionPattern = "(?i)prod",
    [switch]$SkipSync
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  DevLake - Full Configuration" -ForegroundColor Cyan
Write-Host "  Phase 2: Configure Connections" -ForegroundColor Cyan
Write-Host "  Phase 3: Configure Scopes, Project & First Sync" -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════
#  Resolve repos from file if provided
# ═══════════════════════════════════════════════════════════════
if ($ReposFile -and -not $Repos) {
    if (-not (Test-Path $ReposFile)) {
        Write-Error "Repos file not found: $ReposFile"
        exit 1
    }
    Write-Host "Loading repos from file: $ReposFile" -ForegroundColor Yellow
    $Repos = Get-Content $ReposFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' -and $_ -notmatch '^repo' }
    Write-Host "  Loaded $($Repos.Count) repo(s) from file." -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════
#  Phase 2: Configure Connections
# ═══════════════════════════════════════════════════════════════
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  PHASE 2: Configure Connections      ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════╝`n" -ForegroundColor Magenta

$connectScript = Join-Path $scriptDir "configure-connections.ps1"
$connectParams = @{
    Organization   = $Organization
    ConnectionType = $ConnectionType
}
if ($DevLakeUrl)   { $connectParams.DevLakeUrl = $DevLakeUrl }
if ($GitHubToken)  { $connectParams.GitHubToken = $GitHubToken }
if ($Enterprise)   { $connectParams.Enterprise = $Enterprise }

$connectResult = & $connectScript @connectParams

if (-not $connectResult) {
    Write-Error "Phase 2 failed. Cannot continue to Phase 3."
    exit 1
}

Write-Host "`n  Phase 2 complete." -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════
#  Phase 3: Configure Scopes & Project
# ═══════════════════════════════════════════════════════════════
Write-Host "`n╔══════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  PHASE 3: Configure Scopes & Project ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════╝`n" -ForegroundColor Magenta

$scopeScript = Join-Path $scriptDir "configure-scopes.ps1"
$scopeParams = @{
    DevLakeUrl          = $connectResult.DevLakeUrl
    GitHubConnectionId  = $connectResult.GitHubConnectionId
    Organization        = $Organization
    DeploymentPattern   = $DeploymentPattern
    ProductionPattern   = $ProductionPattern
}
if ($connectResult.CopilotConnectionId) {
    $scopeParams.CopilotConnectionId = $connectResult.CopilotConnectionId
}
else {
    $scopeParams.SkipCopilot = $true
}
if ($Repos)        { $scopeParams.Repos = $Repos }
if ($ReposFile -and -not $Repos) { $scopeParams.ReposFile = $ReposFile }
if ($ProjectName)  { $scopeParams.ProjectName = $ProjectName }
if ($SkipSync)     { $scopeParams.SkipSync = $true }

$scopeResult = & $scopeScript @scopeParams

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  Full configuration complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

return $scopeResult
