# DevLake API Reference

Quick reference for the DevLake REST API endpoints used by the configuration scripts.

## Base URL

- **Local Docker (default):** `http://localhost:8080`
- **Local Docker (devlake-demo):** `http://localhost:8085`
- **Azure deployment:** Found in `.devlake-azure.json` → `endpoints.backend`

## Authentication

The standard API (`/plugins/...`, `/blueprints/...`, `/projects/...`) requires **no authentication** by default. API keys are only enforced on the `/rest/...` prefix.

---

## Health & Status

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/ping` | Liveness check — returns `"pong"` |
| `GET` | `/ready` | Readiness check |
| `GET` | `/health` | Health status |
| `GET` | `/version` | Backend version info |
| `GET` | `/proceed-db-migration` | Trigger pending DB migrations |

---

## Connections

All plugin connections follow the same pattern: `/plugins/<pluginName>/connections`

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/plugins/<plugin>/test` | Test connection payload (before saving) |
| `POST` | `/plugins/<plugin>/connections` | Create connection |
| `GET` | `/plugins/<plugin>/connections` | List all connections |
| `GET` | `/plugins/<plugin>/connections/:id` | Get single connection |
| `PATCH` | `/plugins/<plugin>/connections/:id` | Update connection |
| `DELETE` | `/plugins/<plugin>/connections/:id` | Delete connection |
| `POST` | `/plugins/<plugin>/connections/:id/test` | Test saved connection |

### GitHub Connection Payload

```json
{
  "name": "my-github",
  "endpoint": "https://api.github.com/",
  "authMethod": "AccessToken",
  "token": "ghp_xxxx",
  "enableGraphql": true,
  "rateLimitPerHour": 12000,
  "tokenExpiresAt": "2028-01-01T00:00:00Z",
  "refreshTokenExpiresAt": "2028-01-01T00:00:00Z"
}
```

**Required PAT scopes:** `repo`, `read:org`, `read:user`

### GitHub Copilot Connection Payload

```json
{
  "name": "my-copilot",
  "endpoint": "https://api.github.com/",
  "authMethod": "AccessToken",
  "token": "ghp_xxxx",
  "organization": "my-org",
  "rateLimitPerHour": 5000,
  "tokenExpiresAt": "2028-01-01T00:00:00Z",
  "refreshTokenExpiresAt": "2028-01-01T00:00:00Z"
}
```

**Required PAT scopes:** `copilot`, `manage_billing:copilot`, `read:org`

Optional field: `"enterprise": "my-enterprise"` for enterprise-level metrics.

---

## Scopes

Scopes represent what data to collect (repos, orgs, etc.).

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `PUT` | `/plugins/<plugin>/connections/:id/scopes` | Create/update scopes (batch) |
| `GET` | `/plugins/<plugin>/connections/:id/scopes` | List scopes |
| `GET` | `/plugins/<plugin>/connections/:id/scopes/:scopeId` | Get single scope |
| `PATCH` | `/plugins/<plugin>/connections/:id/scopes/:scopeId` | Update scope |
| `DELETE` | `/plugins/<plugin>/connections/:id/scopes/:scopeId` | Delete scope |
| `GET` | `/plugins/<plugin>/connections/:id/remote-scopes` | Browse available scopes |
| `GET` | `/plugins/<plugin>/connections/:id/search-remote-scopes` | Search available scopes |

### GitHub Repo Scope Payload

```json
{
  "data": [
    {
      "githubId": 12345678,
      "connectionId": 1,
      "name": "my-repo",
      "fullName": "my-org/my-repo",
      "htmlUrl": "https://github.com/my-org/my-repo",
      "cloneUrl": "https://github.com/my-org/my-repo.git",
      "scopeConfigId": 1
    }
  ]
}
```

`githubId` is the numeric GitHub repository ID (from `gh api repos/owner/repo --jq .id`).

### Copilot Org Scope Payload

