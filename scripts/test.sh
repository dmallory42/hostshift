#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sdk.sh
MODULES="$PWD/build/checks"
TARGET=arm64-apple-macosx14.0
mkdir -p "$MODULES"
# Compiles a library module from the sources after the name, with optional extra flags in MODULE_FLAGS.
compile_module() {
    local name="$1"
    shift
    swiftc -swift-version 6 -target "$TARGET" -parse-as-library ${MODULE_FLAGS:-} -emit-module -emit-object \
        -whole-module-optimization -module-name "$name" -I "$MODULES" "$@" \
        -o "$MODULES/$name.o" -emit-module-path "$MODULES/$name.swiftmodule"
}
compile_module HostsCore Sources/HostsCore/*.swift
PARSER=Vendor/swift-argument-parser/Sources
MODULE_FLAGS=-suppress-warnings compile_module ArgumentParserToolInfo "$PARSER"/ArgumentParserToolInfo/*.swift
MODULE_FLAGS=-suppress-warnings compile_module ArgumentParser "$PARSER"/ArgumentParser/*/*.swift

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
run_checks cli-checks \
    Sources/Hostshift/CLIContext.swift Sources/Hostshift/CLICommands.swift Sources/Hostshift/CLIRunner.swift \
    Sources/Hostshift/CommandLineInstall.swift \
    "$MODULES/ArgumentParser.o" "$MODULES/ArgumentParserToolInfo.o"
