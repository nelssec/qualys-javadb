#!/bin/bash
set -euo pipefail

SOURCE_REGISTRY="ghcr.io/aquasecurity/trivy-java-db"
SOURCE_TAG="1"
DEST_REGISTRY=""
DEST_TAG="1"

WORK_DIR=""

usage() {
    cat <<EOF
Usage: $(basename "$0") -d DEST_REGISTRY [OPTIONS]

Mirror Trivy Java DB to an internal registry for air-gapped environments.

OPTIONS:
    -s, --source URL      Source registry (default: $SOURCE_REGISTRY)
    -d, --dest URL        Destination registry (required)
    -t, --tag TAG         Tag to use (default: $SOURCE_TAG)
    --source-tag TAG      Source tag if different from dest
    --dest-tag TAG        Destination tag if different from source
    -h, --help            Show this help message

EXAMPLES:
    # Mirror to internal registry
    $(basename "$0") -d your-registry.example.com/qualys/trivy-java-db

    # Mirror with different tag
    $(basename "$0") -d your-registry.example.com/trivy-java-db -t latest

    # Mirror from one internal registry to another
    $(basename "$0") -s registry1.example.com/java-db -d registry2.example.com/java-db
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
        echo "  brew install oras  # macOS"
        echo "  # or see https://oras.land/docs/installation"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source)
                SOURCE_REGISTRY="$2"
                shift 2
                ;;
            -d|--dest)
                DEST_REGISTRY="$2"
                shift 2
                ;;
            -t|--tag)
                SOURCE_TAG="$2"
                DEST_TAG="$2"
                shift 2
                ;;
            --source-tag)
                SOURCE_TAG="$2"
                shift 2
                ;;
            --dest-tag)
                DEST_TAG="$2"
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

    if [[ -z "$DEST_REGISTRY" ]]; then
        echo "Error: Destination registry is required (-d)"
        echo ""
        usage
        exit 1
    fi
}

main() {
    parse_args "$@"
    check_oras

    echo "==> Mirroring Java DB"
    echo "    Source: ${SOURCE_REGISTRY}:${SOURCE_TAG}"
    echo "    Dest:   ${DEST_REGISTRY}:${DEST_TAG}"
    echo ""

    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR"

    echo "==> Pulling from source registry"
    if ! oras pull "${SOURCE_REGISTRY}:${SOURCE_TAG}"; then
        echo "Error: Failed to pull from ${SOURCE_REGISTRY}:${SOURCE_TAG}"
        exit 1
    fi

    if [[ ! -f "javadb.tar.gz" ]]; then
        echo "Error: javadb.tar.gz not found after pull"
        ls -la
        exit 1
    fi

    DB_SIZE=$(du -h javadb.tar.gz | cut -f1)
    echo "    Downloaded: javadb.tar.gz (${DB_SIZE})"

    echo "==> Pushing to destination registry"
    if ! oras push "${DEST_REGISTRY}:${DEST_TAG}" \
        javadb.tar.gz:application/vnd.aquasec.trivy.javadb.layer.v1.tar+gzip; then
        echo "Error: Failed to push to ${DEST_REGISTRY}:${DEST_TAG}"
        exit 1
    fi

    echo ""
    echo "==> Mirror complete!"
    echo ""
    echo "To pull from your mirror:"
    echo "    ./setup-java-db.sh -r ${DEST_REGISTRY} -t ${DEST_TAG}"
    echo ""
}

main "$@"
