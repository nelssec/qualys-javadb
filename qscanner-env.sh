#!/bin/bash

JAVADB_CACHE_DIR="${JAVADB_CACHE_DIR:-${HOME}/.cache/qualys/qscanner/java-db}"
QSCANNER_CACHE_DIR="$(dirname "$JAVADB_CACHE_DIR")"

export QSCANNER_CACHE_DIR

echo "QScanner cache: $QSCANNER_CACHE_DIR"
echo "Java DB location: $JAVADB_CACHE_DIR"
echo ""
echo "Recommended qscanner flags for pre-staged java-db:"
echo "  --skip-java-db-update=true    Prevents java-db download attempts"
echo "  --scan-timeout 5m             Scan timeout (default: 5m)"
echo "  --max-network-retries 0       Disable network retries"
echo ""
echo "Example:"
echo "  qscanner image <image> --skip-java-db-update=true --max-network-retries 0"
