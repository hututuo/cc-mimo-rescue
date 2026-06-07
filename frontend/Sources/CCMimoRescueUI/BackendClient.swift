import Foundation

struct BackendClient {
    let backendRoot: URL

    init() {
        backendRoot = Self.findBackendRoot()
    }

    func run<T: Decodable>(_ arguments: [String], as type: T.Type) async throws -> T {
        let data = try await runRaw(arguments)
        return try JSONDecoder().decode(type, from: data)
    }

    func runRaw(_ arguments: [String]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.currentDirectoryURL = backendRoot
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONPATH"] = backendRoot.appendingPathComponent("src").path
            process.environment = environment
            process.arguments = ["-m", "cc_mimo_rescue"] + arguments + ["--json"]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let stderrText = String(data: err, encoding: .utf8) ?? "Unknown backend error"
                throw BackendError.commandFailed(stderrText)
            }
            return out
        }.value
    }
}

enum BackendError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message
        }
    }
}

private extension BackendClient {
    static func findBackendRoot() -> URL {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["CC_MIMO_RESCUE_BACKEND"] {
            let overrideURL = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            if isBackendRoot(overrideURL) {
                return overrideURL
            }
        }

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("backend"), isBackendRoot(bundled) {
            return bundled
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("backend"),
            cwd.deletingLastPathComponent().appendingPathComponent("backend"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("backend")
        ]

        if let found = candidates.first(where: isBackendRoot) {
            return found
        }

        return cwd.appendingPathComponent("backend")
    }

    static func isBackendRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("src/cc_mimo_rescue/__main__.py").path)
    }
}
