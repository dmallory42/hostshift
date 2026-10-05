# Hostshift

Switch `/etc/hosts` configurations from a native macOS app or the menu bar. Keep separate profiles for local development, staging and your usual setup, then activate the one you need.

- Save, duplicate, import and export hosts profiles.
- Edit with syntax highlighting, line numbers and validation. No autocorrect or smart substitutions.
- Switch profiles from the menu bar without opening the editor.
- Restore your starting configuration with the read-only **Original** profile.

## Get started

Requires an Apple silicon Mac with macOS 14 or later.

1. Download the disk image from the [latest release](https://github.com/dmallory42/hostshift/releases/latest).
2. Open it and drag Hostshift to Applications.
3. Open Hostshift from Applications and choose **Enable System Access**.
4. Allow Hostshift under **System Settings → General → Login Items & Extensions**.

After setup, switching profiles doesn’t require a password. Hostshift needs to run from Applications to enable system access.

### Build from source

Building needs a Swift 6 toolchain:

```sh
git clone https://github.com/dmallory42/hostshift.git
cd hostshift
./scripts/build.sh
open build/Hostshift.app
```

Local builds ask for administrator approval when you enable system access, and again after each rebuild.

## Switch hosts

1. Duplicate **Original** to keep your existing entries, or create a new profile.
2. Edit the mappings and give the profile a name.
3. Click **Activate** or press **⌘Return**. Hostshift saves the profile, updates `/etc/hosts` and refreshes the DNS cache.

**Save** (**⌘S**) keeps your edits without activating them. A dot beside the profile name means unsaved changes; the green checkmark marks the active profile.

You can also activate a profile from its right-click menu or the macOS menu bar. Invalid entries block activation, with clickable line numbers to help you fix them.

If another app or a manual edit has changed `/etc/hosts`, Hostshift asks before replacing those changes. Choose **Save as Profile** to keep them.

## Your configuration

Profiles stay on your Mac. Hostshift keeps your initial hosts file as **Original**. Each switch saves the file it replaces to `/private/etc/hosts.hostshift-backup`. Existing connections and apps with their own DNS caches may need restarting.

To uninstall, activate **Original** if you want to restore it, then choose **Settings → Disable System Access** before deleting the app.

## Updates and development

Use **Hostshift → Check for Updates…**, or enable automatic checks in Settings. Available updates open on GitHub for download.

For tests, signing and release setup, see [Developing Hostshift](docs/development.md).

## Licence

Hostshift is free software under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE) for the full text.
