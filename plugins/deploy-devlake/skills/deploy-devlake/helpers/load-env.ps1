<#
.SYNOPSIS
    Load key-value pairs from a .devlake.env file.

.DESCRIPTION
    Reads a .devlake.env (or custom-named) file and returns a hashtable of
    KEY=VALUE pairs. Ignores blank lines and lines starting with #.

    This function does NOT set environment variables — it returns a scoped
    hashtable so secrets are not leaked into the process environment.

    Used by configure-connections.ps1 to resolve PATs without requiring them
    on the command line or in chat history.

.PARAMETER EnvFile
    Path to the env file. Defaults to ".devlake.env" in the current directory.

.OUTPUTS
    Hashtable of key-value pairs (empty hashtable if file does not exist).

.EXAMPLE
    $secrets = .\helpers\load-env.ps1
    $token = $secrets["GITHUB_TOKEN"]

.EXAMPLE
    $secrets = .\helpers\load-env.ps1 -EnvFile "C:\path\to\.devlake.env"
#>

param(
    [string]$EnvFile = (Join-Path (Get-Location) ".devlake.env")
)

$result = @{}

if (-not (Test-Path $EnvFile)) {
    return $result
}

$lines = Get-Content $EnvFile -Encoding UTF8

foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Skip blank lines and comments
    if (-not $trimmed -or $trimmed.StartsWith('#')) {
        continue
    }

    # Parse KEY=VALUE (split only on first '=')
    $eqIndex = $trimmed.IndexOf('=')
    if ($eqIndex -le 0) {
        continue
    }

    $key = $trimmed.Substring(0, $eqIndex).Trim()
    $value = $trimmed.Substring($eqIndex + 1).Trim()

    # Strip surrounding quotes if present
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    # Only store non-empty values
    if ($value) {
        $result[$key] = $value
    }
}

return $result
