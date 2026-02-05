---
name: deploy-devlake
description: Deploy Apache DevLake to Azure or run locally with Docker. Supports Official release images or Custom builds from source. Use when deploying DevLake, creating Azure resources for DevLake, setting up local DevLake, or troubleshooting DevLake deployments. Trigger phrases include "deploy devlake", "set up devlake", "devlake azure", "devlake local", "install devlake".
---

# Deploy DevLake

Deploy Apache DevLake with two paths: **Official** (local or Azure) or **Custom** (build from source → local or Azure).

## Deployment Paths

```
═══════════════════════════════════════════════════════════════
              DEVLAKE DEPLOYMENT - SELECT PATH
═══════════════════════════════════════════════════════════════
1️⃣  Official Apache DevLake (latest release, official images)
    a) Local Docker - quick setup on your machine
    b) Deploy to Azure - ACI containers with managed MySQL

2️⃣  Custom DevLake (build from source)
    Step 1: Choose source
      a) Clone a remote fork (e.g., ewega/incubator-devlake)
      b) Use a local repository path
    Step 2: Choose target
      1) Local Docker - build & run locally
      2) Deploy to Azure - push to ACR, deploy to ACI

☁️  Cloud support: Azure only (AWS/GCP coming soon)
═══════════════════════════════════════════════════════════════
```

## Prerequisites

| Deployment | Requirements |
|------------|--------------|
| Local Docker | Docker installed and running |
| Azure | Azure CLI logged in (`az account show`), Docker, Active subscription |

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
.\azure\deploy.ps1 -ResourceGroupName "devlake-rg" -Location "eastus" -RepoUrl "https://github.com/ewega/incubator-devlake"
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

## Reference Documentation

| File | Content |
|------|---------|
| [environment-variables.md](references/environment-variables.md) | Required env vars & DB_URL format |
| [troubleshooting.md](references/troubleshooting.md) | Common issues & fixes |
| [cleanup.md](references/cleanup.md) | Teardown and resource deletion |

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

## State File (Azure)

Azure deployments create `.devlake-azure.json` in the current directory containing:
- Resource names and IDs
- Endpoints
- Secrets (for reference)

Use for tracking deployments and cleanup. Add to `.gitignore`.

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
