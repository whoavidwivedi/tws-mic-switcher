import Foundation

public enum Updater {
    public static let repositoryURL = "https://github.com/whoavidwivedi/tws-mic-switcher"

    private static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tws-mic-switcher", isDirectory: true)
    }

    public static func run(checkOnly: Bool) -> Int32 {
        let fileManager = FileManager.default
        let installPath = installDirectory.path

        guard fileManager.fileExists(atPath: installPath + "/.git") else {
            fputs("""
            error: no managed installation found at \(installPath)

            Install or repair it with:
              curl -fsSL \(repositoryURL)/raw/main/install.sh | bash

            """, stderr)
            return 1
        }

        print("Checking for updates...")
        guard let latest = latestReleaseTag() else {
            fputs("error: could not check \(repositoryURL). Check your network connection.\n", stderr)
            return 1
        }

        if compareVersions(latest, appVersion) <= 0 {
            print("Already up to date (v\(appVersion)).")
            return 0
        }

        print("Update available: v\(appVersion) -> \(latest)")
        if checkOnly {
            return 0
        }

        let installer = installPath + "/install.sh"
        guard fileManager.fileExists(atPath: installer) else {
            fputs("error: installer not found at \(installer). Re-run the one-line installer.\n", stderr)
            return 1
        }

        print("==> Updating the background service (it will restart)...")
        let status = runInheritingOutput("/bin/bash", [installer])
        guard status == 0 else {
            fputs("error: update failed (exit \(status)). The previous installation was left in place.\n", stderr)
            return status
        }

        print("Updated to \(latest).")
        return 0
    }

    public static func latestReleaseTag() -> String? {
        guard let output = runCapturing("/usr/bin/git", [
            "-C", installDirectory.path,
            "ls-remote", "--tags", "--refs", "origin", "v*"
        ]) else {
            return nil
        }

        let tags = output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[1].hasPrefix("refs/tags/") else {
                return nil
            }
            return String(parts[1].dropFirst("refs/tags/".count))
        }

        return tags.max { compareVersions($0, $1) < 0 }
    }

    public static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = numericComponents(lhs)
        let right = numericComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l < r ? -1 : 1
            }
        }
        return 0
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    private static func runCapturing(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func runInheritingOutput(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            return 1
        }

        process.waitUntilExit()
        return process.terminationStatus
    }
}
