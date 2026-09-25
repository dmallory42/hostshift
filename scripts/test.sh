#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
MODULES="$PWD/build/checks"
mkdir -p "$MODULES"
swiftc -swift-version 6 -parse-as-library -emit-module -emit-object \
    -whole-module-optimization -module-name HostsCore Sources/HostsCore/*.swift \
    -o "$MODULES/HostsCore.o" -emit-module-path "$MODULES/HostsCore.swiftmodule"
swiftc -swift-version 6 -parse-as-library -I "$MODULES" scripts/checks.swift \
    "$MODULES/HostsCore.o" -o "$MODULES/checks"
"$MODULES/checks"
swiftc -swift-version 6 -parse-as-library -I "$MODULES" scripts/helper-checks.swift \
    Sources/HostshiftHelper/HelperService.swift Sources/HostshiftHelper/HelperDelegate.swift \
    "$MODULES/HostsCore.o" -o "$MODULES/helper-checks"
"$MODULES/helper-checks"

swiftc -swift-version 6 -parse-as-library -I "$MODULES" scripts/profile-checks.swift \
    Sources/Hostshift/ProfileStore.swift Sources/Hostshift/SystemAccess.swift \
    Sources/Hostshift/LocalSetup.swift Sources/Hostshift/HostsInstaller.swift \
    Sources/Hostshift/HelperReply.swift "$MODULES/HostsCore.o" -o "$MODULES/profile-checks"
"$MODULES/profile-checks"

swiftc -swift-version 6 -parse-as-library -I "$MODULES" scripts/editor-checks.swift \
    Sources/Hostshift/HostsTextFormatting.swift Sources/Hostshift/HostsSyntaxHighlighter.swift Sources/Hostshift/HostsTextCoordinator.swift "$MODULES/HostsCore.o" -o "$MODULES/editor-checks"
"$MODULES/editor-checks"

swiftc -swift-version 6 -parse-as-library -I "$MODULES" scripts/update-checks.swift \
    "$MODULES/HostsCore.o" -o "$MODULES/update-checks"
"$MODULES/update-checks"
