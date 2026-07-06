import Foundation
import SPPDeviceKit

// MARK: - InjectionPreflightResult

public struct InjectionPreflightResult: Sendable {

    public enum CheckStatus: String, Sendable, Hashable {
        case pass, fail, warn, skip
    }

    public struct Check: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let detail: String
        public let status: CheckStatus
    }

    public let checks: [Check]

    public var passed: Bool   { !checks.contains { $0.status == .fail } }
    public var failCount: Int { checks.filter    { $0.status == .fail }.count }
    public var warnCount: Int { checks.filter    { $0.status == .warn }.count }
    public var passCount: Int { checks.filter    { $0.status == .pass }.count }

    public var summary: String {
        if failCount > 0 { return "\(failCount) check\(failCount == 1 ? "" : "s") failed" }
        if warnCount > 0 { return "Ready with \(warnCount) warning\(warnCount == 1 ? "" : "s")" }
        return "All checks passed"
    }
}

// MARK: - InjectionPreflightService

/// Verifies all preconditions required before attempting simulator injection.
///
/// Ownership: injection state only. Does not own build state (read via artifact path
/// passed in) or simulator session state (read via SimulatorTarget passed in).
@MainActor
public final class InjectionPreflightService: ObservableObject {

    // MARK: - Published

    @Published public var result: InjectionPreflightResult?
    @Published public var isRunning = false
    @Published public var logs: [String] = []

    // MARK: - Dependencies

    private let discovery = SimulatorDiscoveryService()

    public init() {}

    // MARK: - Run

