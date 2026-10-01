# Developing Hostshift

Build, helper and release details for contributors. For everyday use, see the [README](../README.md).

## Build and check

Requires macOS 14 or later and a Swift 6 compiler with a matching macOS SDK. No third-party dependencies are required.

```sh
./scripts/build.sh
./scripts/test.sh
open build/Hostshift.app
```

The build script creates an app for the current machine's architecture. Without an Apple signing identity it creates an ad-hoc signed local build. The one-time setup installs a helper restricted to the current user and that exact build. It uses `swiftc` directly, so Xcode is optional. The package can also be opened in Xcode, or built with `swift build`; run the core checks with `swift run HostsCoreChecks`.

If the compiler and SDK do not match, set `SDKROOT` to a compatible installed macOS SDK.

For a signed distribution build, use an installed Apple code-signing identity:

```sh
HOSTSHIFT_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/build.sh
```

Quit the running app before rebuilding it with a different signing identity. Signing keys belong in the macOS Keychain, never in the repository.

For distribution, notarise the signed app using Apple's notary service. Apple's service-management requirements include notarisation for apps containing launch daemons. Put the app in `/Applications` before enabling its helper so the service remains available before login. The app is not sandboxed because it manages a system file.

After storing notarisation credentials in a Keychain profile, submit and staple the signed app:

```sh
ditto -c -k --keepParent build/Hostshift.app build/Hostshift-notarization.zip
xcrun notarytool submit build/Hostshift-notarization.zip --keychain-profile Hostshift-notary --wait
# Continue only after Apple reports Accepted.
xcrun stapler staple build/Hostshift.app
xcrun stapler validate build/Hostshift.app
spctl --assess --type execute --verbose=2 build/Hostshift.app
```

Create the download archive after stapling. Keep app-specific passwords in a password manager or Keychain, and use `notarytool store-credentials` with its secure prompt rather than putting passwords in command arguments.

Local builds install the helper in `/Library/PrivilegedHelperTools/dev.dmallory.hostshift.helper`, its launch daemon in `/Library/LaunchDaemons/dev.dmallory.hostshift.helper.plist`, and its pinned identities in `/Library/Application Support/Hostshift/registration.json`. These files are root-owned. The helper is loaded on demand by launchd and survives app restarts. Rebuilding the app requires enabling access again because the local signature changes. Hostshift verifies the staged helper signature before installing it.

Apple-signed builds instead use `SMAppService`. Approve the helper once under **System Settings → General → Login Items & Extensions**. Hostshift shows pending, enabled and revoked states.

Use **Hostshift → Settings → Disable System Access** before uninstalling or changing installation methods. For the local build, removal also requests administrator authorisation. Disabling access leaves the current hosts file untouched; apply Original first if you want to restore it. After updating a signed helper, disable and enable access to re-register it.

## Storage and switching

Profiles are stored in `~/Library/Application Support/Hostshift/profiles.json`. The Original profile remains unchanged. Import and export preserve file contents, including comments.

Each switch checks the system file's SHA-256 digest before replacing it, saves the file it replaces to `/private/etc/hosts.hostshift-backup`, and atomically moves a prepared file into place with `root:wheel` ownership and `0644` permissions. Each switch overwrites that backup, so it always holds the file from before the latest switch. As with other hosts editors, concurrent writes from another tool should be avoided; digest checks cannot lock out unrelated processes.

Administrator approval happens during helper setup. Later switches use authenticated XPC calls. Local builds pin both peers to their exact code-signing requirements, with the approved user ID stored in the root-owned registration. Apple-signed builds require peers with the expected bundle identifier and the same Apple signing team. The helper independently validates incoming content, serialises writes, and only exposes hosts replacement. It never accepts a path or arbitrary shell command from clients. Hostshift never handles or stores an administrator password.

The command contains base64-encoded content, so profile text is never interpreted as shell syntax. DNS caches are refreshed after a successful switch; a cache refresh failure is reported separately. An unavailable helper reports an error and refreshes the system file without claiming success.

Profiles can contain IPv4, IPv6, aliases and comments. Invalid mappings block activation. Hostnames must use ASCII or punycode. This small app limits activation and imports to 96 KB to keep the helper command within system limits. Empty or comment-only profiles are valid and deliberately remove all mappings when applied.

## Verification

The executable checks cover validation, persistence, active-profile selection, corrupt library handling, backup creation, exact content replacement, external-change conflicts and symlink rejection. Helper checks cover independent request validation, rejected and accepted XPC peers, and isolated local installation and removal. Installation checks use temporary files and substitute ownership and DNS commands. They do not modify `/etc/hosts`, register a real daemon, or request administrator access.

For manual verification, check profile editing, saving, switching, import/export, keyboard navigation and helper setup. The Apple-signed SMAppService path and older supported macOS versions still need testing.

## Apple references

- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [NSTextView](https://developer.apple.com/documentation/appkit/nstextview)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Getting started with SMAppService](https://developer.apple.com/forums/thread/802443)
- [Authenticating XPC peers](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))
- [Creating launch daemons and agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

## Update checks

**Hostshift → Check for Updates…** checks the latest public GitHub release. Settings offers an opt-in daily check; checks run while the main window is open. A newer release opens in the browser after choosing **View Release**. The checker does not install or replace the app, interrupt an activation, or save/discard profile edits. It uses Apple's URLSession, AppKit alerts and SwiftUI controls, with no updater dependency.

The default release repository is `dmallory42/hostshift`. Override the repository and set the version when building:

```sh
HOSTSHIFT_UPDATE_REPOSITORY="OWNER/REPOSITORY" \
HOSTSHIFT_VERSION="1.1.0" HOSTSHIFT_BUILD_NUMBER="2" \
./scripts/build.sh
```

Use numeric release tags such as `v1.1.0`, mark production releases as GitHub's latest release, and attach an app archive built for the intended architecture. Drafts and prereleases are not offered. This checker compares the marketing version, so increment `HOSTSHIFT_VERSION` for each published update. Unconfigured builds report that updates are unavailable and make no update requests. Private repositories are not supported; no GitHub credentials are embedded in the app.

The Developer ID can be supplied later through `HOSTSHIFT_SIGNING_IDENTITY`, alongside these variables. Before publishing downloads, sign and notarise the app and test helper registration after an upgrade. No release has been published by this setup. In-app installation through Sparkle remains future work, including its signed feed and coordination of unsaved edits and helper upgrades.
