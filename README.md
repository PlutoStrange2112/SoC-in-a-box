# SoC-in-a-Box

**Ghost Tech Security Solutions**

A production-ready, environment-driven installer suite for deploying a complete Security Operations Center (SOC) stack.

---

## 📦 What's Included

### Server Components
- **Wazuh Manager** - SIEM, threat detection, and compliance
- **Wazuh Indexer** - Log storage and search (OpenSearch-based)
- **Wazuh Dashboard** - Visualization and management UI
- **Zabbix Server** - Infrastructure monitoring
- **MariaDB/PostgreSQL** - Database backend
- **Nginx** - Reverse proxy with TLS

### Client Agents
- **Wazuh Agent** - Endpoint detection and response
- **Zabbix Agent** - Performance and availability monitoring
- **ClamAV** - Antivirus with scheduled scanning

---

## 🚀 Quick Start

### Server Installation

```bash
# 1. Copy and configure environment
cd server
cp .env.template .env
nano .env  # Edit configuration

# 2. Run installer as root
sudo ./install.sh

# 3. (Optional) Preview without making changes
sudo ./install.sh --dry-run
```

### Client Installation

```bash
# 1. Copy and configure environment
cd client
cp .env.template .env
nano .env  # Set SOC_IP and agent settings

# 2. Run installer as root
sudo ./install.sh

# 3. (Optional) Preview without making changes
sudo ./install.sh --dry-run
```

---

## 📁 Directory Structure

```
SoCInaBox/
├── README.md
├── client/
│   ├── .env.template       # Client configuration
│   ├── install.sh          # Main installer
│   ├── uninstall.sh        # Removal script
│   └── agents/
│       ├── wazuh/install.sh
│       ├── zabbix/install.sh
│       └── clamav/install.sh
└── server/
    ├── .env.template       # Server configuration
    ├── install.sh          # Main installer
    ├── uninstall.sh        # Removal script
    └── components/
        ├── database/install.sh
        ├── wazuh-manager/install.sh
        ├── zabbix-server/install.sh
        └── nginx/install.sh
```

---

## ⚙️ Configuration

### Server `.env` Key Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SERVER_HOSTNAME` | Server hostname | `soc-box-01` |
| `SERVER_DOMAIN` | Domain for TLS | `soc.example.com` |
| `DB_ROOT_PASSWORD` | Database root password | `<secure password>` |
| `WAZUH_ENABLED` | Install Wazuh Manager | `true` |
| `ZABBIX_ENABLED` | Install Zabbix Server | `true` |
| `ENABLE_TLS` | Enable HTTPS with TLS | `true` |

### Client `.env` Key Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SITE_NAME` | Site identifier | `site_alpha` |
| `SOC_IP` | SOC server IP address | `10.50.0.10` |
| `WAZUH_ENABLED` | Install Wazuh agent | `true` |
| `ZABBIX_ENABLED` | Install Zabbix agent | `true` |
| `CLAMAV_ENABLED` | Install ClamAV | `true` |
| `CLAMAV_SCHEDULE` | Scan schedule (cron) | `0 2 * * *` |

---

## 🔧 Command Line Options

Both installers support:

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-d, --dry-run` | Preview without changes |
| `-v, --verbose` | Verbose output |
| `-e, --env FILE` | Use custom .env file |
| `--version` | Show version |

---

## 🌐 Bulk Deployment

### SSH Fan-Out (Recommended)

```bash
# Using pssh
pssh -h hosts.txt -l root -i 'cd /opt/soc && ./install.sh'

# Using Ansible
ansible all -m script -a "/opt/soc/client/install.sh"
```

### USB/Air-Gapped Sites

1. Copy `client/` folder to USB drive
2. Configure `.env` for the site
3. Run `sudo ./install.sh` on target

---

## 📊 Post-Installation

### Access URLs (Server)

| Service | URL |
|---------|-----|
| Wazuh Dashboard | `https://<server>:5601` |
| Zabbix Frontend | `https://<server>/zabbix` |

### Verify Agent Registration

```bash
# On server - check registered Wazuh agents
/var/ossec/bin/agent_control -l

# Check Zabbix agent status
systemctl status zabbix-agent
```

---

## 🔄 Uninstall

```bash
# Server
sudo ./server/uninstall.sh

# Client
sudo ./client/uninstall.sh

# Selective removal
sudo ./client/uninstall.sh --wazuh
```

---

## 📋 Supported Operating Systems

- **Debian** 11, 12
- **Ubuntu** 20.04, 22.04, 24.04
- **RHEL/CentOS/Rocky** 8, 9
- **AlmaLinux** 8, 9

---

## ⚠️ Important Notes

1. **Change default passwords** before production use
2. **Backup `.env` files** - they contain sensitive credentials
3. **Test with `--dry-run`** before production deployment
4. **Keep installers versioned** with your site configurations

---

## 📞 Support

Ghost Tech Security Solutions  
https://www.ghosttechconsulting.com

---

*Built for repeatability, isolation, and control.*