    /// Run all preflight checks.
    ///
    /// - Parameters:
    ///   - target:      The selected simulator target (nil if nothing selected).
    ///   - bundleID:    Bundle ID of the target app process (nil or empty if not specified).
    ///   - packageURL: The built .deb package (nil if no build ran yet).
    ///   - dylibURL:   The raw .dylib from .theos/obj/ (nil if no build ran yet).
    public func run(
        target: SimulatorTarget?,
        bundleID: String?,
        packageURL: URL?,
        dylibURL: URL?
    ) async {
        guard !isRunning else { return }
        isRunning = true
        result    = nil
        logs      = []
        defer { isRunning = false }

        var checks: [InjectionPreflightResult.Check] = []

        // ── Check 1: xcrun present ────────────────────────────────────────────

        let xcrunPath = "/usr/bin/xcrun"
        let xcrunPresent = FileManager.default.isExecutableFile(atPath: xcrunPath)
        checks.append(.init(
            name:   "xcrun available",
            detail: xcrunPresent ? xcrunPath
                                 : "Not found at \(xcrunPath) — install Xcode Command Line Tools",
            status: xcrunPresent ? .pass : .fail
        ))
        log(xcrunPresent ? "✓ xcrun: \(xcrunPath)" : "✗ xcrun not found — install Xcode CLT")

        // ── Check 2: simctl responds ──────────────────────────────────────────

        if xcrunPresent {
            let ping = await pingSimctl()
            checks.append(.init(
                name:   "xcrun simctl usable",
                detail: ping.detail,
                status: ping.ok ? .pass : .fail
            ))
            log(ping.ok ? "✓ simctl: \(ping.detail)" : "✗ simctl:\n  \(ping.logDetail)")
        } else {
            checks.append(.init(
                name: "xcrun simctl usable", detail: "Skipped — xcrun unavailable", status: .skip
            ))
        }

        // ── Check 3: simulator target selected ───────────────────────────────

        guard let target else {
            checks.append(.init(
                name:   "Simulator selected",
                detail: "No simulator target selected — pick one in the Simulator tab",
                status: .fail
            ))
            log("✗ No simulator target selected")
            result = InjectionPreflightResult(checks: checks)
            return
        }
        checks.append(.init(
            name:   "Simulator selected",
            detail: "\(target.displayName)  [\(target.udid)]",
            status: .pass
        ))
        log("✓ Target: \(target.displayName) [\(target.udid)]")

        // ── Check 4: live boot state ──────────────────────────────────────────
        // Re-checked from xcrun, not from cached SimulatorService state.

        log("  Re-checking boot state for \(target.udid)…")
        let (usable, usabilityReason) = await discovery.checkUsability(
            udid: target.udid, name: target.name
        )
        checks.append(.init(
            name:   "Simulator booted",
            detail: usabilityReason,
            status: usable ? .pass : .fail
        ))
        log(usable ? "✓ \(usabilityReason)" : "✗ \(usabilityReason)")

        // ── Check 5: target bundle ID ─────────────────────────────────────────

        let trimmedBundleID = bundleID?.trimmingCharacters(in: .whitespaces) ?? ""
        let hasBundleID = !trimmedBundleID.isEmpty
        checks.append(.init(
            name:   "Injection target (bundle ID)",
            detail: hasBundleID
                ? trimmedBundleID
                : "No bundle ID — specify which app to inject into",
            status: hasBundleID ? .pass : .warn
        ))
        log(hasBundleID ? "✓ Bundle ID: \(trimmedBundleID)" : "⚠ No bundle ID specified")

        // ── Check 6: .deb package (informational — install path, not injection path) ──

        if let deb = packageURL {
            let debExists = FileManager.default.fileExists(atPath: deb.path)
            checks.append(.init(
                name:   ".deb package",
                detail: debExists ? deb.path : "Not found: \(deb.path)",
                status: debExists ? .pass : .fail
            ))
            log(debExists ? "✓ .deb: \(deb.path)" : "✗ .deb missing: \(deb.path)")
        } else {
            checks.append(.init(
                name:   ".deb package",
                detail: "No package built yet — run Build (⌘B) first",
                status: .warn
            ))
            log("⚠ No .deb — build not run")
        }

        // ── Check 7: raw .dylib — the actual injection artifact ───────────────

        var dylibPlatformOK = true
        if let dylib = dylibURL {
            let dylibExists = FileManager.default.fileExists(atPath: dylib.path)
            checks.append(.init(
                name:   "Raw .dylib (injection artifact)",
                detail: dylibExists ? dylib.path : "Not found: \(dylib.path)",
                status: dylibExists ? .pass : .fail
            ))
            log(dylibExists ? "✓ dylib: \(dylib.path)" : "✗ dylib missing: \(dylib.path)")

            // ── Check 8: injection method ─────────────────────────────────────

            if dylibExists {
                checks.append(.init(
                    name:   "Injection method",
                    detail: "SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=\(dylib.lastPathComponent) (parent-env prefix)",
                    status: .pass
                ))
                log("✓ Injection: SIMCTL_CHILD_DYLD_INSERT_LIBRARIES via parent environment")

                // ── Check 8b: dylib platform / architecture (read-only) ───────────
                // Arch alone can't distinguish device vs simulator on Apple Silicon
                // (both are arm64/arm64e). The Mach-O LC_BUILD_VERSION *platform*
                // field is the decisive signal. A device (iphoneos) image will NOT
                // map into a simulator process via DYLD_INSERT_LIBRARIES.
                let probe = await inspectDylibPlatform(at: dylib)
                checks.append(.init(
                    name:   "Dylib platform / arch",
                    detail: probe.detail,
                    status: probe.status
                ))
                log((probe.status == .fail ? "✗ " : probe.status == .warn ? "⚠ " : "✓ ") + probe.detail)
                dylibPlatformOK = probe.status != .fail
            }
        } else {
            checks.append(.init(
                name:   "Raw .dylib (injection artifact)",
                detail: "Not tracked — build the project first. Expected at .theos/obj/<name>.dylib",
                status: packageURL != nil ? .fail : .warn
            ))
            log(packageURL != nil
                ? "✗ dylib missing despite successful build — check .theos/obj/"
                : "⚠ dylib unknown — run build first")
        }

        // ── Check 9: injection command preview ───────────────────────────────

        if usable && hasBundleID && dylibPlatformOK, let dylib = dylibURL,
           FileManager.default.fileExists(atPath: dylib.path) {
            let cmd = "SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=\(dylib.path)"
                + " xcrun simctl launch --terminate-running-process"
                + " \(target.udid) \(trimmedBundleID)"
            checks.append(.init(
                name:   "Injection command (ready)",
                detail: cmd,
                status: .pass
            ))
            log("Command:\n  \(cmd)")
        }

        // ── Summary ──────────────────────────────────────────────────────────

        let r = InjectionPreflightResult(checks: checks)
        result = r
        log("─────────────────────────────────────────")
        log("Preflight: \(r.passCount) pass  \(r.warnCount) warn  \(r.failCount) fail")
        log(r.passed ? "✓ READY" : "✗ NOT READY")
    }

    // MARK: - Dylib platform inspection (read-only)