```json
{
  "data": [
    {
      "id": "my-org",
      "connectionId": 1,
      "organization": "my-org",
      "name": "my-org",
      "fullName": "my-org"
    }
  ]
}
```

---

## Scope Configs

Control how collected data is transformed (e.g., DORA patterns).

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/plugins/<plugin>/connections/:id/scope-configs` | Create scope config |
| `GET` | `/plugins/<plugin>/connections/:id/scope-configs` | List scope configs |
| `PATCH` | `/plugins/<plugin>/connections/:id/scope-configs/:id` | Update scope config |

### GitHub DORA Scope Config

```json
{
  "name": "dora-config",
  "connectionId": 1,
  "deploymentPattern": "(?i)deploy",
  "productionPattern": "(?i)prod",
  "issueTypeIncident": "incident",
  "refdiff": {
    "tagsPattern": ".*",
    "tagsLimit": 10,
    "tagsOrder": "reverse semver"
  }
}
```

| Field | Purpose |
|-------|---------|
| `deploymentPattern` | Regex matching CI/CD workflow names that count as deployments |
| `productionPattern` | Regex matching environment names that count as production |
| `issueTypeIncident` | Issue label that marks incidents (for Change Failure Rate / MTTR) |

---

## Projects & Blueprints

A **project** auto-creates a **blueprint** (the scheduled data-collection recipe).

### Project Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/projects` | Create project (returns blueprint) |
| `GET` | `/projects` | List projects |
| `GET` | `/projects/:name` | Get project by name |
| `PATCH` | `/projects/:name` | Update project |

### Project Payload

```json
{
  "name": "My Project",
  "description": "DORA + Copilot metrics",
  "metrics": [
    { "pluginName": "dora", "enable": true }
  ]
}
```

### Blueprint Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/blueprints` | List blueprints |
| `GET` | `/blueprints/:id` | Get blueprint |
| `PATCH` | `/blueprints/:id` | Update blueprint (add connections & scopes) |
| `POST` | `/blueprints/:id/trigger` | Trigger data collection |

### Blueprint PATCH Payload

```json
{
  "connections": [
    {
      "pluginName": "github",
      "connectionId": 1,
      "scopes": [
        { "scopeId": "12345678", "scopeName": "my-org/my-repo" }
      ]
    },
    {
      "pluginName": "gh-copilot",
      "connectionId": 1,
      "scopes": [
        { "scopeId": "my-org", "scopeName": "my-org" }
      ]
    }
  ],
  "enable": true,
  "cronConfig": "0 0 * * *",
  "timeAfter": "2025-01-01T00:00:00Z"
}
```

**Note:** `scopeId` for GitHub repos is the numeric GitHub ID (as a string). For Copilot, it's the org slug.

---

## Pipelines

Pipelines are triggered by blueprints and represent a single data collection run.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/pipelines` | List pipelines |
| `GET` | `/pipelines/:id` | Get pipeline status |
| `POST` | `/pipelines/:id/rerun` | Rerun a pipeline |

### Pipeline Status Values

| Status | Meaning |
|--------|---------|
| `TASK_CREATED` | Pipeline created, not started |
| `TASK_RUNNING` | Currently collecting data |
| `TASK_COMPLETED` | Finished successfully |
| `TASK_FAILED` | Failed (check logs) |
| `TASK_CANCELLED` | Cancelled by user |

---

## Typical Setup Flow

```
1. POST /plugins/github/test           → validate credentials
2. POST /plugins/github/connections     → create connection (returns ID)
3. POST /plugins/gh-copilot/connections → create copilot connection
4. POST /plugins/github/connections/1/scope-configs → DORA config
5. PUT  /plugins/github/connections/1/scopes        → add repos
6. PUT  /plugins/gh-copilot/connections/1/scopes    → add org
7. POST /projects                       → create project (returns blueprint ID)
8. PATCH /blueprints/:id                → link connections+scopes
9. POST /blueprints/:id/trigger         → start first sync
10. GET  /pipelines/:id                 → monitor progress
```
