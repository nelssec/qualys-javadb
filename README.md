# qualys-javadb

Scripts for managing Java DB in air-gapped and HPC environments for QScanner.

## Problem Statement

QScanner uses a Java database to identify Java packages during vulnerability scans. This database maps JAR file SHA1 hashes to Maven coordinates (GroupID, ArtifactID, Version), enabling precise identification of Java dependencies.

By default, QScanner downloads this database on first execution and periodically checks for updates. While convenient for workstation use, this behavior is problematic in controlled environments:

**Air-gapped and restricted networks**
Systems without internet access cannot download the database, causing scan failures or degraded Java package detection.

**High-performance computing (HPC) clusters**
Compute nodes typically lack external network access. When running parallel scan jobs, each node attempting to download the database creates unnecessary failures and delays.

**Ephemeral and containerized environments**
Short-lived containers or VMs that scan once and terminate waste resources re-downloading the database on every instantiation.

**Bandwidth and latency constraints**
Repeated downloads of the same database consume bandwidth and add latency to scan operations.

**Reproducible builds and security policies**
Organizations may require all external dependencies to be explicitly provisioned rather than fetched at runtime.

## Solution

Pre-stage the Java database once, then configure QScanner to use the local copy without attempting network operations. This repository provides the tooling to download, mirror, and deploy the database in a controlled manner.

## How It Works

The Java database is distributed as an OCI artifact (using the container image format for distribution). These scripts use [oras](https://oras.land/) (OCI Registry As Storage) to pull and push the artifact.

### Architecture

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  Public Registry    │     │  Internal Registry  │     │   Target Systems    │
│  (ghcr.io)          │────▶│  (your-registry)    │────▶│   (air-gapped)      │
│                     │     │                     │     │                     │
│  javadb.tar.gz      │     │  javadb.tar.gz      │     │  trivy-java.db      │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
        │                           │                           │
        │    mirror-java-db.sh      │     setup-java-db.sh      │
        └───────────────────────────┴───────────────────────────┘
```

### Workflow Options

**Direct installation** (internet-connected systems):
1. Run `setup-java-db.sh` to pull and extract the database
2. Database is placed in QScanner's cache directory
3. Run QScanner with `--skip-java-db-update=true`

**Mirrored installation** (air-gapped systems):
1. On an internet-connected machine, run `mirror-java-db.sh` to copy the artifact to your internal registry
2. On target systems, run `setup-java-db.sh` pointing to your internal registry
3. Run QScanner with `--skip-java-db-update=true`

**Shared filesystem** (HPC clusters):
1. Run `setup-java-db.sh` once to a shared filesystem location
2. Configure all compute nodes to use that location via `QSCANNER_CACHE_DIR`
3. Run QScanner with `--skip-java-db-update=true`

### Database Location

QScanner expects the database at: `~/.cache/qualys/qscanner/java-db/trivy-java.db`

The `--skip-java-db-update=true` flag prevents download attempts, and `--max-network-retries 0` ensures scans don't hang waiting for network timeouts.

## Requirements

- [oras CLI](https://oras.land/) - OCI Registry As Storage client
- Bash shell

### Installing oras

```bash
# macOS
brew install oras

# Linux amd64
VERSION="1.2.0"
curl -LO "https://github.com/oras-project/oras/releases/download/v${VERSION}/oras_${VERSION}_linux_amd64.tar.gz"
tar -zxf oras_${VERSION}_linux_amd64.tar.gz
sudo mv oras /usr/local/bin/
```

## Scripts

### setup-java-db.sh

Downloads and installs the Java DB to the local cache directory.

```bash
# Basic usage - downloads from default registry
./setup-java-db.sh

# Pull from internal mirror
./setup-java-db.sh -r your-registry.example.com/qualys/java-db

# Install to custom location (e.g., shared HPC filesystem)
./setup-java-db.sh -d /shared/qualys/java-db
```

Options:
- `-r, --registry URL` - OCI registry URL
- `-t, --tag TAG` - Image tag (default: 1)
- `-d, --dest DIR` - Destination directory

Environment variables:
- `JAVADB_REGISTRY` - Override default registry
- `JAVADB_TAG` - Override default tag
- `JAVADB_CACHE_DIR` - Override default cache directory

### mirror-java-db.sh

Mirrors the Java DB to an internal registry for air-gapped environments.

```bash
# Mirror to internal registry
./mirror-java-db.sh -d your-registry.example.com/qualys/java-db

# Mirror with different tag
./mirror-java-db.sh -d your-registry.example.com/java-db -t latest
```

Options:
- `-s, --source URL` - Source registry
- `-d, --dest URL` - Destination registry (required)
- `-t, --tag TAG` - Tag to use for both source and dest
- `--source-tag TAG` - Source tag if different
- `--dest-tag TAG` - Destination tag if different

### qscanner-env.sh

Helper script that sets up environment variables and displays recommended QScanner flags.

```bash
source ./qscanner-env.sh
```

## Usage with QScanner

After installing the Java DB, run QScanner with these flags to prevent network queries:

```bash
qscanner image <image> --skip-java-db-update=true --max-network-retries 0
```

### Recommended flags

| Flag | Description |
|------|-------------|
| `--skip-java-db-update=true` | Prevents java-db download attempts |
| `--max-network-retries 0` | Disables network retries |
| `--scan-timeout 5m` | Scan timeout (default: 5m) |

### Custom cache location

If you installed the Java DB to a non-default location:

```bash
export QSCANNER_CACHE_DIR="/path/to/cache"
qscanner image <image> --skip-java-db-update=true --max-network-retries 0
```

Or use the `--cache-dir` flag:

```bash
qscanner image <image> --cache-dir /path/to/cache --skip-java-db-update=true --max-network-retries 0
```

## Directory Structure

Default cache location: `~/.cache/qualys/qscanner/java-db`

```
~/.cache/qualys/qscanner/
└── java-db/
    └── trivy-java.db
```

## Workflow Examples

### Air-gapped deployment

1. On a machine with internet access, mirror the database:
   ```bash
   ./mirror-java-db.sh -d internal-registry.example.com/qualys/java-db
   ```

2. On the air-gapped machine, pull from the internal registry:
   ```bash
   ./setup-java-db.sh -r internal-registry.example.com/qualys/java-db
   ```

3. Run QScanner:
   ```bash
   qscanner image myapp:latest --skip-java-db-update=true --max-network-retries 0
   ```

### HPC shared filesystem

1. Install to shared location (run once):
   ```bash
   ./setup-java-db.sh -d /shared/qualys/java-db
   ```

2. In job scripts, set the cache directory:
   ```bash
   export QSCANNER_CACHE_DIR="/shared/qualys"
   qscanner image $IMAGE --skip-java-db-update=true --max-network-retries 0
   ```
