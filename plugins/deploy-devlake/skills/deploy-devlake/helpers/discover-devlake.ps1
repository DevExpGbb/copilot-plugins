<#
.SYNOPSIS
    Discover a running DevLake instance and return its API base URL.

.DESCRIPTION
    Checks multiple sources to find a reachable DevLake backend:
      1. Explicit -DevLakeUrl parameter
      2. .devlake-azure.json state file (Azure deployment)
      3. Well-known local ports (8080, 8085)
    Validates connectivity via /ping before returning.

.PARAMETER DevLakeUrl
    Explicit DevLake API URL to use (skips auto-discovery).

.PARAMETER StateFilePath
    Path to search for the Azure state file. Defaults to current directory.

.PARAMETER Quiet
    Suppress informational output.

.OUTPUTS
    PSCustomObject with:
      - Url        : The validated DevLake API base URL (no trailing slash)
      - Source      : How the URL was discovered (parameter | statefile | localhost | user)
      - GrafanaUrl  : Grafana URL if known (from state file), otherwise $null

.EXAMPLE
    $devlake = .\helpers\discover-devlake.ps1
    Invoke-RestMethod "$($devlake.Url)/plugins"

.EXAMPLE
    $devlake = .\helpers\discover-devlake.ps1 -DevLakeUrl "http://myhost:8080"
#>

param(
    [string]$DevLakeUrl,
    [string]$StateFilePath = ".",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message, [string]$Color = "Gray")
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

function Test-DevLakeEndpoint {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri "$Url/ping" -TimeoutSec 5 -ErrorAction SilentlyContinue -UseBasicParsing
        return ($response.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

# ── 1. Explicit parameter ────────────────────────────────────────────
if ($DevLakeUrl) {
    $DevLakeUrl = $DevLakeUrl.TrimEnd('/')
    Write-Info "Testing provided URL: $DevLakeUrl" "Yellow"
    if (Test-DevLakeEndpoint $DevLakeUrl) {
        Write-Info "  Connected!" "Green"
        return [PSCustomObject]@{
            Url        = $DevLakeUrl
            Source     = "parameter"
            GrafanaUrl = $null
        }
    }
    else {
        Write-Host "  ERROR: Cannot reach DevLake at $DevLakeUrl/ping" -ForegroundColor Red
        Write-Host "  Ensure DevLake is running and the URL is correct." -ForegroundColor Red
        exit 1
    }
}

# ── 2. Azure state file ──────────────────────────────────────────────
$stateFile = Join-Path (Resolve-Path $StateFilePath) ".devlake-azure.json"
if (Test-Path $stateFile) {
    Write-Info "Found Azure state file: $stateFile" "Yellow"
    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        $backendUrl = $state.endpoints.backend.TrimEnd('/')
        $grafanaUrl = $state.endpoints.grafana

        Write-Info "  Testing $backendUrl ..." "Gray"
        if (Test-DevLakeEndpoint $backendUrl) {
            Write-Info "  Connected to Azure deployment!" "Green"
            return [PSCustomObject]@{
                Url        = $backendUrl
                Source     = "statefile"
                GrafanaUrl = $grafanaUrl
            }
        }
        else {
            Write-Info "  Azure endpoint not reachable. Trying local fallbacks..." "Yellow"
        }
    }
    catch {
        Write-Info "  Could not parse state file. Trying local fallbacks..." "Yellow"
    }
}

# ── 3. Local state file ──────────────────────────────────────────────
$localStateFile = Join-Path (Resolve-Path $StateFilePath) ".devlake-local.json"
if (Test-Path $localStateFile) {
    Write-Info "Found local state file: $localStateFile" "Yellow"
    try {
        $localState = Get-Content $localStateFile -Raw | ConvertFrom-Json
        $backendUrl = $localState.endpoints.backend.TrimEnd('/')
        $grafanaUrl = $localState.endpoints.grafana

        Write-Info "  Testing $backendUrl ..." "Gray"
        if (Test-DevLakeEndpoint $backendUrl) {
            Write-Info "  Connected to local deployment!" "Green"
            return [PSCustomObject]@{
                Url        = $backendUrl
                Source     = "statefile"
                GrafanaUrl = $grafanaUrl
            }
        }
        else {
            Write-Info "  Local state endpoint not reachable. Trying well-known ports..." "Yellow"
        }
    }
    catch {
        Write-Info "  Could not parse local state file. Trying well-known ports..." "Yellow"
    }
}

# ── 4. Well-known local ports ────────────────────────────────────────
$localPorts = @(
    @{ Url = "http://localhost:8080"; Grafana = "http://localhost:3002"; Desc = "default Docker Compose" },
    @{ Url = "http://localhost:8085"; Grafana = "http://localhost:3004"; Desc = "devlake-demo port mapping" }
)

foreach ($candidate in $localPorts) {
    Write-Info "  Trying $($candidate.Url) ($($candidate.Desc))..." "Gray"
    if (Test-DevLakeEndpoint $candidate.Url) {
        Write-Info "  Connected to local DevLake on $($candidate.Url)!" "Green"
        return [PSCustomObject]@{
            Url        = $candidate.Url
            Source     = "localhost"
            GrafanaUrl = $candidate.Grafana
        }
    }
}

# ── 5. Could not auto-detect ─────────────────────────────────────────
Write-Host "`nCould not auto-detect a running DevLake instance." -ForegroundColor Yellow
Write-Host "Checked:" -ForegroundColor Gray
Write-Host "  • .devlake-azure.json state file" -ForegroundColor Gray
Write-Host "  • .devlake-local.json state file" -ForegroundColor Gray
Write-Host "  • http://localhost:8080 (default)" -ForegroundColor Gray
Write-Host "  • http://localhost:8085 (devlake-demo)" -ForegroundColor Gray
Write-Host ""

$userUrl = Read-Host "Enter your DevLake API URL (e.g., http://myhost:8080)"
if (-not $userUrl) {
    Write-Error "No URL provided. Cannot continue."
    exit 1
}

$userUrl = $userUrl.TrimEnd('/')
Write-Info "Testing $userUrl ..." "Yellow"
if (Test-DevLakeEndpoint $userUrl) {
    Write-Info "  Connected!" "Green"
    return [PSCustomObject]@{
        Url        = $userUrl
        Source     = "user"
        GrafanaUrl = $null
    }
}
else {
    Write-Error "Cannot reach DevLake at $userUrl/ping. Ensure DevLake is running."
    exit 1
}
