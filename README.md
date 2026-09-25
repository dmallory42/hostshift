# Hostshift

A small native macOS app for saving and switching `/etc/hosts` configurations. The name and two-way arrow icon reflect switching between host profiles.

## Use

Open `build/Hostshift.app`. Choose **Enable System Access** and approve the one-time helper installation with your administrator password. An Apple Developer account is not required for the local build. Subsequent switches do not require a password. System access is required before using profiles. The setup sheet offers Enable System Access or Quit Hostshift. Cancelling administrator authorisation returns to setup.

Hostshift captures the existing hosts file as a read-only **Original** profile on first launch.

- The toolbar contains **New Profile**, **Save** and **Activate**. Duplicate, rename and delete profiles from the sidebar’s context menu or File menu. Import and export are in the File menu.
- Edit the name and contents, then click **Save** or press **⌘S**. Unsaved profiles have a dot in the sidebar and an **Unsaved changes** indicator in the editor status bar. Switching profiles keeps drafts in memory; quitting prompts you to save or discard them.
- The editor highlights addresses, hostnames and comments. Line numbers match validation messages. Expand the issue count in the status bar and click an issue to select its line.
- Right-click a profile for **New Profile**, **Duplicate**, **Rename…** and **Delete**. Use **⌘N** to create a profile and **⌘D** to duplicate the selected profile. With the sidebar focused, use **Return** to rename or **Backspace/Delete** to request deletion. Deletion requires confirmation; Original and active profiles are protected.
- Choose **Activate** or press Command-Return to save the selected profile and replace `/etc/hosts`. The approved helper applies it immediately.
- Select **Original** and apply it to restore the first-launch configuration.
- The sidebar footer shows the active saved profile. If the system file differs, use **Capture as Profile** to create a draft from it, then save that draft. Hostshift refreshes system status automatically.

The two-way arrow in the macOS menu bar provides quick access to all saved profiles. Click a profile to apply it; a checkmark marks the active one. The menu remains available after closing the main window and includes Open Hostshift, Settings and Quit. You can hide it in Settings. Profile switching requires system access to be enabled and a valid target profile; activation saves any edits first.

Only one matching profile is marked active. If another tool changes the system file, Hostshift refreshes its status. Editing a saved profile does not change the system file until you apply it.

The editor uses AppKit's plain-text `NSTextView`, with undo and find enabled, and smart substitutions disabled. An AppKit ruler shows logical line numbers that match validation messages, including blank lines and CRLF files; wrapped continuations keep their original line number. The surrounding interface uses SwiftUI's native split view, sidebar, toolbar, menus, confirmation dialogs and system colours. It supports light and dark appearance.

## Build and check

Requires macOS 14 or later and a Swift 6 compiler with a matching macOS SDK. No third-party dependencies are required.

```sh
./scripts/build.sh
./scripts/test.sh
open build/Hostshift.app
```

The build script creates an app for the current machine's architecture. Without an Apple signing identity it creates an ad-hoc signed local build. The one-time setup installs a helper restricted to the current user and that exact build. It uses `swiftc` directly, so Xcode is optional. The package can also be opened in Xcode, or built with `swift build`; run the core checks with `swift run HostsCoreChecks`.

If the selected SDK does not match the compiler, set `SDKROOT` to a compatible installed SDK before running the scripts. For the current local Command Line Tools installation:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

For a signed distribution build, use an installed Apple code-signing identity:

```sh
HOSTSHIFT_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build.sh
```

For distribution, notarise the signed app using Apple's notary service. Apple's service-management requirements include notarisation for apps containing launch daemons. Put the app in `/Applications` before enabling its helper so the service remains available before login. The app is not sandboxed because it manages a system file.

Local builds install the helper in `/Library/PrivilegedHelperTools/local.hostshift.helper`, its launch daemon in `/Library/LaunchDaemons/local.hostshift.helper.plist`, and its pinned identities in `/Library/Application Support/Hostshift/registration.json`. These files are root-owned. The helper is loaded on demand by launchd and survives app restarts. Rebuilding the app requires enabling access again because the local signature changes. Hostshift verifies the staged helper signature before installing it.

