# Hostshift command line

`hostshift` manages the same profiles as the Hostshift app and activates them through the same helper. `hs` is an optional short name for it. This page is the full reference; `hostshift help <command>` shows each command's options.

## Before you start

- Activating a profile replaces the whole `/etc/hosts` file. Each switch saves the file it replaced to `/private/etc/hosts.hostshift-backup`.
- System access must be enabled once in the Hostshift app. The command line can check it but can't set it up. `hostshift status` reports it.
- **Original** is the read-only snapshot of `/etc/hosts` from the first launch. It can be shown, copied and activated, but not changed, renamed or deleted.
- Changes are saved immediately. The command line has no drafts, and the app picks up its changes within a few seconds.

## Install

With Homebrew:

```sh
brew trust --cask dmallory42/tap/hostshift
brew install --cask dmallory42/tap/hostshift
```

Recent versions of Homebrew only load casks from other taps after you trust them. Skip the first line if your Homebrew has no `trust` command.

If you installed Hostshift from the disk image, link the command into a folder on your PATH. **Settings → Command Line** in the app shows these commands with the app's actual location:

```sh
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/Hostshift.app/Contents/MacOS/Hostshift /usr/local/bin/hostshift
```

To add the short `hs` alias as well:

```sh
sudo ln -s /Applications/Hostshift.app/Contents/MacOS/Hostshift /usr/local/bin/hs
```

Other tools also use `hs`, including Hammerspoon and npm's `http-server`. Plain `ln -s` refuses to replace an existing `hs`, so the command above fails instead of overwriting one. To remove the alias later, check that it points into Hostshift.app, then delete the link:

```sh
ls -l "$(command -v hs)"
rm "$(command -v hs)"   # add sudo for /usr/local/bin
```

Removing `hs` leaves `hostshift` working. Remove both links before deleting the app, or they will point at nothing.

Shell completion, including profile names, is available for zsh, bash and fish:

```sh
hostshift --generate-completion-script zsh > ~/.zfunc/_hostshift
```

Put the file in a folder on your `fpath`. For bash or fish, pass `bash` or `fish` instead of `zsh`.

## Choosing a profile

Commands that take `<profile>` match it in this order:

1. An exact name.
2. A unique case-insensitive name.
3. `--id <prefix>`, the start of a profile's ID from `hostshift list --json`. Pass a name or `--id`, not both.

When more than one profile matches, the command fails and lists their IDs. Names with spaces need quoting: `hostshift activate "Local dev"`.

## Commands

| Command | What it does |
|---|---|
| `status [--json]` | Shows the active profile, whether `/etc/hosts` has unsaved external changes, and whether system access is ready. |
| `list [--json]` | Lists profiles, marking the active one and Original. |
| `show <profile> [--json]` | Prints the profile's content exactly as saved, with no added newline. |
| `activate <profile> [--replace \| --save-current] [--json]` | Validates the profile and replaces `/etc/hosts` with it. Activating the active profile does nothing and reports `"changed": false`. |
| `new <name> [--from <path> \| --from -] [--json]` | Creates a profile from a file, from stdin, or from Original's content without `--from`. |
| `duplicate <profile> [--json]` | Copies a profile as "Copy of …", numbered if that name is taken. |
| `capture [--json]` | Saves the current `/etc/hosts` as "Copy of /etc/hosts". |
| `rename <profile> <new-name> [--json]` | Renames a profile. With `--id`, the only argument is the new name: `rename --id 3f2a "Staging"`. |
| `set <profile> --from <path> \| --from - [--json]` | Replaces a profile's content. |
| `edit <profile> [--activate] [--json]` | Opens the profile in `$VISUAL` or `$EDITOR`, then saves it. Needs a terminal. |
| `export <profile> [-o <path>]` | Writes the content to a file, replacing it if it exists, or to stdout. |
| `delete <profile> [--yes] [--json]` | Deletes a profile after confirmation. Original and the active profile can't be deleted. |
| `validate <profile> \| --file <path> \| --file - [--json]` | Reports entries that would block activation. |

Typed names are kept as typed, after trimming spaces at the ends. `new` and `rename` refuse a name that another profile already uses, so names stay unambiguous.

Content is read and written as exact UTF-8 text. Tabs, spaces, line endings and comments are never changed. Profiles are limited to 96 KB. A profile with problems can be saved, as in the app, with a warning on stderr; only activation is blocked.

### External changes

If `/etc/hosts` matches neither a saved profile nor the last activation, another app or a manual edit changed it, and activating would discard that. In a terminal, `activate` asks whether to save those changes as a profile first, replace them, or cancel. Without a terminal, it exits with code 3 and leaves `/etc/hosts` unchanged unless you pass one of:

- `--save-current` saves the current file as "Copy of /etc/hosts", then activates.
- `--replace` discards it and activates.

### Editing

`edit` copies the profile to a private temporary file, opens your editor and waits for it to exit. Editors that open a window must wait for the file to close, for example `EDITOR="code --wait"` or `EDITOR="subl -w"`. If the file is unchanged, nothing is saved. If the edited content has problems, `edit` lists them and asks whether to edit again, save anyway or discard. Scripts should use `show` and `set --from` instead.

## Scripts and agents

- Pass `--json` to any command that prints output. JSON goes to stdout; messages and warnings go to stderr.
- Without a terminal on stdin and stderr, no command prompts. A command that needs a decision exits with code 3 and the message names the flag to pass (`--replace`, `--save-current` or `--yes`).
- With `--json`, errors are written to stderr as `{"code": 1, "error": "…"}`.
- `activate` is safe to repeat: it returns `"changed": false` when the profile is already active.
- Check `status --json` before activating if you need to know whether system access is ready (`"systemAccess": "ready"`).

A typical sequence:

```sh
hostshift status --json
printf '127.0.0.1\tapi.test\n' | hostshift new "API" --from - --json
hostshift validate "API" --json
hostshift activate "API" --save-current --json
hostshift activate Original --json   # restore the starting configuration
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success, including help and `--version`. |
| 1 | The command failed, for example an unknown profile, a refused change or a helper error. |
| 2 | Usage error: unknown command, missing or conflicting arguments, or `edit` without a terminal. |
| 3 | Needs a decision. Rerun with the flag named in the message. |
| 4 | System access isn't ready. Enable it in the Hostshift app. |
| 5 | The profile has problems that block activation, or `validate` found problems. |

### JSON output

A profile summary appears in most results:

```json
{ "id": "3f2a…", "name": "API", "isActive": true, "isOriginal": false }
```

IDs are lowercase UUIDs. Keys are sorted, and optional values are `null` instead of missing.

| Command | Result |
|---|---|
| `status` | `{"active": summary or null, "hosts": "matches" \| "differs" \| "unreadable", "externalChanges": bool, "systemAccess": "ready" \| "needsApproval" \| "notEnabled" \| "needsReenabling" \| "unavailable"}` |
| `list` | `{"profiles": [summary, …]}` in the app's sidebar order |
| `show` | `{"profile": summary, "content": "…"}` |
| `activate` | `{"profile": summary, "changed": bool, "warning": string or null}`. A warning means the switch worked but something else didn't, such as the DNS cache refresh. |
| `new`, `duplicate`, `capture`, `rename`, `set`, `edit` | `{"profile": summary, "diagnostics": [diagnostic, …]}` |
| `delete` | `{"deleted": summary}` |
| `validate` | `{"valid": bool, "diagnostics": [diagnostic, …]}` |

A diagnostic is `{"line": number or null, "message": "…"}`. Lines are numbered from 1, as in the app's editor, and `line` is `null` for problems with the whole file, such as its size.
