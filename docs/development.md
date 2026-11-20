# Developing Hostshift

Build, helper and release details for contributors. For everyday use, see the [README](../README.md).

## Build and check

Requires macOS 14 or later and a Swift 6 compiler with a matching macOS SDK. The command-line tool parses arguments with Apple's Swift Argument Parser, which is vendored unmodified in `Vendor/swift-argument-parser`, so builds need no package resolution or network access. Its README says how to update it.

```sh
./scripts/build.sh
./scripts/test.sh
open build/Hostshift.app
```

The build script creates an app for Apple silicon Macs; Intel Macs are not supported. Without an Apple signing identity it creates an ad-hoc signed local build. The one-time setup installs a helper restricted to the current user and that exact build. It uses `swiftc` directly, so Xcode is optional. The package can also be opened in Xcode, or built with `swift build`; run the core checks with `swift run HostsCoreChecks`.

If the compiler and SDK do not match, set `SDKROOT` to a compatible installed macOS SDK.

For a signed distribution build, use an installed Apple code-signing identity:

```sh
HOSTSHIFT_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/build.sh
```

Quit the running app before rebuilding it with a different signing identity. Signing keys belong in the macOS Keychain, never in the repository.

For distribution, notarise the signed app using Apple's notary service. Apple's service-management requirements include notarisation for apps containing launch daemons. Put the app in `/Applications` before enabling its helper so the service remains available before login; release builds show a move-to-Applications instruction instead of enabling access from anywhere else. The app is not sandboxed because it manages a system file.

After storing notarisation credentials in a Keychain profile, submit and staple the signed app:

```sh
ditto -c -k --keepParent build/Hostshift.app build/Hostshift-notarization.zip
xcrun notarytool submit build/Hostshift-notarization.zip --keychain-profile Hostshift-notary --wait
# Continue only after Apple reports Accepted.
xcrun stapler staple build/Hostshift.app
xcrun stapler validate build/Hostshift.app
spctl --assess --type execute --verbose=2 build/Hostshift.app
```

Then package the stapled app as a drag-to-Applications disk image, and notarise and staple the disk image too:

```sh
HOSTSHIFT_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/package-dmg.sh build/Hostshift.app
xcrun notarytool submit build/Hostshift-1.1.0.dmg --keychain-profile Hostshift-notary --wait
xcrun stapler staple build/Hostshift-1.1.0.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 build/Hostshift-1.1.0.dmg
```

The disk image is named after the app's version. `package-dmg.sh` scripts Finder to lay out the window, so the first run asks permission to control Finder. Keep app-specific passwords in a password manager or Keychain, and use `notarytool store-credentials` with its secure prompt rather than putting passwords in command arguments.

