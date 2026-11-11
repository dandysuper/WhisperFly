import AppKit
import SwiftUI

// Shims for APIs newer than the deployment target (macOS 13 Ventura).
//
// WhisperFly runs on every Mac from 2017 onward, Intel and Apple silicon. The
// floor is macOS 13 because everything the app is built on starts there:
// MenuBarExtra, ScreenCaptureKit audio capture, SMAppService login items and the
// grouped settings forms. Newer APIs are called through these helpers so each
// call site stays one line and the fallback lives in one place.

extension NSApplication {
    /// Brings WhisperFly to the front. `activate()` is macOS 14+; Ventura
    /// needs the older form, which macOS 14 deprecated.
    func activateCompat() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

extension NSRunningApplication {
    /// Brings another app to the front, e.g. the one dictated text goes to.
    @discardableResult
    func activateCompat() -> Bool {
        if #available(macOS 14.0, *) {
            return activate()
        } else {
            return activate(options: [.activateIgnoringOtherApps])
        }
    }
}

extension View {
    /// SF Symbol swap animation (macOS 14+); a plain change on Ventura.
    @ViewBuilder
    func symbolReplaceTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    /// Continuous pulse on an SF Symbol (macOS 14+); an opacity pulse on Ventura.
    @ViewBuilder
    func pulsingSymbol() -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.pulse, options: .repeating)
        } else {
            self.modifier(LegacyPulse())
        }
    }

    /// One bounce whenever `value` changes (macOS 14+); nothing on Ventura.
    @ViewBuilder
    func bounceSymbol<V: Equatable>(on value: V) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}

private struct LegacyPulse: ViewModifier {
    @StateObject private var dimmed = LocalFlag(false)

    func body(content: Content) -> some View {
        content
            .opacity(dimmed.value ? 0.45 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dimmed.value = true
                }
            }
    }
}

/// Facts about the Mac WhisperFly is running on, for diagnostics and for
/// refusing updates this Mac could not open.
enum SystemInfo {

    enum Architecture: String, Sendable {
        case arm64
        case x86_64

        /// The architecture of this process's own slice.
        static var current: Architecture {
            #if arch(arm64)
            return .arm64
            #else
            return .x86_64
            #endif
        }

        /// Matching `Bundle.executableArchitectures` value.
        var bundleConstant: Int {
            switch self {
            case .arm64:  return NSBundleExecutableArchitectureARM64
            case .x86_64: return NSBundleExecutableArchitectureX86_64
            }
        }
    }

    /// `true` on Apple silicon, including when this process runs under Rosetta.
    static var isAppleSiliconHardware: Bool {
        sysctlFlag("hw.optional.arm64")
    }

    /// `true` when an Intel slice is running translated on Apple silicon.
    static var isTranslated: Bool {
        sysctlFlag("sysctl.proc_translated")
    }

    /// Architectures the running binary contains, e.g. both for a universal build.
    static var bundledArchitectures: [Architecture] {
        let values = Bundle.main.executableArchitectures?.map(\.intValue) ?? []
        var result: [Architecture] = []
        if values.contains(NSBundleExecutableArchitectureARM64) { result.append(.arm64) }
        if values.contains(NSBundleExecutableArchitectureX86_64) { result.append(.x86_64) }
        return result.isEmpty ? [Architecture.current] : result
    }

    static var osVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    /// `macOS 15.6.1`
    static var osDescription: String {
        let v = osVersion
        return v.patchVersion > 0
            ? "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// `Apple silicon`, `Intel`, or `Apple silicon (Intel build under Rosetta)`,
    /// plus whether the app itself is universal.
    static var hardwareDescription: String {
        var text: String
        if isTranslated {
            text = L("system.hardware.rosetta", "Apple silicon (running the Intel version under Rosetta)")
        } else if isAppleSiliconHardware {
            text = L("system.hardware.apple_silicon", "Apple silicon")
        } else {
            text = L("system.hardware.intel", "Intel")
        }
        if bundledArchitectures.count > 1 {
            text += " · " + L("system.build.universal", "universal app")
        }
        return text
    }

    /// `true` when Liquid Glass is in use rather than the pre-macOS 26 materials.
    @MainActor static var usesLiquidGlass: Bool { LiquidGlassSupport.isActive }

    private static func sysctlFlag(_ name: String) -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 && value == 1
    }
}

/// Whether a downloaded build can run on this Mac. Checked before an update
/// replaces the installed app, so a future release that drops Intel or an old
/// macOS can never leave the user with an app that will not open.
enum UpdateCompatibility: Equatable, Sendable {
    case compatible
    case requiresNewerSystem(minimum: String)
    case missingArchitecture(SystemInfo.Architecture)

    static func evaluate(
        minimumSystemVersion: String?,
        architectures: [Int],
        currentSystem: OperatingSystemVersion,
        currentArchitecture: SystemInfo.Architecture,
        canTranslate: Bool
    ) -> UpdateCompatibility {
        if let minimum = minimumSystemVersion?.trimmingCharacters(in: .whitespaces), !minimum.isEmpty {
            let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
            let required = OperatingSystemVersion(
                majorVersion: parts.count > 0 ? parts[0] : 0,
                minorVersion: parts.count > 1 ? parts[1] : 0,
                patchVersion: parts.count > 2 ? parts[2] : 0
            )
            if compare(currentSystem, required) == .orderedAscending {
                return .requiresNewerSystem(minimum: minimum)
            }
        }

        // An empty list means the bundle could not be read; let the install's
        // own checks decide rather than guessing.
        guard !architectures.isEmpty else { return .compatible }
        if architectures.contains(currentArchitecture.bundleConstant) { return .compatible }
        // Apple silicon can run an Intel-only build through Rosetta.
        if currentArchitecture == .arm64, canTranslate,
           architectures.contains(NSBundleExecutableArchitectureX86_64) {
            return .compatible
        }
        return .missingArchitecture(currentArchitecture)
    }

    /// Inspects an `.app` on disk against the running Mac.
    static func evaluate(appAt url: URL) -> UpdateCompatibility {
        let bundle = Bundle(url: url)
        let minimum = bundle?.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        let architectures = bundle?.executableArchitectures?.map(\.intValue) ?? []
        // The *hardware* architecture: an Intel slice under Rosetta must still
        // accept an arm64-only update, because the update will run natively.
        let hardware: SystemInfo.Architecture = SystemInfo.isAppleSiliconHardware ? .arm64 : .x86_64
        return evaluate(
            minimumSystemVersion: minimum,
            architectures: architectures,
            currentSystem: SystemInfo.osVersion,
            currentArchitecture: hardware,
            canTranslate: hardware == .arm64
        )
    }

    private static func compare(_ a: OperatingSystemVersion, _ b: OperatingSystemVersion) -> ComparisonResult {
        for (x, y) in [(a.majorVersion, b.majorVersion), (a.minorVersion, b.minorVersion), (a.patchVersion, b.patchVersion)] {
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }
}