Apple-signed builds instead use `SMAppService`. Approve the helper once under **System Settings → General → Login Items & Extensions**. Hostshift shows pending, enabled and revoked states.

Use **Hostshift → Settings → Disable System Access** before uninstalling or changing installation methods. For the local build, removal also requests administrator authorisation. Disabling access leaves the current hosts file untouched; apply Original first if you want to restore it. After updating a signed helper, disable and enable access to re-register it.

## Storage and switching

Profiles are stored in `~/Library/Application Support/Hostshift/profiles.json`. The Original profile remains unchanged. Import and export preserve file contents, including comments.

Each switch checks the system file's SHA-256 digest before replacing it, creates a backup at `/private/etc/hosts.hostshift-backup.*`, and atomically moves a prepared file into place with `root:wheel` ownership and `0644` permissions. Backups are retained until manually removed. As with other hosts editors, concurrent writes from another tool should be avoided; digest checks cannot lock out unrelated processes.

Administrator approval happens during helper setup. Later switches use authenticated XPC calls. Local builds pin both peers to their exact code-signing requirements, with the approved user ID stored in the root-owned registration. Apple-signed builds require peers with the expected bundle identifier and the same Apple signing team. The helper independently validates incoming content, serialises writes, and only exposes hosts replacement. It never accepts a path or arbitrary shell command from clients. Hostshift never handles or stores an administrator password.

The command contains base64-encoded content, so profile text is never interpreted as shell syntax. DNS caches are refreshed after a successful switch; a cache refresh failure is reported separately. An unavailable helper reports an error and refreshes the system file without claiming success.

Profiles can contain IPv4, IPv6, aliases and comments. Invalid mappings block activation. Hostnames must use ASCII or punycode. This small app limits activation and imports to 96 KB to keep the helper command within system limits. Empty or comment-only profiles are valid and deliberately remove all mappings when applied.

## Verification

The executable checks cover validation, persistence, active-profile selection, corrupt library handling, backup creation, exact content replacement, external-change conflicts and symlink rejection. Helper checks cover independent request validation, rejected and accepted XPC peers, and isolated local installation and removal. Installation checks use temporary files and substitute ownership and DNS commands. They do not modify `/etc/hosts`, register a real daemon, or request administrator access.

A full manual check should create and edit a profile, import and export it, approve the helper once, apply two different profiles without another password prompt, then restore Original. Disable system access and confirm that Apply becomes unavailable. For Apple-signed builds, also revoke approval in System Settings. Also check keyboard navigation and VoiceOver. On 22 September 2026, the local helper installation was approved on the development Mac. Two switches through the running helper succeeded without another password prompt, using identical copies of Original to preserve the host mappings. Original was left active and its content verified byte-for-byte. All 27 automated checks passed. The Apple-signed SMAppService path and older supported macOS versions have not been exercised.

On 24 September 2026, the menu bar update passed the same 27 automated checks and app signature verification. Native UI checks confirmed that the menu survives closing the main window, reopens it, exposes labelled actions, and disables switching before helper setup. This rebuilt local app requires setup approval again; no hosts mappings were changed during these checks.

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

Configure the public release repository and version when building:

```sh
HOSTSHIFT_UPDATE_REPOSITORY="OWNER/REPOSITORY" \
HOSTSHIFT_VERSION="1.1.0" HOSTSHIFT_BUILD_NUMBER="2" \
./scripts/build.sh
```

Use numeric release tags such as `v1.1.0`, mark production releases as GitHub's latest release, and attach an app archive built for the intended architecture. Drafts and prereleases are not offered. This checker compares the marketing version, so increment `HOSTSHIFT_VERSION` for each published update. Unconfigured builds report that updates are unavailable and make no update requests. Private repositories are not supported; no GitHub credentials are embedded in the app.

The Developer ID can be supplied later through `HOSTSHIFT_SIGNING_IDENTITY`, alongside these variables. Before publishing downloads, sign and notarise the app and test helper registration after an upgrade. No release has been published by this setup. In-app installation through Sparkle remains future work, including its signed feed and coordination of unsaved edits and helper upgrades.
