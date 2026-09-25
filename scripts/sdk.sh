# Respect an explicit SDK, otherwise use the Command Line Tools default SDK.
if [[ -z "${SDKROOT:-}" ]]; then
    HOSTSHIFT_DEFAULT_SDK="$(xcode-select -p)/SDKs/MacOSX.sdk"
    if [[ -d "$HOSTSHIFT_DEFAULT_SDK" ]]; then
        export SDKROOT="$HOSTSHIFT_DEFAULT_SDK"
    else
        export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    fi
fi
