---
name: deploy-devlake
description: Deploy and configure Apache DevLake. Supports deployment to Azure or local Docker, plus post-deploy configuration of GitHub connections, Copilot metrics, DORA scopes, and projects. Trigger phrases include "deploy devlake", "set up devlake", "configure devlake", "devlake connections", "devlake scopes", "devlake azure", "devlake local", "install devlake".
---

# Deploy & Configure DevLake

Full lifecycle setup for Apache DevLake: deploy, configure connections, add scopes, create a project, and trigger the first data sync.

## First Interaction — Explain Phases

When a user invokes this skill for the first time, **always start by explaining the three phases** before doing anything else:

> DevLake setup has three phases:
>
> **Phase 1 — Deploy:** Spin up a DevLake instance (local Docker or Azure). If you already have DevLake running, you can skip this.
>
> **Phase 2 — Configure Connections:** Create GitHub and GitHub Copilot connections so DevLake can pull your data.
>
> **Phase 3 — Configure Scopes & Project:** Select which repos to track, set up DORA metric patterns, create a project, and trigger the first data sync.
>
> You can run these individually or combined:
> - **Full Setup** = Phases 1 + 2 + 3 (deploy and configure everything from scratch)
> - **Full Configuration** = Phases 2 + 3 (configure a DevLake instance that's already running)

Then ask:
> "Would you like to:
> 1. **Full Setup** — Deploy DevLake and configure it end-to-end (Phases 1→2→3)
> 2. **Full Configuration** — Configure an already-running DevLake instance (Phases 2→3)
> 3. **Deploy only** — Just deploy DevLake (Phase 1)
> 4. **Configure connections only** — Phase 2
> 5. **Configure scopes only** — Phase 3"

Branch to the appropriate section based on their answer. If the user's original message already makes their intent clear (e.g., "deploy devlake to Azure"), skip the question and go directly to the relevant phase.

## Setup Phases

```
═══════════════════════════════════════════════════════════════
              DEVLAKE SETUP - SELECT PHASE
═══════════════════════════════════════════════════════════════

  PHASE 1 — Deploy DevLake
  ────────────────────────
  1️⃣  Official Apache DevLake (latest release images)
      a) Local Docker
      b) Deploy to Azure

  2️⃣  Custom DevLake (build from source)
      a) Clone fork → Local Docker
      b) Clone fork → Deploy to Azure

  PHASE 2 — Configure Connections
  ────────────────────────────────
  3️⃣  Create GitHub + Copilot connections
      • Reads PAT from .devlake.env file (secure, no chat exposure)
      • Validates PAT scopes against GitHub API
      • Tests connections before saving

  PHASE 3 — Configure Scopes & Project
  ─────────────────────────────────────
  4️⃣  Add repos, create DORA config, build project
      • Browse/select repos via gh CLI
      • Create DORA scope config (deploy/prod patterns)
      • Create project + blueprint
      • Trigger first data sync

  FULL CONFIGURATION — Phases 2 + 3 combined
  ─────────────────────────────────────────────
  5️⃣  End-to-end post-deployment configuration in one flow

  FULL SETUP — Phases 1 + 2 + 3
  ──────────────────────────────
  6️⃣  Deploy + configure everything from scratch

☁️  Cloud support: Azure only (AWS/GCP coming soon)
═══════════════════════════════════════════════════════════════
```

## Prerequisites

| Phase | Requirements |
|-------|--------------|
| Phase 1 — Local Docker | Docker installed and running |
| Phase 1 — Azure | Azure CLI logged in (`az account show`), Docker, Active subscription |
| Phase 2 — Connections | Running DevLake instance, GitHub PAT with scopes: `repo`, `read:org`, `read:user`, `copilot`, `manage_billing:copilot` |
| Phase 3 — Scopes | Connections configured (Phase 2), `gh` CLI authenticated (for repo lookups) |

---

## Path 1a: Official DevLake → Local Docker

Quick local setup using official release images.

```powershell
# Download and set up official DevLake
.\local\deploy-local.ps1

# Or specify a target directory and version
.\local\deploy-local.ps1 -TargetDirectory "C:\devlake" -Version "v1.0.2"

# Then start DevLake
cd C:\devlake
docker compose up -d
```

**Endpoints:**
- Config UI: http://localhost:4000
- Grafana: http://localhost:3002 (admin/admin)
- Backend API: http://localhost:8080

---

## Path 1b: Official DevLake → Azure

Deploy official release images to Azure. No build required, no ACR needed.

```powershell
.\azure\deploy.ps1 -ResourceGroupName "devlake-rg" -Location "eastus" -UseOfficialImages
```

**Cost:** ~$30-50/month (no ACR)

---

## Path 2-Local: Custom Build → Local Docker

Build from source and run locally.

### Clone (if using remote fork)
```powershell
git clone https://github.com/<owner>/<repo>.git
cd <repo>
```

### Build Images
```powershell
cd backend; docker build -t devlake-backend:local .
cd ../config-ui; docker build -t devlake-config-ui:local .
cd ../grafana; docker build -t devlake-dashboard:local .
```

### Run
```powershell
docker compose -f docker-compose-dev.yml up -d
```

**Endpoints:** Same as Path 1a.

---

## Path 2-Azure: Custom Build → Azure

Build from source and deploy to Azure with ACR.

### From Local Repository
```powershell
.\azure\deploy.ps1 -ResourceGroupName "devlake-rg" -Location "eastus"
```

### From Remote Fork
```powershell
.\azure\deploy.ps1 -ResourceGroupName "devlake-rg" -Location "eastus" -RepoUrl "https://github.com/DevExpGBB/incubator-devlake"
```

**Cost:** ~$50-75/month (includes ACR)

---

## Script Reference

| Script | Purpose |
|--------|---------|
| `local/deploy-local.ps1` | Download official docker-compose and set up locally |
| `azure/deploy.ps1` | Deploy to Azure (official or custom images) |
| `azure/cleanup.ps1` | Delete Azure resources using state file |
| `azure/main.bicep` | Bicep template for custom builds (with ACR) |
| `azure/main-official.bicep` | Bicep template for official images (no ACR) |
| `configure/configure-connections.ps1` | Phase 2: Create & test GitHub + Copilot connections |
| `configure/configure-scopes.ps1` | Phase 3: Add repos, create project, trigger sync |
| `configure/full-configuration.ps1` | Phases 2+3 combined in one flow |
| `helpers/discover-devlake.ps1` | Auto-detect running DevLake instance URL |
| `helpers/load-env.ps1` | Load secrets from `.devlake.env` file |

## Reference Documentation

| File | Content |
|------|---------|
| [environment-variables.md](references/environment-variables.md) | Required env vars & DB_URL format |
| [troubleshooting.md](references/troubleshooting.md) | Common issues & fixes |
| [cleanup.md](references/cleanup.md) | Teardown and resource deletion |
| [api-reference.md](references/api-reference.md) | DevLake REST API endpoints & payloads |

---

## Critical Requirements (Azure)

| Requirement | Why |
|-------------|-----|
| `parseTime=True&loc=UTC&tls=true` in DB_URL | Datetime fields fail without it |
| `ENCRYPTION_SECRET` (32 chars) | Backend panics without it |
| Key Vault RBAC role | "Forbidden" when storing secrets |
| Start MySQL after creation | Azure auto-stops Burstable tier |

See [references/environment-variables.md](references/environment-variables.md) for details.

---

## Phase 2: Configure Connections

Create GitHub and GitHub Copilot connections against a running DevLake instance.

### Agent Q&A Flow for Phase 2

> ⚠️ **Security: NEVER accept a PAT pasted directly into this conversation.**
> Chat history is persisted and tokens would be permanently exposed.
> Always use the `.devlake.env` file workflow described below.

When the user asks to configure connections, follow this conversation flow:

1. **Check prerequisites:**
   - Verify DevLake is reachable: run `.\helpers\discover-devlake.ps1` or ask for the URL

2. **Ask the user:**
   - "What is your GitHub organization slug?" (e.g., `octodemo`)
   - "Do you also want to configure GitHub Copilot metrics?" (default: yes)
   - "Do you have an enterprise slug for enterprise-level Copilot metrics?" (optional)

3. **Create the `.devlake.env` secrets file** with the appropriate template based on which connections the user wants. Use the agent's file creation capability to create the file in the working directory, then open it for the user:

   For GitHub + Copilot (both connections use the same token):
   ```env
   # DevLake Connection Secrets
   # Paste your GitHub PAT below, then save this file.
   # Required scopes: repo, read:org, read:user, copilot, manage_billing:copilot
   # This file will be deleted automatically after connections are created.

   GITHUB_TOKEN=
   ```

   For GitHub only:
   ```env
   # DevLake Connection Secrets
   # Paste your GitHub PAT below, then save this file.
   # Required scopes: repo, read:org, read:user
   # This file will be deleted automatically after connections are created.

   GITHUB_TOKEN=
   ```

   Tell the user:
   > "I've created a `.devlake.env` file. Please paste your GitHub PAT after `GITHUB_TOKEN=`, save the file, and let me know when you're ready."

4. **Wait for user confirmation** that they've saved the file.

5. **Run the script** — the token is read from the file, never from the command line:

```powershell
# Both GitHub + Copilot (default)
.\configure\configure-connections.ps1 -Organization "octodemo"

# GitHub only (no Copilot)
.\configure\configure-connections.ps1 -Organization "octodemo" -ConnectionType "github"

# With enterprise Copilot
.\configure\configure-connections.ps1 -Organization "octodemo" -Enterprise "my-enterprise"

# Against a specific DevLake URL
.\configure\configure-connections.ps1 -Organization "octodemo" -DevLakeUrl "http://myhost:8080"
```

6. **Confirm cleanup** — after successful connection creation, the script automatically deletes `.devlake.env`. Report this to the user:
   > "Connections created successfully. The `.devlake.env` file has been deleted — your PAT is now stored encrypted in DevLake's database."

### What the Script Does

1. Auto-discovers the DevLake API URL (state file → localhost fallback → ask user)
2. Resolves GitHub token (`.devlake.env` → `$env:GITHUB_TOKEN` → masked prompt)
3. Validates token scopes against GitHub API — warns about missing scopes
4. Tests connection payload via `POST /plugins/github/test` before creating
5. Creates GitHub connection via `POST /plugins/github/connections`
6. Creates Copilot connection via `POST /plugins/gh-copilot/connections`
7. Tests saved connections via `POST /plugins/<plugin>/connections/:id/test`
8. Saves connection IDs to state file for Phase 3
9. Deletes `.devlake.env` (tokens now stored encrypted in DevLake)

### Required PAT Scopes

| Scope | Purpose | Required For |
|-------|---------|-------------|
| `repo` | Repository data access | GitHub connection |
| `read:org` | Organization membership | Both |
| `read:user` | User profile (GraphQL) | GitHub connection |
| `copilot` | Copilot usage metrics | Copilot connection |
| `manage_billing:copilot` | Copilot seats/billing | Copilot connection |

### Idempotency

The script checks for existing connections by name before creating. Running it twice is safe.

---

## Phase 3: Configure Scopes & Project

Add repository scopes, create a DORA configuration, set up a project with a blueprint, and trigger the first data sync.

### Agent Q&A Flow for Phase 3

When the user asks to configure scopes or create a project, follow this flow:

1. **Check prerequisites:**
   - Verify DevLake is reachable
   - Verify connections exist (Phase 2 completed)
   - Verify `gh` CLI for repo lookups

2. **Ask the user:**
   - "Which repositories should I track for DORA metrics? You can:
     - **Paste them** — comma-separated list of `owner/repo` names
     - **Provide a file** — path to a `.csv` or `.txt` file with one `owner/repo` per line
     - **Browse** — I'll list your org's repos via `gh` CLI and you can pick"
   - "What regex identifies your deployment CI/CD workflows?" (default: `(?i)deploy`)
   - "What regex identifies your production environment?" (default: `(?i)prod`)
   - "What issue label marks incidents?" (default: `incident`)
   - "What should the project be named?" (default: org name)
   - "Should I trigger the first data sync now?" (default: yes)

3. **Run the script:**

```powershell
# Basic: specify repos directly (paste or comma-separated)
.\configure\configure-scopes.ps1 -Organization "octodemo" -Repos "octodemo/app1","octodemo/app2"

# From a file (CSV or TXT, one owner/repo per line)
.\configure\configure-scopes.ps1 -Organization "octodemo" -ReposFile ".\my-repos.csv"

# Interactive: let user pick from org's repos
.\configure\configure-scopes.ps1 -Organization "octodemo"

# Custom DORA patterns
.\configure\configure-scopes.ps1 -Organization "octodemo" -Repos "octodemo/app1" `
    -DeploymentPattern "(?i)(deploy|release)" `
    -ProductionPattern "(?i)(prod|production)" `
    -IncidentLabel "bug/incident"

# Custom project name
.\configure\configure-scopes.ps1 -Organization "octodemo" -ProjectName "My DORA Dashboard"

# Skip Copilot scope
.\configure\configure-scopes.ps1 -Organization "octodemo" -Repos "octodemo/app1" -SkipCopilot

# Skip triggering sync
.\configure\configure-scopes.ps1 -Organization "octodemo" -Repos "octodemo/app1" -SkipSync
```

### What the Script Does

1. Auto-discovers DevLake API URL and resolves connection IDs (from state file or API)
2. Looks up repo details via `gh api repos/<owner>/<repo>` to get GitHub numeric IDs
3. Creates a DORA scope config via `POST /plugins/github/connections/:id/scope-configs`
4. Adds repo scopes via `PUT /plugins/github/connections/:id/scopes`
5. Adds Copilot org scope via `PUT /plugins/gh-copilot/connections/:id/scopes`
6. Creates a DevLake project via `POST /projects` (auto-creates blueprint)
7. Configures the blueprint with connection scopes via `PATCH /blueprints/:id`
8. Triggers the first sync via `POST /blueprints/:id/trigger`
9. Monitors pipeline progress for up to 5 minutes

### DORA Scope Config Explained

| Field | Default | Purpose |
|-------|---------|---------|
| `deploymentPattern` | `(?i)deploy` | Regex matching GitHub Actions workflow names that represent deployments |
| `productionPattern` | `(?i)prod` | Regex matching environment names for production deploys |
| `issueTypeIncident` | `incident` | Issue label that identifies incidents for Change Failure Rate and MTTR |

Users should customize these to match their CI/CD naming conventions.

---

## Full Configuration (Phases 2 + 3)

Run connections and scopes configuration in a single flow, ideal for users who already have DevLake deployed and running.

```powershell
# End-to-end with interactive repo selection
.\configure\full-configuration.ps1 -Organization "octodemo"

# End-to-end with repos specified
.\configure\full-configuration.ps1 -Organization "octodemo" -Repos "octodemo/app1","octodemo/app2"

# End-to-end with repos from a file
.\configure\full-configuration.ps1 -Organization "octodemo" -ReposFile ".\my-repos.csv"

# With custom .devlake.env location
.\configure\full-configuration.ps1 -Organization "octodemo" -EnvFile "C:\secrets\.devlake.env"

# With all options
.\configure\full-configuration.ps1 -Organization "octodemo" `
    -Repos "octodemo/app1" `
    -ProjectName "My DORA Project" `
    -Enterprise "my-enterprise" `
    -DeploymentPattern "(?i)(deploy|release)"
```

### Agent Flow for Full Configuration

When a user says "configure DevLake" or chooses Full Configuration:

1. Ask: "Do you have DevLake running? I'll auto-detect it, or you can provide the URL."
2. Ask: "What's your GitHub organization?"
3. Create `.devlake.env` with `GITHUB_TOKEN=` placeholder, open it, and tell the user to paste their PAT and save.
4. Wait for user confirmation that the file is saved.
5. Ask: "Which repos should I track? You can paste a list, point me to a CSV/TXT file, or I can list your org's repos."
6. Ask: "Do you want Copilot metrics too?" (default: yes)
7. Run `.\configure\full-configuration.ps1` with their answers
8. Report results: connections created, `.devlake.env` deleted, repos added, sync status, Grafana URL

---

## Full Setup (Phases 1 + 2 + 3)

End-to-end: deploy a fresh DevLake instance and then configure it.

### Agent Flow for Full Setup

When a user says "set up DevLake from scratch" or chooses Full Setup:

1. Run **Phase 1** first — ask the user which deployment path (local Docker or Azure, official or custom) and execute the appropriate deploy script
2. Wait for DevLake to be healthy (poll `/ping`)
3. Then run **Full Configuration** (Phases 2 + 3) as described above

---

## API URL Discovery

The configuration scripts auto-detect the DevLake API URL in this order:

1. **Explicit parameter** (`-DevLakeUrl "http://..."`)
2. **Azure state file** (`.devlake-azure.json` → `endpoints.backend`)
3. **Local state file** (`.devlake-local.json` → `endpoints.backend`)
4. **Well-known ports** (`localhost:8080`, `localhost:8085`)
5. **Ask the user** (if all above fail)

The discovery helper is at `helpers/discover-devlake.ps1` and is called automatically by all configure scripts.

---

## State Files

| File | Created By | Contains |
|------|-----------|----------|
| `.devlake-azure.json` | `azure/deploy.ps1` | Azure resources, endpoints, secrets |
| `.devlake-local.json` | `configure/configure-connections.ps1` | Endpoints, connections (local deploys) |
| `.devlake.env` | Agent (Phase 2) | **Ephemeral** — PATs for connection creation. Auto-deleted after success. |

Both state files are updated by Phase 2 and Phase 3 scripts with connection IDs, project info, and timestamps. Add all to `.gitignore`.

---

## Cleanup

### Azure (using script)
```powershell
.\azure\cleanup.ps1
```

### Azure (manual)
```bash
az group delete --name <resource-group> --yes --no-wait
```

### Local Docker
```powershell
cd <devlake-directory>
docker compose down
```

---

## Cost Estimate

| Path | Monthly Cost | Includes |
|------|-------------|----------|
| Local Docker | Free | Local resources only |
| Official (Azure) | ~$30-50 | MySQL B1ms + 3 containers + Key Vault |
| Custom (Azure) | ~$50-75 | MySQL B1ms + 3 containers + ACR Basic + Key Vault |