    /// Inspects a Mach-O dylib with read-only tools (`lipo -info`, `otool -l`) to
    /// determine whether it targets the iOS Simulator. Never modifies the file.
    ///
    /// The Mach-O LC_BUILD_VERSION `platform` field is authoritative:
    ///   2 = iOS (device)   7 = iOS Simulator   1 = macOS   6 = Mac Catalyst …
    /// Architecture (arm64/arm64e) is identical for device and Apple-Silicon
    /// simulator, so it cannot distinguish them — only the platform field can.
    private func inspectDylibPlatform(at url: URL) async -> (status: InjectionPreflightResult.CheckStatus, detail: String) {
        let archs   = await readArchitectures(at: url)
        let loadCmds = await readLoadCommands(at: url)
        let platforms = parsePlatforms(from: loadCmds)
        let archStr = archs.isEmpty ? "unknown arch" : archs.joined(separator: " ")

        // Decisive: an explicit iOS Simulator platform means it can map.
        if platforms.contains(7) {
            return (.pass, "iOS Simulator image (platform 7) — arch: \(archStr). Simulator-compatible.")
        }

        // Device image (or legacy iphoneos min-version with no simulator platform).
        let looksDevice = platforms.contains(2)
            || (platforms.isEmpty && loadCmds.contains("LC_VERSION_MIN_IPHONEOS"))
        if looksDevice {
            return (.fail,
                "Built dylib appears to target iphoneos/device, not iphonesimulator. "
                + "Simulator injection will not map this image. "
                + "(arch: \(archStr); platform: \(platformNames(platforms)))")
        }

        // Some other platform (macOS, Catalyst, tvOS sim, …) or undeterminable.
        if platforms.isEmpty {
            return (.warn,
                "Could not determine platform (no LC_BUILD_VERSION) — arch: \(archStr). "
                + "Simulator compatibility unverified.")
        }
        return (.warn,
            "Dylib platform is \(platformNames(platforms)), not iOS Simulator — arch: \(archStr). "
            + "Simulator injection may not map this image.")
    }

    /// `lipo -info <dylib>` → ["arm64", "arm64e"]. Falls back to empty on error.
    private func readArchitectures(at url: URL) async -> [String] {
        let out = await ProcessRunner.run(executable: "/usr/bin/lipo", arguments: ["-info", url.path]).stdout
        // Output forms:
        //   "Architectures in the fat file: <path> are: arm64 arm64e"
        //   "Non-fat file: <path> is architecture: arm64"
        guard let tail = out.split(separator: ":").last else { return [] }
        return tail.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// `otool -l <dylib>` load-command dump (per-arch slices concatenated).
    private func readLoadCommands(at url: URL) async -> String {
        await ProcessRunner.run(executable: "/usr/bin/otool", arguments: ["-l", url.path]).stdout
    }

    /// Collects every `platform <N>` integer appearing under LC_BUILD_VERSION.
    private func parsePlatforms(from loadCommands: String) -> Set<Int> {
        var result = Set<Int>()
        for raw in loadCommands.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("platform ") else { continue }
            if let n = Int(line.dropFirst("platform ".count).trimmingCharacters(in: .whitespaces)) {
                result.insert(n)
            }
        }
        return result
    }

    private func platformNames(_ platforms: Set<Int>) -> String {
        let names = platforms.sorted().map { p -> String in
            switch p {
            case 1:  return "macOS"
            case 2:  return "iOS (device)"
            case 3:  return "tvOS"
            case 4:  return "watchOS"
            case 6:  return "Mac Catalyst"
            case 7:  return "iOS Simulator"
            case 8:  return "tvOS Simulator"
            case 9:  return "watchOS Simulator"
            case 11: return "visionOS"
            case 12: return "visionOS Simulator"
            default: return "platform \(p)"
            }
        }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    // MARK: - Helpers

    private struct SimctlPing {
        let ok: Bool
        /// Shown in the check row — the exact status or failure reason.
        let detail: String
        /// Verbose form for the log (full command + stderr).
        let logDetail: String
    }

    /// Pings `simctl` through a resolved full-Xcode toolchain and reports the
    /// real outcome — the exact command, exit code, and stderr on failure —
    /// rather than collapsing everything into a generic error.
    private func pingSimctl() async -> SimctlPing {
        guard let devDir = SimulatorToolchain.developerDir() else {
            let detail = "No full Xcode found. simctl ships only with Xcode.app, "
                + "not the Command Line Tools. Install Xcode, then run: "
                + "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
            return SimctlPing(ok: false, detail: detail,
                              logDetail: "no Xcode.app with simctl found (xcode-select currently targets Command Line Tools)")
        }
        let result = await ProcessRunner.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "help"],
            environment: SimulatorToolchain.processEnvironment()
        )
        if result.succeeded {
            return SimctlPing(ok: true,
                              detail: "simctl responded via \(devDir)",
                              logDetail: "simctl usable (DEVELOPER_DIR=\(devDir))")
        }
        let err = result.stderr.isEmpty
            ? (result.stdout.isEmpty ? "no output" : result.stdout)
            : result.stderr
        return SimctlPing(
            ok: false,
            detail: "simctl failed (exit \(result.exitCode)): \(err)",
            logDetail: "$ \(result.command)\n  → exit \(result.exitCode): \(err)"
        )
    }

    private func log(_ message: String) {
        let ts = timestampString()
        logs.append("[\(ts)] \(message)")
    }

    private func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
