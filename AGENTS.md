# Hostshift

Native macOS app for switching `/etc/hosts` between saved profiles. A privileged helper writes the file. The [README](README.md) is for users; [docs/development.md](docs/development.md) covers internals, signing and releases.

## Commands

- Build: `./scripts/build.sh` produces `build/Hostshift.app`. It compiles with `swiftc` and packages the app and helper; `swift build` does not produce a runnable app.
- Test: `./scripts/test.sh`. Run it after changing profile state, validation, persistence, installation or update checking. Register new check executables in that script.
- Separate output or signed build: set `HOSTSHIFT_BUILD_DIR` and `HOSTSHIFT_SIGNING_IDENTITY`. See docs/development.md.
- Release disk image: `./scripts/package-dmg.sh path/to/Hostshift.app` after the app is notarised and stapled. It scripts Finder to lay out the window.
- If the compiler and SDK mismatch, set `SDKROOT` to a compatible SDK. Never commit a machine-specific SDK path.
- Documentation-only changes need link, path and diff checks, not a rebuild.

## Constraints

- macOS 14 and Swift 6. Guard newer APIs with availability checks instead of raising the minimum version.
- Apple silicon only. Intel Macs are not supported.
- No third-party dependencies without discussing them with the user.
- The bundle identifiers `dev.dmallory.hostshift` and `dev.dmallory.hostshift.helper` feed the signing requirements and launchd label. Changing them after release strands installed helpers.
- Never embed GitHub tokens or signing credentials. Keep signing identities configurable through the build script.

## System safety

- IMPORTANT: Confirm with the user before activating a real profile, writing `/etc/hosts`, installing or removing the real helper, or deleting root-owned files. Describe the steps and how the system will be restored, then wait for approval.
- Tests use temporary profile libraries and substituted installation paths, never the real hosts file or helper.
- Never save or discard the user's drafts to make a test easier. Quit Hostshift normally and respect its unsaved-changes prompt; do not force-kill it.
- Preserve the helper's protections: XPC code-signing checks, independent validation of every request, conflict detection, the backup, atomic replacement and read-back verification. The helper must never accept a path or shell command from a client.

## Verifying UI changes

- A successful compile does not verify focus, menus or layout. Build and exercise the changed interaction.
- From a terminal, drive the app with System Events UI scripting and capture its window with `screencapture -l <window id>`. Click buttons and menu items instead of sending keystrokes, because a keystroke goes to whichever app is frontmost, which may be the terminal. SwiftUI buttons often expose no accessibility title, so address them by position.
- Local builds pin the helper to the exact app signature, so every rebuild needs system access approved again. Do not rebuild while the app is open or during an administrator prompt.
- `open build/Hostshift.app` does not restart a running process. Confirm the old process has exited before claiming new code is loaded.

## Product behaviour

- User-facing copy says **Activate**. Internal `apply` names are fine.
- Save stores a profile locally. Activate validates, saves that profile and installs it; a failed save must stop the install, and other drafts stay unsaved.
- Activation replaces the whole hosts file. When `/etc/hosts` matches neither the last activation nor a saved profile, ask whether to save it as a profile, replace it or cancel. Saving edits to the active profile must not trigger this prompt.
- The helper keeps one backup, `/private/etc/hosts.hostshift-backup`, holding the file the latest switch replaced. A rejected switch leaves it unchanged.
- **Original** is the read-only first-launch snapshot. Never replace it with a later system file.
- Active status means a saved profile matches `/etc/hosts`, not which row is selected. Unsaved edits to the active profile must stay activatable.
- New profile names are unique: copies are named "Copy of …" and a name in use gains " (2)", " (3)" and so on. Names the user types are kept as typed.
- Sidebar context actions target the clicked row. Backspace or Delete asks for confirmation only when the sidebar has focus, so text editing keeps normal deletion.
- Unsaved dots sit beside names and the active checkmark sits at the trailing edge. Status icons need accessible labels.
- Use native SwiftUI and AppKit controls, menus and shortcuts. Show system-access setup in place of the profile view, not as a sheet: macOS will not quit an app while a sheet is open.

## Hosts content is literal text

- Preserve tabs, spaces, line endings and comments through editing, saving, import, export and activation. Never normalise or autoformat.
- Keep autocorrection, smart substitutions, predictive completion and Writing Tools off. App-wide punctuation settings live in `HostshiftApp`, editor flags in `HostsTextEditor`. Never change global macOS preferences.
- Syntax colours and tab alignment are display-only and must not change stored text or undo history.
- Line numbers and diagnostics must handle UTF-16 offsets, CRLF and wrapped lines.

## Documentation

- The update checker only finds a newer GitHub release and opens its page. Never describe it as installing updates.
- Keep the README to setup and everyday use; architecture, packaging and releases go in docs/development.md.
- Keep session history and handoff notes out of the repository.
