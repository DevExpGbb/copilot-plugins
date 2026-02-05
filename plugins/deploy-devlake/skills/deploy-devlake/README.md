# Deploy DevLake

GitHub Copilot CLI skill for deploying [Apache DevLake](https://devlake.apache.org/) to Azure or running locally with Docker.

## Features

- Official images (latest release) or custom builds from source
- Local Docker deployment with one command
- Azure deployment with managed MySQL, Key Vault, Container Instances
- Automated infrastructure provisioning via Bicep

## Supported Targets

- ✅ Local Docker
- ✅ Azure (ACI + MySQL Flexible Server)
- 🔜 AWS (coming soon)
- 🔜 GCP (coming soon)

## Installation

```bash
copilot plugin install DevExpGBB/copilot-plugins:plugins/deploy-devlake
```

## Quick Start

After installing, start a Copilot CLI session and ask:

```
Help me deploy DevLake
```

Or be specific:

```
Deploy DevLake to Azure using official images
```

```
Set up DevLake locally with Docker
```

## Prerequisites

| Deployment | Requirements |
|------------|--------------|
| Local Docker | Docker Desktop installed and running |
| Azure | Azure CLI (`az login`), Docker, Active Azure subscription |

## Skill Structure

```
deploy-devlake/
├── SKILL.md              # Main skill definition
├── azure/                # Azure deployment scripts + Bicep
│   ├── deploy.ps1
│   ├── cleanup.ps1
│   ├── main.bicep
│   └── main-official.bicep
├── local/                # Local Docker setup
│   └── deploy-local.ps1
└── references/           # Documentation
    ├── environment-variables.md
    ├── troubleshooting.md
    └── cleanup.md
```

## Cost Estimates (Azure)

| Path | Monthly Cost | Resources |
|------|-------------|-----------|
| Official Images | ~$30-50 | MySQL B1ms + 3 containers + Key Vault |
| Custom Build | ~$50-75 | MySQL B1ms + 3 containers + ACR Basic + Key Vault |

## License

MIT License - see [LICENSE](LICENSE) for details.
