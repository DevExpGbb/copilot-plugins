<#
.SYNOPSIS
    Configure GitHub and GitHub Copilot connections in DevLake.

.DESCRIPTION
    Creates and tests GitHub and/or GitHub Copilot connections against a running
    DevLake instance. Uses the gh CLI for token retrieval and validation.

    Prerequisites:
      - gh CLI installed and authenticated (gh auth status)
      - DevLake instance running and reachable

.PARAMETER DevLakeUrl
    DevLake API base URL. Auto-discovered if omitted.

.PARAMETER ConnectionType
    Which connections to create: "github", "gh-copilot", or "both" (default).

.PARAMETER GitHubToken
    GitHub PAT to use. If omitted, attempts to retrieve from gh CLI.

.PARAMETER Organization
    GitHub organization slug (e.g., "octodemo"). Required for gh-copilot.

.PARAMETER Enterprise
    GitHub enterprise slug (optional, for enterprise-level Copilot metrics).

.PARAMETER ConnectionName
    Display name for the connection(s). Defaults to the organization name.

.PARAMETER SkipTest
    Skip connection testing after creation.

.PARAMETER RateLimitPerHour
    GitHub API rate limit per hour. Default: 12000 for GitHub, 5000 for Copilot.

.EXAMPLE
    .\configure-connections.ps1 -Organization "octodemo"

.EXAMPLE
    .\configure-connections.ps1 -Organization "octodemo" -GitHubToken "ghp_xxx" -ConnectionType "both"

.EXAMPLE
    .\configure-connections.ps1 -DevLakeUrl "http://myhost:8080" -Organization "myorg" -ConnectionType "github"
#>

param(
    [string]$DevLakeUrl,
    [ValidateSet("github", "gh-copilot", "both")]
    [string]$ConnectionType = "both",
    [string]$GitHubToken,
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [string]$Enterprise,
    [string]$ConnectionName,
    [switch]$SkipTest,
    [int]$GitHubRateLimit = 12000,
    [int]$CopilotRateLimit = 5000
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$helpersDir = Join-Path (Split-Path -Parent $scriptDir) "helpers"

# ═══════════════════════════════════════════════════════════════
#  Banner
# ═══════════════════════════════════════════════════════════════
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DevLake - Configure Connections" -ForegroundColor Cyan
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
#  Step 2: Resolve GitHub Token
# ═══════════════════════════════════════════════════════════════
Write-Host "`nStep 2: Resolving GitHub token..." -ForegroundColor Yellow

if (-not $GitHubToken) {
    # Try gh CLI
    Write-Host "  No token provided. Checking gh CLI..." -ForegroundColor Gray
    try {
        $null = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            $GitHubToken = (gh auth token 2>$null).Trim()
            if ($GitHubToken) {
                Write-Host "  Retrieved token from gh CLI." -ForegroundColor Green
            }
        }
    }
    catch { }

    if (-not $GitHubToken) {
        Write-Host "  gh CLI not authenticated or unavailable." -ForegroundColor Yellow
        $GitHubToken = Read-Host "  Enter your GitHub Personal Access Token"
        if (-not $GitHubToken) {
            Write-Error "A GitHub token is required. Provide -GitHubToken or authenticate with 'gh auth login'."
            exit 1
        }
    }
}

