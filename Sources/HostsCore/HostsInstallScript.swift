import Foundation
import CryptoKit

public enum HostsInstallScript {
    public static func digest(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func shell(content: String, expected: String) -> String {
        // Only base64 and a SHA-256 digest enter the privileged script, never raw user text.
        let payload = Data(content.utf8).base64EncodedString()
        let hash = digest(expected)
        return """
        set -eu
        export PATH=/usr/bin:/bin:/usr/sbin:/sbin
        target=/private/etc/hosts
        [ -f "$target" ] && [ ! -L "$target" ] || { echo 'The hosts file must be a regular file.' >&2; exit 1; }
        actual=$(/usr/bin/shasum -a 256 "$target")
        [ "${actual%% *}" = '\(hash)' ] || { echo 'The hosts file changed outside Hostshift. Refresh and try again.' >&2; exit 1; }
        temporary=$(/usr/bin/mktemp /private/etc/.hostshift.XXXXXX)
        backup=$(/usr/bin/mktemp /private/etc/.hostshift-backup.XXXXXX)
        trap '/bin/rm -f "$temporary" "$backup"' EXIT
        /usr/bin/printf '%s' '\(payload)' | /usr/bin/base64 -D > "$temporary"
        /usr/sbin/chown root:wheel "$temporary"
        /bin/chmod 644 "$temporary"
        /bin/cp -p "$target" "$backup"
        actual=$(/usr/bin/shasum -a 256 "$target")
        [ "${actual%% *}" = '\(hash)' ] || { echo 'The hosts file changed outside Hostshift. Refresh and try again.' >&2; exit 1; }
        /bin/mv -f "$backup" /private/etc/hosts.hostshift-backup
        /bin/mv -f "$temporary" "$target"
        if /usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder; then
            echo 'Activated. DNS cache refreshed.'
        else
            echo 'Activated. DNS cache could not be refreshed; some apps may need restarting.'
        fi
        """
    }

}
