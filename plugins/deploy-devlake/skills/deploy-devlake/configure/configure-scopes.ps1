<#
.SYNOPSIS
    Configure scopes, create a project and blueprint, and trigger the first sync.

.DESCRIPTION
    Phase 3 of DevLake setup:
      1. Look up GitHub repository IDs via gh CLI
      2. Create a DORA scope config for the GitHub connection
      3. Add repository scopes to the GitHub connection
      4. Add organization scope to the Copilot connection
      5. Create a DevLake project (which auto-creates a blueprint)
      6. Configure the blueprint with connection scopes
      7. Trigger the first data sync and monitor progress

    Prerequisites:
      - DevLake running with connections already configured (Phase 2)
      - gh CLI installed and authenticated

.PARAMETER DevLakeUrl
    DevLake API base URL. Auto-discovered if omitted.

.PARAMETER GitHubConnectionId
    ID of the GitHub connection. Auto-detected from state file or API if omitted.

.PARAMETER CopilotConnectionId
    ID of the Copilot connection. Auto-detected from state file or API if omitted.

.PARAMETER Repos
    Array of GitHub repositories in "owner/repo" format.
    If omitted (and no -ReposFile), uses gh CLI to list repos for selection.

.PARAMETER ReposFile
    Path to a CSV or TXT file containing repos (one "owner/repo" per line).
    Lines starting with # are treated as comments and skipped.
    A CSV header row starting with "repo" is also skipped.
    Takes precedence over -Repos if both are provided.

.PARAMETER Organization
    GitHub organization slug (for Copilot scope). Auto-detected from state file if omitted.

.PARAMETER ProjectName
    DevLake project name. Defaults to the organization name.

.PARAMETER DeploymentPattern
    Regex to match deployment workflow names for DORA. Default: "(?i)deploy"

.PARAMETER ProductionPattern
    Regex to match production environment for DORA. Default: "(?i)prod"

.PARAMETER IncidentLabel
    Issue label that identifies incidents for DORA. Default: "incident"

.PARAMETER TimeAfter
    Only collect data after this date (ISO 8601). Default: 6 months ago.

.PARAMETER CronSchedule
    Blueprint cron schedule. Default: "0 0 * * *" (daily at midnight).

.PARAMETER SkipSync
    Skip triggering the first data sync after setup.

.PARAMETER SkipCopilot
    Skip adding Copilot scope (GitHub repos only).

.EXAMPLE
    .\configure-scopes.ps1 -Organization "octodemo" -Repos "octodemo/app1","octodemo/app2"

.EXAMPLE
    .\configure-scopes.ps1 -Organization "octodemo" -ReposFile ".\my-repos.csv"

.EXAMPLE
    .\configure-scopes.ps1 -Organization "octodemo" -ProjectName "My DORA Project"
#>

