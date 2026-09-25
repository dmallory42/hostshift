# Working on Hostshift

Hostshift is a native macOS hosts-file switcher for developers. Keep the UI small and familiar. The [README](README.md) is for people using the app; [development notes](docs/development.md) cover its internals and release setup.

## Build and verification

- Target macOS 14 and Swift 6. Guard newer APIs with availability checks rather than raising the minimum OS version.
- Build the runnable bundle with `./scripts/build.sh`; it produces `build/Hostshift.app`. The script compiles with `swiftc` and packages both executables. A plain Swift package build does not replace this packaging step.
- Run `./scripts/test.sh` for changes to profile state, validation, persistence, installation or update checking. These checks use isolated files and helper fixtures, not the real system hosts file.
- For UI changes, build and exercise the affected interaction when possible. A successful compile alone does not verify keyboard focus, context-menu targets or layout.
- `scripts/sdk.sh` selects the SDK. If the compiler and SDK mismatch, inspect the installed toolchain and set `SDKROOT` to a compatible SDK. Do not hard-code a machine-specific SDK path into the project.
- Documentation-only changes need link/path and diff checks, not an app rebuild.

## Where changes belong

- `Sources/Hostshift`: SwiftUI screens, AppKit editor, profile store, helper client and update checker.
- `Sources/HostsCore`: shared models, validation, persistence, signing requirements and installation script generation.
- `Sources/HostshiftHelper`: privileged XPC service. It validates requests independently of the UI.
- `Resources`: app and launch-daemon property lists.
- `scripts`: packaging and executable checks. Add new check executables to `scripts/test.sh`.

## Behaviour to preserve

- Use **Activate** in user-facing copy. Internal `apply` names still exist.
- Save persists a profile locally. Activate validates, saves that profile, then installs it. A failed save must prevent installation; unrelated drafts stay unsaved.
- **Original** is the read-only first-launch snapshot. Do not silently replace it with a later system file.
- Active status reflects the saved profile matching `/etc/hosts`, not whichever row is selected. Unsaved edits to the active profile must remain activatable.
- Sidebar context actions target the clicked row. Backspace/Delete requests confirmation only when the sidebar has focus; editing text must retain normal deletion behaviour.
- Unsaved dots sit beside names; the active checkmark sits at the trailing edge. Give status icons accessible labels.
- Use SwiftUI and AppKit controls, native menus, sheets and keyboard shortcuts. Keep system-access setup separate from the profile layout.

## Treat hosts content as literal text

- Preserve tabs, spaces, line endings and comments through editing, saving, import/export and activation. Do not normalise or autoformat content.
- Keep autocorrection, smart substitutions, predictive completion and Writing Tools disabled. App-level period/capitalisation preferences live in `HostshiftApp`; per-editor flags live in `HostsTextEditor`. Do not change global macOS preferences.
- Syntax colours use temporary layout attributes. Tab alignment is visual paragraph formatting; neither should rewrite stored text or disturb undo history.
- Line numbers and diagnostic navigation must handle UTF-16 offsets, CRLF and wrapped lines.

## Protect the running app and system files

- Use temporary profile libraries and mocked installation paths for tests. Do not activate a real profile, overwrite `/etc/hosts`, or install/remove the real helper merely to verify a change unless the user has authorised that system action.
- Never save or discard the user's drafts to make a test or relaunch easier. Use normal app termination and respect its unsaved-changes prompt. Do not force-kill Hostshift.
- Local builds pin helper access to the exact app signature. Rebuilding while the app is open replaces its bundle; the old process must restart and the new build needs system-access approval. Do not rebuild during an administrator-authorisation flow.
- `open build/Hostshift.app` does not restart an existing process. Verify it has exited before claiming a relaunch loaded new code.
- Preserve XPC code-signing checks, helper-side validation, conflict detection, backups, atomic replacement and read-back verification. The helper must never accept arbitrary paths or shell commands from clients.
- Leave signing identities configurable. The Developer ID/SMAppService distribution path still needs release testing; local helper tests do not establish that it works.

## Updates and documentation

- The current updater checks public GitHub releases and opens the release page. It does not install updates. Do not describe it as an automatic installer.
- Release settings are in `Resources/Info.plist` with build-script overrides. Never embed GitHub tokens or signing credentials.
- Keep the README focused on setup and everyday host switching. Put architecture, packaging and release details in `docs/development.md`; omit local session history.
- Do not add third-party dependencies without discussing the need with the user.