# Validate token scopes
Write-Host "  Validating token..." -ForegroundColor Gray
try {
    $headers = @{ Authorization = "Bearer $GitHubToken"; "User-Agent" = "devlake-setup" }
    $tokenCheck = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers $headers -UseBasicParsing -ErrorAction Stop
    $scopes = $tokenCheck.Headers["X-OAuth-Scopes"]
    $ghUser = ($tokenCheck.Content | ConvertFrom-Json).login
    Write-Host "  Authenticated as: $ghUser" -ForegroundColor Green

    if ($scopes) {
        $scopeList = $scopes -split ",\s*"
        $required = @("repo")
        $recommended = @("read:org", "read:user", "copilot", "manage_billing:copilot")

        foreach ($s in $required) {
            if ($scopeList -notcontains $s) {
                Write-Host "  WARNING: Missing required scope '$s'" -ForegroundColor Red
            }
        }
        foreach ($s in $recommended) {
            if ($scopeList -notcontains $s) {
                Write-Host "  WARNING: Missing recommended scope '$s'" -ForegroundColor Yellow
            }
        }
        Write-Host "  Token scopes: $scopes" -ForegroundColor Gray
    }
    else {
        Write-Host "  Note: Fine-grained PAT detected (scopes not listed in headers)." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  WARNING: Could not validate token against GitHub API." -ForegroundColor Yellow
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════
#  Step 3: Set defaults
# ═══════════════════════════════════════════════════════════════
if (-not $ConnectionName) { $ConnectionName = $Organization }
$futureDate = (Get-Date).AddYears(2).ToString("yyyy-MM-ddT00:00:00Z")

# ═══════════════════════════════════════════════════════════════
#  Step 4: Create GitHub Connection
# ═══════════════════════════════════════════════════════════════
$githubConnectionId = $null
$copilotConnectionId = $null

if ($ConnectionType -eq "github" -or $ConnectionType -eq "both") {
    Write-Host "`nStep 3: Creating GitHub connection..." -ForegroundColor Yellow

    # Check if connection already exists
    $existingConnections = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections" -Method Get -ErrorAction SilentlyContinue
    $existing = $existingConnections | Where-Object { $_.name -eq $ConnectionName }

    if ($existing) {
        Write-Host "  Connection '$ConnectionName' already exists (ID: $($existing.id)). Skipping creation." -ForegroundColor Yellow
        $githubConnectionId = $existing.id
    }
    else {
        # Test connection first
        if (-not $SkipTest) {
            Write-Host "  Testing connection parameters..." -ForegroundColor Gray
            $testBody = @{
                endpoint         = "https://api.github.com/"
                authMethod       = "AccessToken"
                token            = $GitHubToken
                enableGraphql    = $true
                rateLimitPerHour = $GitHubRateLimit
                proxy            = ""
            } | ConvertTo-Json

            try {
                $testResult = Invoke-RestMethod -Uri "$apiBase/plugins/github/test" -Method Post -Body $testBody -ContentType "application/json"
                if ($testResult.success -eq $false) {
                    Write-Host "  WARNING: Connection test failed: $($testResult.message)" -ForegroundColor Red
                    Write-Host "  Proceeding anyway..." -ForegroundColor Yellow
                }
                else {
                    Write-Host "  Connection test passed!" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "  WARNING: Connection test request failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Create connection
        $body = @{
            name                  = $ConnectionName
            endpoint              = "https://api.github.com/"
            authMethod            = "AccessToken"
            token                 = $GitHubToken
            enableGraphql         = $true
            rateLimitPerHour      = $GitHubRateLimit
            tokenExpiresAt        = $futureDate
            refreshTokenExpiresAt = $futureDate
        } | ConvertTo-Json

        try {
            $result = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections" -Method Post -Body $body -ContentType "application/json"
            $githubConnectionId = $result.id
            Write-Host "  GitHub connection created (ID: $githubConnectionId)" -ForegroundColor Green
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
            Write-Error "Failed to create GitHub connection (HTTP $statusCode): $($_.Exception.Message)"
            exit 1
        }
    }

    # Test saved connection
    if (-not $SkipTest -and $githubConnectionId) {
        Write-Host "  Verifying saved connection..." -ForegroundColor Gray
        try {
            $verify = Invoke-RestMethod -Uri "$apiBase/plugins/github/connections/$githubConnectionId/test" -Method Post -ContentType "application/json"
            if ($verify.success -ne $false) {
                Write-Host "  Saved connection verified!" -ForegroundColor Green
            }
            else {
                Write-Host "  WARNING: Saved connection test returned: $($verify.message)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  WARNING: Could not verify saved connection." -ForegroundColor Yellow
        }
    }
}

# ═══════════════════════════════════════════════════════════════
#  Step 5: Create GitHub Copilot Connection
# ═══════════════════════════════════════════════════════════════
if ($ConnectionType -eq "gh-copilot" -or $ConnectionType -eq "both") {
    Write-Host "`nStep 4: Creating GitHub Copilot connection..." -ForegroundColor Yellow

    $copilotName = "$ConnectionName-copilot"

    # Check if connection already exists
    $existingCopilot = Invoke-RestMethod -Uri "$apiBase/plugins/gh-copilot/connections" -Method Get -ErrorAction SilentlyContinue
    $existingCp = $existingCopilot | Where-Object { $_.name -eq $copilotName }

    if ($existingCp) {
        Write-Host "  Connection '$copilotName' already exists (ID: $($existingCp.id)). Skipping creation." -ForegroundColor Yellow
        $copilotConnectionId = $existingCp.id
    }
    else {
        # Build copilot connection body
        $copilotBody = @{
            name                  = $copilotName
            endpoint              = "https://api.github.com/"
            authMethod            = "AccessToken"
            token                 = $GitHubToken
            organization          = $Organization
            rateLimitPerHour      = $CopilotRateLimit
            tokenExpiresAt        = $futureDate
            refreshTokenExpiresAt = $futureDate
        }
        if ($Enterprise) {
            $copilotBody.enterprise = $Enterprise
        }
        $copilotBodyJson = $copilotBody | ConvertTo-Json

        # Test connection
        if (-not $SkipTest) {
            Write-Host "  Testing Copilot connection..." -ForegroundColor Gray
            try {
                $testResult = Invoke-RestMethod -Uri "$apiBase/plugins/gh-copilot/test" -Method Post -Body $copilotBodyJson -ContentType "application/json"
                if ($testResult.success -eq $false) {
                    Write-Host "  WARNING: Connection test failed: $($testResult.message)" -ForegroundColor Red
                    Write-Host "  Proceeding anyway (verify PAT has 'copilot' and 'manage_billing:copilot' scopes)..." -ForegroundColor Yellow
                }
                else {
                    Write-Host "  Copilot connection test passed!" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "  WARNING: Copilot connection test failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Create connection
        try {
            $result = Invoke-RestMethod -Uri "$apiBase/plugins/gh-copilot/connections" -Method Post -Body $copilotBodyJson -ContentType "application/json"
            $copilotConnectionId = $result.id
            Write-Host "  Copilot connection created (ID: $copilotConnectionId)" -ForegroundColor Green
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
            Write-Error "Failed to create Copilot connection (HTTP $statusCode): $($_.Exception.Message)"
            exit 1
        }
    }

    # Test saved connection
    if (-not $SkipTest -and $copilotConnectionId) {
        Write-Host "  Verifying saved Copilot connection..." -ForegroundColor Gray
        try {
            $verify = Invoke-RestMethod -Uri "$apiBase/plugins/gh-copilot/connections/$copilotConnectionId/test" -Method Post -ContentType "application/json"
            if ($verify.success -ne $false) {
                Write-Host "  Saved Copilot connection verified!" -ForegroundColor Green
            }
            else {
                Write-Host "  WARNING: Copilot connection test returned: $($verify.message)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  WARNING: Could not verify saved Copilot connection." -ForegroundColor Yellow
        }
    }
}

# ═══════════════════════════════════════════════════════════════
#  Step 6: Save state
# ═══════════════════════════════════════════════════════════════
Write-Host "`nSaving connection state..." -ForegroundColor Yellow

# Try to update existing state file, or create local state
$stateFile = $null
$state = $null
$azureState = Join-Path (Get-Location) ".devlake-azure.json"
$localState = Join-Path (Get-Location) ".devlake-local.json"

if (Test-Path $azureState) {
    $stateFile = $azureState
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
}
elseif (Test-Path $localState) {
    $stateFile = $localState
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
}
else {
    # Create a new local state file
    $stateFile = $localState
    $state = [PSCustomObject]@{
        deployedAt = (Get-Date -Format "o")
        method     = "local"
        endpoints  = [PSCustomObject]@{
            backend  = $apiBase
            grafana  = $devlake.GrafanaUrl
            configUi = $null
        }
    }
}

# Add/update connections in state
$connections = @()
if ($githubConnectionId) {
    $connections += [PSCustomObject]@{
        plugin       = "github"
        connectionId = $githubConnectionId
        name         = $ConnectionName
    }
}
if ($copilotConnectionId) {
    $connections += [PSCustomObject]@{
        plugin       = "gh-copilot"
        connectionId = $copilotConnectionId
        name         = "$ConnectionName-copilot"
        organization = $Organization
        enterprise   = $Enterprise
    }
}

$state | Add-Member -NotePropertyName "connections" -NotePropertyValue $connections -Force
$state | Add-Member -NotePropertyName "connectionsConfiguredAt" -NotePropertyValue (Get-Date -Format "o") -Force
$state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8

Write-Host "  State saved to: $stateFile" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Connections Configured!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

Write-Host "Connections created:" -ForegroundColor Yellow
if ($githubConnectionId) {
    Write-Host "  GitHub:  ID=$githubConnectionId  Name='$ConnectionName'"
}
if ($copilotConnectionId) {
    Write-Host "  Copilot: ID=$copilotConnectionId  Name='$ConnectionName-copilot'"
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  Run configure-scopes.ps1 to add repositories and create a project."
Write-Host "  Example:"
Write-Host "    .\configure\configure-scopes.ps1 -Organization `"$Organization`" -Repos `"$Organization/my-repo`""
Write-Host ""

# Return connection IDs for pipeline use
return [PSCustomObject]@{
    GitHubConnectionId  = $githubConnectionId
    CopilotConnectionId = $copilotConnectionId
    DevLakeUrl          = $apiBase
    StateFile           = $stateFile
}