param(
    [string]$DevLakeUrl,
    [int]$GitHubConnectionId,
    [int]$CopilotConnectionId,
    [string[]]$Repos,
    [string]$ReposFile,
    [string]$Organization,
    [string]$ProjectName,
    [string]$DeploymentPattern = "(?i)deploy",
    [string]$ProductionPattern = "(?i)prod",
    [string]$IncidentLabel = "incident",
    [string]$TimeAfter,
    [string]$CronSchedule = "0 0 * * *",
    [switch]$SkipSync,
    [switch]$SkipCopilot
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersDir = Join-Path (Split-Path -Parent $scriptDir) "helpers"

# ═══════════════════════════════════════════════════════════════
#  Banner
# ═══════════════════════════════════════════════════════════════
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DevLake - Configure Scopes & Project" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════
#  Step 1: Discover DevLake
# ═══════════════════════════════════════════════════════════════
Write-Host "Step 1: Discovering DevLake instance..." -ForegroundColor Yellow
$discoverScript = Join-Path $helpersDir "discover-devlake.ps1"
$devlake = & $discoverScript -DevLakeUrl $DevLakeUrl
$apiBase = $devlake.Url
Write-Host "  API: $apiBase" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════
#  Step 2: Resolve connection IDs and organization
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 2: Resolving connections..." -ForegroundColor Yellow

# Try state file first
$stateData = $null
$azureState = Join-Path (Get-Location) ".devlake-azure.json"
$localState = Join-Path (Get-Location) ".devlake-local.json"
$stateFile = $null

if (Test-Path $azureState) {
    $stateData = Get-Content $azureState -Raw | ConvertFrom-Json
    $stateFile = $azureState
}
elseif (Test-Path $localState) {
    $stateData = Get-Content $localState -Raw | ConvertFrom-Json
    $stateFile = $localState
}

# Resolve GitHub connection ID
if (-not $GitHubConnectionId) {
    if ($stateData -and $stateData.connections) {
        $ghConn = $stateData.connections | Where-Object { $_.plugin -eq "github" } | Select-Object -First 1
        if ($ghConn) {
            $GitHubConnectionId = $ghConn.connectionId
            Write-Host "  GitHub connection ID from state file: $GitHubConnectionId" -ForegroundColor Green
        }
    }
    if (-not $GitHubConnectionId) {
        # List from API
        $connections = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections" -Method Get
        if ($connections.Count -eq 1) {
            $GitHubConnectionId = $connections[0].id
            Write-Host "  GitHub connection ID from API: $GitHubConnectionId" -ForegroundColor Green
        }
        elseif ($connections.Count -gt 1) {
            Write-Host "  Multiple GitHub connections found:" -ForegroundColor Yellow
            foreach ($c in $connections) {
                Write-Host "    ID=$($c.id)  Name='$($c.name)'"
            }
            $GitHubConnectionId = [int](Read-Host "  Enter the GitHub connection ID to use")
        }
        else {
            Write-Error "No GitHub connections found. Run configure-connections.ps1 first."
            exit 1
        }
    }
}

# Resolve Copilot connection ID
if (-not $SkipCopilot -and -not $CopilotConnectionId) {
    if ($stateData -and $stateData.connections) {
        $cpConn = $stateData.connections | Where-Object { $_.plugin -eq "gh-copilot" } | Select-Object -First 1
        if ($cpConn) {
            $CopilotConnectionId = $cpConn.connectionId
            Write-Host "  Copilot connection ID from state file: $CopilotConnectionId" -ForegroundColor Green
        }
    }
    if (-not $CopilotConnectionId) {
        try {
            $cpConnections = Invoke-RestMethod -Uri "$apiBase/plugins/gh-copilot/connections" -Method Get -ErrorAction SilentlyContinue
            if ($cpConnections.Count -eq 1) {
                $CopilotConnectionId = $cpConnections[0].id
                Write-Host "  Copilot connection ID from API: $CopilotConnectionId" -ForegroundColor Green
            }
            elseif ($cpConnections.Count -gt 1) {
                Write-Host "  Multiple Copilot connections found:" -ForegroundColor Yellow
                foreach ($c in $cpConnections) {
                    Write-Host "    ID=$($c.id)  Name='$($c.name)'"
                }
                $CopilotConnectionId = [int](Read-Host "  Enter the Copilot connection ID to use")
            }
            else {
                Write-Host "  No Copilot connections found. Skipping Copilot scope." -ForegroundColor Yellow
                $SkipCopilot = $true
            }
        }
        catch {
            Write-Host "  Copilot plugin not available. Skipping." -ForegroundColor Yellow
            $SkipCopilot = $true
        }
    }
}

# Resolve organization
if (-not $Organization) {
    if ($stateData -and $stateData.connections) {
        $cpState = $stateData.connections | Where-Object { $_.plugin -eq "gh-copilot" } | Select-Object -First 1
        if ($cpState -and $cpState.organization) {
            $Organization = $cpState.organization
            Write-Host "  Organization from state file: $Organization" -ForegroundColor Green
        }
    }
    if (-not $Organization) {
        $Organization = Read-Host "  Enter your GitHub organization slug"
        if (-not $Organization) {
            Write-Error "Organization is required for Copilot scope."
            exit 1
        }
    }
}

if (-not $ProjectName) { $ProjectName = $Organization }
if (-not $TimeAfter) { $TimeAfter = (Get-Date).AddMonths(-6).ToString("yyyy-MM-ddT00:00:00Z") }

Write-Host "`n  Configuration:" -ForegroundColor Yellow
Write-Host "    GitHub Connection: $GitHubConnectionId"
if (-not $SkipCopilot) { Write-Host "    Copilot Connection: $CopilotConnectionId" }
Write-Host "    Organization: $Organization"
Write-Host "    Project Name: $ProjectName"
Write-Host "    Time After: $TimeAfter"

# ═══════════════════════════════════════════════════════════════
#  Step 3: Resolve repositories
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 3: Resolving repositories..." -ForegroundColor Yellow

# Load from file if provided
if ($ReposFile -and (-not $Repos -or $Repos.Count -eq 0)) {
    if (-not (Test-Path $ReposFile)) {
        Write-Error "Repos file not found: $ReposFile"
        exit 1
    }
    Write-Host "  Loading repos from file: $ReposFile" -ForegroundColor Yellow
    $Repos = Get-Content $ReposFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^#' -and $_ -notmatch '^repo' }
    Write-Host "  Loaded $($Repos.Count) repo(s) from file." -ForegroundColor Green
}

if (-not $Repos -or $Repos.Count -eq 0) {
    Write-Host "  No repos specified. Listing repos in '$Organization' via gh CLI..." -ForegroundColor Gray
    try {
        $repoList = gh repo list $Organization --limit 30 --json nameWithOwner,id --jq '.[].nameWithOwner' 2>$null
        if ($LASTEXITCODE -eq 0 -and $repoList) {
            $availableRepos = $repoList -split "`n" | Where-Object { $_ }
            Write-Host "  Available repos in $Organization (showing up to 30):" -ForegroundColor Yellow
            for ($i = 0; $i -lt $availableRepos.Count; $i++) {
                Write-Host "    [$($i+1)] $($availableRepos[$i])"
            }
            Write-Host ""
            $selection = Read-Host "  Enter repo numbers (comma-separated, e.g., 1,3,5) or 'all'"
            if ($selection -eq "all") {
                $Repos = $availableRepos
            }
            else {
                $indices = $selection -split "," | ForEach-Object { [int]$_.Trim() - 1 }
                $Repos = $indices | ForEach-Object { $availableRepos[$_] }
            }
        }
        else {
            Write-Host "  Could not list repos via gh CLI." -ForegroundColor Yellow
            $repoInput = Read-Host "  Enter repos (comma-separated, e.g., org/repo1,org/repo2)"
            $Repos = $repoInput -split "," | ForEach-Object { $_.Trim() }
        }
    }
    catch {
        Write-Host "  gh CLI not available." -ForegroundColor Yellow
        $repoInput = Read-Host "  Enter repos (comma-separated, e.g., org/repo1,org/repo2)"
        $Repos = $repoInput -split "," | ForEach-Object { $_.Trim() }
    }
}

if (-not $Repos -or $Repos.Count -eq 0) {
    Write-Error "At least one repository is required."
    exit 1
}

Write-Host "  Repos to configure: $($Repos -join ', ')" -ForegroundColor Green

# Look up GitHub repo details via gh CLI
Write-Host "`n  Looking up repo details..." -ForegroundColor Gray
$repoDetails = @()
foreach ($repo in $Repos) {
    try {
        $repoJson = gh api "repos/$repo" --jq '{id: .id, name: .name, full_name: .full_name, html_url: .html_url, clone_url: .clone_url}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $repoJson) {
            $detail = $repoJson | ConvertFrom-Json
            $repoDetails += $detail
            Write-Host "    $($detail.full_name) (ID: $($detail.id))" -ForegroundColor Green
        }
        else {
            Write-Host "    WARNING: Could not fetch details for '$repo'" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "    WARNING: gh api failed for '$repo': $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($repoDetails.Count -eq 0) {
    Write-Error "Could not resolve any repository details. Verify repos exist and gh CLI is authenticated."
    exit 1
}

# ═══════════════════════════════════════════════════════════════
#  Step 4: Create DORA scope config
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 4: Creating DORA scope config..." -ForegroundColor Yellow

$scopeConfigBody = @{
    name                = "dora-config"
    connectionId        = $GitHubConnectionId
    deploymentPattern   = $DeploymentPattern
    productionPattern   = $ProductionPattern
    issueTypeIncident   = $IncidentLabel
    refdiff             = @{
        tagsPattern = ".*"
        tagsLimit   = 10
        tagsOrder   = "reverse semver"
    }
} | ConvertTo-Json -Depth 3

$scopeConfigId = $null
try {
    $scopeConfigResult = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections/$GitHubConnectionId/scope-configs" -Method Post -Body $scopeConfigBody -ContentType "application/json"
    $scopeConfigId = $scopeConfigResult.id
    Write-Host "  Scope config created (ID: $scopeConfigId)" -ForegroundColor Green
    Write-Host "    Deployment pattern: $DeploymentPattern" -ForegroundColor Gray
    Write-Host "    Production pattern: $ProductionPattern" -ForegroundColor Gray
    Write-Host "    Incident label: $IncidentLabel" -ForegroundColor Gray
}
catch {
    # Might already exist - try to list and find it
    Write-Host "  Could not create scope config (may already exist). Fetching existing..." -ForegroundColor Yellow
    try {
        $existing = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections/$GitHubConnectionId/scope-configs" -Method Get
        if ($existing.Count -gt 0) {
            $scopeConfigId = $existing[0].id
            Write-Host "  Using existing scope config (ID: $scopeConfigId)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  WARNING: Could not create or find scope config. Repos will use default config." -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════
#  Step 5: Add repo scopes to GitHub connection
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 5: Adding repository scopes..." -ForegroundColor Yellow

$scopeData = $repoDetails | ForEach-Object {
    $entry = @{
        githubId     = $_.id
        connectionId = $GitHubConnectionId
        name         = $_.name
        fullName     = $_.full_name
        htmlUrl      = $_.html_url
        cloneUrl     = $_.clone_url
    }
    if ($scopeConfigId) { $entry.scopeConfigId = $scopeConfigId }
    $entry
}

$scopeBody = @{ data = @($scopeData) } | ConvertTo-Json -Depth 3

try {
    $null = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections/$GitHubConnectionId/scopes" -Method Put -Body $scopeBody -ContentType "application/json"
    Write-Host "  Added $($repoDetails.Count) repo scope(s):" -ForegroundColor Green
    foreach ($r in $repoDetails) {
        Write-Host "    $($r.full_name) (GitHub ID: $($r.id))" -ForegroundColor Gray
    }
}
catch {
    Write-Error "Failed to add repo scopes: $($_.Exception.Message)"
    exit 1
}

# ═══════════════════════════════════════════════════════════════
#  Step 6: Add Copilot scope
# ═══════════════════════════════════════════════════════════════
if (-not $SkipCopilot -and $CopilotConnectionId) {
    Write-Host "`nStep 6: Adding Copilot scope..." -ForegroundColor Yellow

    $copilotScopeBody = @{
        data = @(
            @{
                id           = $Organization
                connectionId = $CopilotConnectionId
                organization = $Organization
                name         = $Organization
                fullName     = $Organization
            }
        )
    } | ConvertTo-Json -Depth 3

    try {
        Invoke-RestMethod -Uri "$apiBase/plugins/gh-copilot/connections/$CopilotConnectionId/scopes" -Method Put -Body $copilotScopeBody -ContentType "application/json"
        Write-Host "  Copilot scope added: $Organization" -ForegroundColor Green
    }
    catch {
        Write-Host "  WARNING: Could not add Copilot scope: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ═══════════════════════════════════════════════════════════════
#  Step 7: Create Project
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 7: Creating DevLake project..." -ForegroundColor Yellow

$projectBody = @{
    name        = $ProjectName
    description = "DORA metrics and Copilot adoption for $Organization"
    metrics     = @(
        @{ pluginName = "dora"; enable = $true }
    )
} | ConvertTo-Json -Depth 3

$blueprintId = $null
try {
    $projectResult = Invoke-RestMethod -Uri "$apiBase/projects" -Method Post -Body $projectBody -ContentType "application/json"
    $blueprintId = $projectResult.blueprint.id
    Write-Host "  Project '$ProjectName' created" -ForegroundColor Green
    Write-Host "  Blueprint ID: $blueprintId" -ForegroundColor Green
}
catch {
    # Project might already exist
    Write-Host "  Project creation failed (may already exist). Looking up..." -ForegroundColor Yellow
    try {
        $existingProject = Invoke-RestMethod -Uri "$apiBase/projects/$ProjectName" -Method Get -ErrorAction SilentlyContinue
        if ($existingProject -and $existingProject.blueprint) {
            $blueprintId = $existingProject.blueprint.id
            Write-Host "  Using existing project '$ProjectName' (Blueprint ID: $blueprintId)" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Could not create or find project '$ProjectName'."
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════
#  Step 8: Configure Blueprint
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 8: Configuring blueprint..." -ForegroundColor Yellow

# Build scopes array for GitHub connection
$githubScopes = $repoDetails | ForEach-Object {
    @{ scopeId = [string]$_.id; scopeName = $_.full_name }
}

$blueprintConnections = @(
    @{
        pluginName   = "github"
        connectionId = $GitHubConnectionId
        scopes       = @($githubScopes)
    }
)

if (-not $SkipCopilot -and $CopilotConnectionId) {
    $blueprintConnections += @{
        pluginName   = "gh-copilot"
        connectionId = $CopilotConnectionId
        scopes       = @(
            @{ scopeId = $Organization; scopeName = $Organization }
        )
    }
}

$blueprintUpdate = @{
    connections = $blueprintConnections
    enable      = $true
    cronConfig  = $CronSchedule
    timeAfter   = $TimeAfter
} | ConvertTo-Json -Depth 5

try {
    Invoke-RestMethod -Uri "$apiBase/blueprints/$blueprintId" -Method Patch -Body $blueprintUpdate -ContentType "application/json"
    Write-Host "  Blueprint configured with $($repoDetails.Count) repo(s)" -ForegroundColor Green
    if (-not $SkipCopilot -and $CopilotConnectionId) {
        Write-Host "  + Copilot scope: $Organization" -ForegroundColor Green
    }
    Write-Host "  Schedule: $CronSchedule" -ForegroundColor Gray
    Write-Host "  Data since: $TimeAfter" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to configure blueprint: $($_.Exception.Message)"
    exit 1
}

# ═══════════════════════════════════════════════════════════════
#  Step 9: Trigger first sync
# ═══════════════════════════════════════════════════════════════
if (-not $SkipSync) {
    Write-Host "`nStep 9: Triggering first data sync..." -ForegroundColor Yellow

    try {
        $triggerResult = Invoke-RestMethod -Uri "$apiBase/blueprints/$blueprintId/trigger" -Method Post -ContentType "application/json"
        $pipelineId = $triggerResult.id
        Write-Host "  Pipeline started (ID: $pipelineId)" -ForegroundColor Green

        # Monitor progress
        Write-Host "  Monitoring progress (press Ctrl+C to stop monitoring)..." -ForegroundColor Gray
        $maxWait = 300   # 5 minutes max monitoring
        $elapsed = 0
        $pollInterval = 10

        while ($elapsed -lt $maxWait) {
            Start-Sleep -Seconds $pollInterval
            $elapsed += $pollInterval

            try {
                $pipeline = Invoke-RestMethod -Uri "$apiBase/pipelines/$pipelineId" -Method Get
                $status = $pipeline.status
                $finished = $pipeline.finishedTasks
                $total = $pipeline.totalTasks

                Write-Host "    [$([math]::Floor($elapsed))s] Status: $status | Tasks: $finished/$total" -ForegroundColor Gray

                if ($status -eq "TASK_COMPLETED") {
                    Write-Host "`n  Data sync completed!" -ForegroundColor Green
                    break
                }
                elseif ($status -eq "TASK_FAILED") {
                    Write-Host "`n  WARNING: Pipeline failed. Check DevLake logs for details." -ForegroundColor Red
                    Write-Host "  Pipeline URL: $apiBase/pipelines/$pipelineId" -ForegroundColor Gray
                    break
                }
            }
            catch {
                Write-Host "    [$elapsed s] Could not check status..." -ForegroundColor Gray
            }
        }

        if ($elapsed -ge $maxWait) {
            Write-Host "`n  Monitoring timed out after $maxWait seconds." -ForegroundColor Yellow
            Write-Host "  The pipeline is still running. Check status at:" -ForegroundColor Yellow
            Write-Host "  $apiBase/pipelines/$pipelineId" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  WARNING: Could not trigger sync: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  You can trigger manually via the Config UI or API." -ForegroundColor Gray
    }
}

# ═══════════════════════════════════════════════════════════════
#  Step 10: Update state file
# ═══════════════════════════════════════════════════════════════
if ($stateFile -and $stateData) {
    $stateData | Add-Member -NotePropertyName "project" -NotePropertyValue ([PSCustomObject]@{
        name        = $ProjectName
        blueprintId = $blueprintId
        repos       = @($Repos)
        organization = $Organization
    }) -Force
    $stateData | Add-Member -NotePropertyName "scopesConfiguredAt" -NotePropertyValue (Get-Date -Format "o") -Force
    $stateData | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
    Write-Host "`nState updated: $stateFile" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  DevLake Setup Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Project: $ProjectName" -ForegroundColor Yellow
Write-Host "Repos:   $($Repos -join ', ')"
if (-not $SkipCopilot) {
    Write-Host "Copilot: $Organization"
}
Write-Host "Schedule: $CronSchedule (data since $TimeAfter)"

$grafanaUrl = $devlake.GrafanaUrl
if ($grafanaUrl) {
    Write-Host "`nDashboards:" -ForegroundColor Cyan
    Write-Host "  Grafana:   $grafanaUrl (admin/admin)"
    Write-Host "  DORA:      $grafanaUrl/d/dora"
    Write-Host "  Copilot:   $grafanaUrl/d/copilot"
}

Write-Host "`nConfig UI: $apiBase" -ForegroundColor Gray
Write-Host ""

# Return summary for pipeline use
return [PSCustomObject]@{
    ProjectName = $ProjectName
    BlueprintId = $blueprintId
    Repos       = $Repos
    DevLakeUrl  = $apiBase
    GrafanaUrl  = $grafanaUrl
}
