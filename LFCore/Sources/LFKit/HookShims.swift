import Foundation

/// Stand-ins for `open` and `osascript`, put first on a hook's `PATH`. When a guardrail hook asks macOS to run
/// something in Terminal, the stand-in runs it right there instead, so its output reaches LF-Git's hook panel and
/// no Terminal window opens. Every other use is handed to the real command unchanged.
public enum HookShims {
    /// Where the app keeps them: `~/Library/Application Support/LF-Git/hook-shims`.
    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("LF-Git/hook-shims", isDirectory: true)
    }

    /// Writes the scripts into `directory` (only when their content changed) and returns `directory`.
    @discardableResult
    public static func install(in directory: URL = defaultDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, script) in [("open", openScript), ("osascript", osascriptScript)] {
            let url = directory.appendingPathComponent(name)
            let data = Data(script.utf8)
            if (try? Data(contentsOf: url)) != data {
                try data.write(to: url, options: .atomic)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return directory
    }

    /// `PATH` with `directory` in front of `path`.
    public static func path(prepending directory: URL, to path: String?) -> String {
        [directory.path, path].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ":")
    }

    // MARK: - Scripts

    /// Shared by both scripts: runs one action in the foreground between a header and a footer, and never fails
    /// the hook (the real `open` / `osascript` would have returned at once).
    private static let runAction = #"""
    lfgit_run() {
        lfgit_label=$1; shift
        printf '── Terminal action: %s ──\n' "$lfgit_label"
        "$@"
        lfgit_status=$?
        printf '── finished (exit %s) ──\n' "$lfgit_status"
    }
    """#

    static let openScript = #"""
    #!/bin/sh
    # LF-Git hook shim for `open`: a script sent to a terminal app runs here instead, so LF-Git shows its output.
    # Anything else goes to the real `open`, unchanged.
    real_open="${LFGIT_REAL_OPEN:-/usr/bin/open}"
    """# + "\n" + runAction + "\n" + #"""
    app=""; bundle=""; file=""; nargs=0
    parse() {
        while [ $# -gt 0 ]; do
            case "$1" in
                -a) [ $# -ge 2 ] || return 1; app=$2; shift 2 ;;
                -b) [ $# -ge 2 ] || return 1; bundle=$2; shift 2 ;;
                -n|-g|-F|-W|--new|--background|--fresh|--wait-apps) shift ;;
                --args) shift; nargs=$#; return 0 ;;
                -*) return 1 ;;
                *) [ -z "$file" ] || return 1; file=$1; shift ;;
            esac
        done
        nargs=0
    }
    is_terminal_app() {
        name=$(basename "$1" .app | tr '[:upper:]' '[:lower:]')
        case "$name" in terminal|iterm|iterm2|warp|ghostty) return 0 ;; esac
        return 1
    }
    is_terminal_bundle() {
        case "$1" in com.apple.Terminal|com.googlecode.iterm2|dev.warp.Warp-Stable|com.mitchellh.ghostty) return 0 ;; esac
        return 1
    }

    parse "$@" || exec "$real_open" "$@"
    inline=1
    [ -n "$file" ] && [ -f "$file" ] || inline=0
    if [ "$inline" = 1 ]; then
        if [ -n "$app" ]; then
            is_terminal_app "$app" || inline=0
        elif [ -n "$bundle" ]; then
            is_terminal_bundle "$bundle" || inline=0
        else
            case "$file" in *.command|*.tool) ;; *) inline=0 ;; esac
        fi
    fi
    [ "$inline" = 1 ] || exec "$real_open" "$@"

    shift $(($# - nargs))
    if [ -x "$file" ]; then
        lfgit_run "$file" "$file" "$@"
    else
        lfgit_run "$file" "${SHELL:-/bin/sh}" "$file" "$@"
    fi
    exit 0
    """#

    static let osascriptScript = #"""
    #!/bin/sh
    # LF-Git hook shim for `osascript`: `tell application "Terminal" to do script "…"` (or iTerm's `write text "…"`)
    # runs the command here instead, so LF-Git shows its output. Anything else goes to the real `osascript`, unchanged.
    real_osascript="${LFGIT_REAL_OSASCRIPT:-/usr/bin/osascript}"
    """# + "\n" + runAction + "\n" + #"""
    script=""
    collect() {
        [ $# -gt 0 ] || return 1
        while [ $# -gt 0 ]; do
            [ "$1" = "-e" ] && [ $# -ge 2 ] || return 1
            script="$script$2
    "
            shift 2
        done
    }
    collect "$@" || exec "$real_osascript" "$@"
    printf '%s' "$script" | grep -Eq 'tell (application|app) "(Terminal|iTerm|iTerm2)"' || exec "$real_osascript" "$@"

    commands=$(mktemp -d "${TMPDIR:-/tmp}/lfgit-osascript.XXXXXX") || exec "$real_osascript" "$@"
    pass() { rm -rf "$commands"; exec "$real_osascript" "$@"; }
    trap 'rm -rf "$commands"' EXIT
    # Each `do script "…"` / `write text "…"` string, unescaped (\" \\ \n \t), into its own file.
    printf '%s' "$script" | awk -v dir="$commands" '
        BEGIN { count = 0; RS = "\001" }
        {
            text = $0
            while (match(text, /(do script|write text)[ \t]+"/)) {
                rest = substr(text, RSTART + RLENGTH)
                command = ""; closed = 0
                for (i = 1; i <= length(rest); i++) {
                    c = substr(rest, i, 1)
                    if (c == "\\" && i < length(rest)) {
                        n = substr(rest, i + 1, 1)
                        if (n == "n") command = command "\n"
                        else if (n == "t") command = command "\t"
                        else command = command n
                        i++
                    } else if (c == "\"") { closed = 1; break }
                    else command = command c
                }
                if (!closed) exit 1
                count++
                file = dir "/" sprintf("%03d", count)
                printf "%s", command > file
                close(file)
                text = substr(rest, i + 1)
            }
        }
    ' || pass "$@"
    ls "$commands"/* >/dev/null 2>&1 || pass "$@"

    for command_file in "$commands"/*; do
        command=$(cat "$command_file")
        lfgit_run "$command" "${SHELL:-/bin/sh}" -c "$command"
    done
    exit 0
    """#
}
