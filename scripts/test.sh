#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
MODULES="$PWD/build/checks"
TARGET=arm64-apple-macosx14.0
mkdir -p "$MODULES"
swiftc -swift-version 6 -target "$TARGET" -parse-as-library -emit-module -emit-object \
    -whole-module-optimization -module-name HostsCore Sources/HostsCore/*.swift \
    -o "$MODULES/HostsCore.o" -emit-module-path "$MODULES/HostsCore.swiftmodule"

# Builds and runs scripts/<name>.swift, linked with HostsCore and the sources listed after the name.
run_checks() {
    local name="$1"
    shift
    swiftc -swift-version 6 -target "$TARGET" -parse-as-library -I "$MODULES" "scripts/$name.swift" "$@" \
        "$MODULES/HostsCore.o" -o "$MODULES/$name"
    "$MODULES/$name"
}

run_checks checks
run_checks helper-checks \
    Sources/HostshiftHelper/HelperService.swift Sources/HostshiftHelper/HelperDelegate.swift \
    Sources/HostshiftHelper/IdleExit.swift
run_checks profile-checks \
    Sources/Hostshift/ProfileStore.swift Sources/Hostshift/SystemAccess.swift \
    Sources/Hostshift/LocalSetup.swift
run_checks editor-checks \
    Sources/Hostshift/HostsTextFormatting.swift Sources/Hostshift/HostsSyntaxHighlighter.swift \
    Sources/Hostshift/HostsTextCoordinator.swift
run_checks update-checks
