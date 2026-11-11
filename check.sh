#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./fetch-resources.sh
mkdir -p build
xcrun swiftc -module-cache-path build/ModuleCache Sources/AtariProject.swift \
    Checks/Compatibility.swift -o build/compatibility-check
build/compatibility-check "$@"
