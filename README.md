# copilot-plugins

GitHub Copilot CLI plugins from DevExpGBB ✨

Extend GitHub Copilot CLI with deployment workflows and automation tools.

## 🔌 Available Plugins

### devlake-deploy

Deploy [Apache DevLake](https://devlake.apache.org/) to Azure or run locally with Docker.

**Features:**
- Official images (latest release) or custom builds from source
- Local Docker deployment with one command
- Azure deployment with managed MySQL, Key Vault, Container Instances
- Automated infrastructure provisioning via Bicep

**Supported Targets:**
- ✅ Local Docker
- ✅ Azure (ACI + MySQL Flexible Server)
- 🔜 AWS (coming soon)
- 🔜 GCP (coming soon)

## 📦 Installation

### Install from this repository

```bash
copilot plugin install DevExpGBB/copilot-plugins:plugins/devlake-deploy
```

### Or install directly

```bash
copilot plugin install DevExpGBB/copilot-plugins
```

## 🚀 Quick Start

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

## 📋 Prerequisites

| Deployment | Requirements |
|------------|--------------|
| Local Docker | Docker Desktop installed and running |
| Azure | Azure CLI (`az login`), Docker, Active Azure subscription |

## 🗂️ Plugin Structure

```
plugins/
└── devlake-deploy/
    └── skills/
        └── deploy-devlake/
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

## 💰 Cost Estimates (Azure)

| Path | Monthly Cost | Resources |
|------|-------------|-----------|
| Official Images | ~$30-50 | MySQL B1ms + 3 containers + Key Vault |
| Custom Build | ~$50-75 | MySQL B1ms + 3 containers + ACR Basic + Key Vault |

## 🤝 Contributing

Contributions welcome! Please read our contributing guidelines before submitting PRs.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.
