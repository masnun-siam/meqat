import Foundation

public enum Relauncher {
    /// Waits up to 30 s for `pid` to exit, then opens `app`. Arguments go in as `$1`/`$2`, never into the script text.
    /// The limit is wall-clock time: an iteration count drifted to 47 s from fork overhead.
    static let script =
        #"end=$(($(/bin/date +%s)+30)); while /bin/kill -0 "$1" 2>/dev/null && [ "$(/bin/date +%s)" -lt "$end" ]; do /bin/sleep 0.1; done; /usr/bin/open "$2""#

    static func arguments(app: URL, pid: Int32) -> [String] {
        ["-c", script, "sh", String(pid), app.path]
    }

    /// Starts a detached helper that opens `app` once process `pid` has exited. The caller quits afterwards.
    public static func relaunch(
        _ app: URL,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        launcher: ProcessLaunching = ProcessLauncher()
    ) throws {
        try launcher.launch(URL(fileURLWithPath: "/bin/sh"), arguments(app: app, pid: pid))
    }
}
