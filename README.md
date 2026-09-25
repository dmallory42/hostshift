# Hostshift

Switch `/etc/hosts` configurations from a native macOS app or the menu bar. Keep separate profiles for local development, staging and your usual setup, then activate the one you need.

- Save, duplicate, import and export hosts profiles.
- Edit with syntax highlighting, line numbers and validation. No autocorrect or smart substitutions.
- Switch profiles from the menu bar without opening the editor.
- Restore your starting configuration with the read-only **Original** profile.

## Get started

Requires macOS 14 or later and a Swift 6 toolchain. Build locally for now:

```sh
git clone https://github.com/dmallory42/hostshift.git
cd hostshift
./scripts/build.sh
open build/Hostshift.app
```

On first launch, choose **Enable System Access** and approve the helper installation. After setup, switching profiles doesn’t require a password. Local rebuilds require approval again.

## Switch hosts

1. Duplicate **Original** to keep your existing entries, or create a new profile.
2. Edit the mappings and give the profile a name.
3. Click **Activate** or press **⌘Return**. Hostshift saves the profile, updates `/etc/hosts` and refreshes the DNS cache.

**Save** (**⌘S**) keeps your edits without activating them. A dot beside the profile name means unsaved changes; the green checkmark marks the active profile.

You can also activate a profile from its right-click menu or the macOS menu bar. Invalid entries block activation, with clickable line numbers to help you fix them.

## Your configuration

Profiles stay on your Mac. Hostshift keeps your initial hosts file as **Original** and backs up `/etc/hosts` before each switch. Existing connections and apps with their own DNS caches may need restarting.

To uninstall, activate **Original** if you want to restore it, then choose **Settings → Disable System Access** before deleting the app.

## Updates and development

Use **Hostshift → Check for Updates…**, or enable automatic checks in Settings. Available updates open on GitHub for download.

For tests, signing and release setup, see [Developing Hostshift](docs/development.md).