After publishing the notarised disk image, update the `hostshift` cask in the [`dmallory42/homebrew-tap`](https://github.com/dmallory42/homebrew-tap) repository. Set its `version` and the disk image's SHA-256 (`shasum -a 256 build/Hostshift-1.1.0.dmg`), then check it with `brew audit --cask dmallory42/tap/hostshift` and `brew install --cask dmallory42/tap/hostshift`. The cask links `hostshift` to the app's executable. It doesn't link `hs`, because Homebrew won't install over a command that another tool already provides.

Local builds install the helper in `/Library/PrivilegedHelperTools/dev.dmallory.hostshift.helper`, its launch daemon in `/Library/LaunchDaemons/dev.dmallory.hostshift.helper.plist`, and its pinned identities in `/Library/Application Support/Hostshift/registration.json`. These files are root-owned. launchd loads the helper on demand, so it stays available across app restarts. Rebuilding the app requires enabling access again because the local signature changes. Hostshift verifies the staged helper signature before installing it.

Apple-signed builds instead use `SMAppService`. Approve the helper once under **System Settings → General → Login Items & Extensions**. Hostshift shows pending, enabled and revoked states.

Use **Hostshift → Settings → Disable System Access** before uninstalling or changing installation methods. For the local build, removal also requests administrator authorisation. Disabling access leaves the current hosts file untouched; activate Original first if you want to restore it. Helpers from 1.0.1 and earlier never exit, so after updating from those versions, disable and enable access or restart the Mac to load the new helper.

## Storage and switching

Profiles are stored in `~/Library/Application Support/Hostshift/profiles.json`. The Original profile remains unchanged. Import and export preserve file contents, including comments.

Each switch checks the system file's SHA-256 digest before replacing it, saves the file it replaces to `/private/etc/hosts.hostshift-backup`, and atomically moves a prepared file into place with `root:wheel` ownership and `0644` permissions. Each switch overwrites that backup, so it always holds the file from before the latest switch. As with other hosts editors, concurrent writes from another tool should be avoided; digest checks cannot lock out unrelated processes.

Administrator approval happens during helper setup. Later switches use authenticated XPC calls. Local builds pin both peers to their exact code-signing requirements, with the approved user ID stored in the root-owned registration. Apple-signed builds require peers with the expected bundle identifier and the same Apple signing team. The helper independently validates incoming content, serialises writes, and only exposes hosts replacement. It exits after 30 seconds without a request and launchd starts it again for the next switch, so an updated app runs its own helper version. It never accepts a path or arbitrary shell command from clients. Hostshift never handles or stores an administrator password.

The command contains base64-encoded content, so profile text is never interpreted as shell syntax. DNS caches are refreshed after a successful switch; a cache refresh failure is reported separately. An unavailable helper reports an error and refreshes the system file without claiming success.

Profiles can contain IPv4, IPv6, aliases and comments. Invalid mappings block activation. Fields are separated by spaces or tabs, and lines end with LF or CRLF. Hostnames must use ASCII or punycode. This small app limits activation and imports to 96 KB to keep the helper command within system limits. Empty or comment-only profiles are valid and deliberately remove all mappings when activated.

## Command-line tool

The `hostshift` command is the app's own executable. `HostshiftMain` runs the command-line tool when the executable is invoked as `hostshift` or `hs`, or with a command, and starts the app otherwise. Because the tool has the app's exact signature, the helper accepts it through the same XPC checks and local registration, and no other client needs to be trusted. A link such as `/opt/homebrew/bin/hostshift` is resolved and the process re-executes from the real path, so Foundation finds the app bundle. `argv[0]` is kept, so help shows the name that was typed.

Arguments are parsed with Swift Argument Parser. The commands share `ProfileActivation` and the `ProfileLibrary` rules in HostsCore with the app, so validation, naming, the Original and active-profile protections, and the external-changes check behave the same way. The tool has no drafts and saves each change immediately.

The app and the tool can both change `profiles.json`. `ProfileLibraryFile` re-reads the file under an exclusive lock on `profiles.json.lock`, applies one change and replaces the file atomically. The app reloads the library when the file changes, during its three-second check and before acting on a profile, and keeps its drafts.

Exit codes and JSON fields are part of the interface. Change them only with [the command-line reference](cli.md), which documents them for scripts and agents.

## Verification

The executable checks cover validation, persistence, active-profile selection, corrupt library handling, backup creation, exact content replacement, external-change conflicts and symlink rejection. Helper checks cover independent request validation, rejected and accepted XPC peers, the idle exit, and isolated local installation and removal. Profile checks run activation against a temporary hosts file with the helper call and external-change prompt substituted. Profile checks also cover another process changing the library while the app has drafts. CLI checks run every command against a temporary library and hosts file, with the helper, terminal, editor and system-access status substituted. Installation checks use temporary files and substitute ownership and DNS commands. They do not modify `/etc/hosts`, register a real daemon, or request administrator access.

For manual verification, check profile editing, saving, switching, import/export, keyboard navigation and helper setup. Older supported macOS versions still need testing.

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

Use numeric release tags such as `v1.1.0`, mark production releases as GitHub's latest release, and attach the disk image. Drafts and prereleases are not offered. This checker compares the marketing version, so increment `HOSTSHIFT_VERSION` for each published update. Unconfigured builds report that updates are unavailable and make no update requests. Private repositories are not supported; no GitHub credentials are embedded in the app.

Supply the Developer ID through `HOSTSHIFT_SIGNING_IDENTITY`, alongside these variables. Before publishing downloads, sign and notarise the app and test helper registration after an upgrade. In-app installation through Sparkle remains future work, including its signed feed and coordination of unsaved edits and helper upgrades.
