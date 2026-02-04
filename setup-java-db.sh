#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_REGISTRY="ghcr.io/aquasecurity/trivy-java-db"
DEFAULT_TAG="1"
DEFAULT_CACHE_DIR="${HOME}/.cache/qualys/qscanner/java-db"

REGISTRY="${JAVADB_REGISTRY:-$DEFAULT_REGISTRY}"
TAG="${JAVADB_TAG:-$DEFAULT_TAG}"
CACHE_DIR="${JAVADB_CACHE_DIR:-$DEFAULT_CACHE_DIR}"

WORK_DIR=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download and install the Trivy Java DB for qscanner.

OPTIONS:
    -r, --registry URL    OCI registry URL (default: $DEFAULT_REGISTRY)
    -t, --tag TAG         Image tag (default: $DEFAULT_TAG)
    -d, --dest DIR        Destination directory (default: $DEFAULT_CACHE_DIR)
    -h, --help            Show this help message

ENVIRONMENT VARIABLES:
    JAVADB_REGISTRY       Override default registry
    JAVADB_TAG            Override default tag
    JAVADB_CACHE_DIR      Override default cache directory

EXAMPLES:
    # Pull from default ghcr.io source
    $(basename "$0")

    # Pull from internal mirror
    $(basename "$0") -r your-registry.example.com/qualys/trivy-java-db

    # Install to shared location for HPC
    $(basename "$0") -d /shared/qualys/java-db

    # Use environment variables
    JAVADB_REGISTRY=my-registry.com/trivy-java-db $(basename "$0")

QSCANNER USAGE:
    After running this script, use qscanner with:
        qscanner image <image> --skip-java-db-update=true --max-network-retries 0

    Or specify a custom cache directory:
        qscanner image <image> --cache-dir \$(dirname \$JAVADB_CACHE_DIR) --skip-java-db-update=true --max-network-retries 0

    For fully offline scanning (degrades Java package detection):
        qscanner image <image> --skip-java-db-update=true --offline-scan=true
EOF
}

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup EXIT

check_oras() {
    if ! command -v oras &> /dev/null; then
        echo "Error: oras CLI not found. Install it first:"
        echo ""
        echo "  # Linux amd64"
        echo "  export VERSION=\"1.2.0\""
        echo "  curl -LO \"https://github.com/oras-project/oras/releases/download/v\${VERSION}/oras_\${VERSION}_linux_amd64.tar.gz\""
        echo "  tar -zxf oras_\${VERSION}_linux_amd64.tar.gz"
        echo "  sudo mv oras /usr/local/bin/"
        echo ""
        echo "  # macOS"
        echo "  brew install oras"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            -t|--tag)
                TAG="$2"
                shift 2
                ;;
            -d|--dest)
                CACHE_DIR="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    check_oras

    echo "==> Downloading Java DB from ${REGISTRY}:${TAG}"

    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR"

    if ! oras pull "${REGISTRY}:${TAG}"; then
        echo "Error: Failed to pull from ${REGISTRY}:${TAG}"
        exit 1
    fi

    if [[ ! -f "javadb.tar.gz" ]]; then
        echo "Error: javadb.tar.gz not found after pull"
        echo "Contents of pull:"
        ls -la
        exit 1
    fi

    echo "==> Creating destination directory: ${CACHE_DIR}"
    mkdir -p "$CACHE_DIR"

    echo "==> Extracting Java DB"
    tar -zxf javadb.tar.gz -C "$CACHE_DIR"

    echo "==> Verifying installation"
    if [[ -f "${CACHE_DIR}/trivy-java.db" ]]; then
        DB_SIZE=$(du -h "${CACHE_DIR}/trivy-java.db" | cut -f1)
        echo "    Database installed: ${CACHE_DIR}/trivy-java.db (${DB_SIZE})"
    else
        echo "    Contents of ${CACHE_DIR}:"
        ls -la "$CACHE_DIR"
    fi

    echo ""
    echo "==> Installation complete!"
    echo ""
    echo "To use with qscanner, run:"
    echo "    qscanner image <image> --skip-java-db-update=true --max-network-retries 0"
    echo ""
    echo "If using a non-default location, ensure qscanner can find it:"
    echo "    export QSCANNER_CACHE_DIR=\"$(dirname "$CACHE_DIR")\""
    echo "    qscanner image <image> --skip-java-db-update=true --max-network-retries 0"
    echo ""
}

main "$@"
