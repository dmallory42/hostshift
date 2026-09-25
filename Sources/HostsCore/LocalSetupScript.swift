import Foundation

public enum LocalSetupScript {
    public static func quote(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\\''") + "'"
    }

    public static func install(helperURL: URL, registration: LocalRegistration) throws -> String {
        let data = try JSONEncoder().encode(registration).base64EncodedString()
        let plist: [String: Any] = [
            "Label": HelperIdentity.serviceName,
            "ProgramArguments": [LocalRegistration.executable, "--local"],
            "MachServices": [HelperIdentity.serviceName: true],
            "ProcessType": "Interactive"
        ]
        let daemon = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).base64EncodedString()
        return """
        set -eu
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        directory=\(quote(LocalRegistration.directory))
        [ ! -L "$directory" ] || { echo 'The Hostshift setup directory is a symlink.' >&2; exit 1; }
        /bin/mkdir -p "$directory" /Library/PrivilegedHelperTools /Library/LaunchDaemons
        for folder in "$directory" /Library/PrivilegedHelperTools /Library/LaunchDaemons; do
            [ ! -L "$folder" ] && [ "$(/usr/bin/stat -f %u "$folder")" = 0 ] || { echo 'Setup needs root-owned directories.' >&2; exit 1; }
        done
        /bin/chmod 755 "$directory"
        staged=$(/usr/bin/mktemp /Library/PrivilegedHelperTools/.hostshift.XXXXXX)
        settings=$(/usr/bin/mktemp "$directory/.registration.XXXXXX")
        daemon=$(/usr/bin/mktemp /Library/LaunchDaemons/.hostshift.XXXXXX)
        trap '/bin/rm -f "$staged" "$settings" "$daemon"' EXIT
        /bin/cp \(quote(helperURL.path)) "$staged"
        /usr/bin/codesign --verify --strict -R \(quote("=" + registration.helperRequirement)) "$staged"
        /usr/bin/printf '%s' '\(data)' | /usr/bin/base64 -D > "$settings"
        /usr/bin/printf '%s' '\(daemon)' | /usr/bin/base64 -D > "$daemon"
        /usr/sbin/chown root:wheel "$staged" "$settings" "$daemon"
        /bin/chmod 755 "$staged"
        /bin/chmod 644 "$settings" "$daemon"
        if /bin/launchctl print system/local.hostshift.helper >/dev/null 2>&1; then
            /bin/launchctl bootout system/local.hostshift.helper
        fi
        /bin/mv -f "$settings" \(quote(LocalRegistration.path))
        /bin/mv -f "$staged" \(quote(LocalRegistration.executable))
        /bin/mv -f "$daemon" \(quote(LocalRegistration.daemon))
        /bin/launchctl enable system/local.hostshift.helper
        /bin/launchctl bootstrap system \(quote(LocalRegistration.daemon))
        """
    }

    public static var uninstall: String {
        """
        set -eu
        if /bin/launchctl print system/local.hostshift.helper >/dev/null 2>&1; then
            /bin/launchctl bootout system/local.hostshift.helper
        fi
        /bin/rm -f '\(LocalRegistration.daemon)' '\(LocalRegistration.executable)' '\(LocalRegistration.path)'
        """
    }

    public static func appleScript(_ shell: String) -> String {
        let escaped = shell.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\n", with: "\\n")
        return "do shell script \"\(escaped)\" with administrator privileges without altering line endings"
    }
}
