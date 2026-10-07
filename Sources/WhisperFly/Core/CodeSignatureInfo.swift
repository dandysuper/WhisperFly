import Foundation
import Security

/// What macOS knows about this process's code signature.
///
/// This is the single most important diagnostic for "my permissions keep
/// resetting". TCC keys every grant to the app's **designated requirement**, not
/// to its bundle identifier alone. An ad-hoc signature has no team identity, so
/// its designated requirement falls back to a `cdhash` — a hash of the exact
/// binary. Rebuild the app and the hash changes, macOS sees a different program,
/// and Microphone, Screen Recording and Accessibility all silently reset while
/// System Settings still shows the old toggles switched on.
///
/// Reading our own requirement lets the app tell the user *why* it is happening
/// instead of showing a permission warning that reappears after every update.
struct CodeSignatureInfo: Sendable {

    /// `CFBundleIdentifier` as recorded in the signature.
    let identifier: String?
    /// Ten-character Apple team identifier, absent for ad-hoc signatures.
    let teamIdentifier: String?
    /// The signature carries `kSecCodeSignatureAdhoc`.
    let isAdHoc: Bool
    /// The hardened runtime flag was present at signing time.
    let hasHardenedRuntime: Bool
    /// The requirement TCC matches against, verbatim.
    let designatedRequirement: String?
    /// Hex-encoded primary code directory hash, when the signature has one.
    let cdHash: String?

    /// `true` when the requirement is anchored to an Apple-issued certificate
    /// rather than a single binary hash, i.e. permission grants survive a rebuild.
    var hasStableIdentity: Bool {
        guard !isAdHoc, teamIdentifier != nil else { return false }
        guard let requirement = designatedRequirement else { return false }
        // An ad-hoc or globally-signed executable pins `cdhash` instead of a team.
        return !requirement.contains("cdhash")
    }

    /// Explains, in one sentence, why grants will or will not survive an update.
    var persistenceDiagnosis: String? {
        if hasStableIdentity { return nil }
        if isAdHoc {
            return L("signature.warn.adhoc",
                     "This build is ad-hoc signed, so macOS ties every permission to the exact binary. Each rebuild looks like a brand-new app and all permissions reset. Sign with a Developer ID or Apple Development certificate to fix it.")
        }
        if teamIdentifier == nil {
            return L("signature.warn.no_team",
                     "This build has no Apple team identifier, so macOS cannot recognise future versions as the same app and permissions will reset on the next update.")
        }
        if designatedRequirement?.contains("cdhash") == true {
            return L("signature.warn.cdhash",
                     "This build's designated requirement is pinned to its binary hash, so macOS treats every rebuild as a different app. Re-sign with a certificate so the requirement is anchored to a team identifier.")
        }
        return L("signature.warn.unknown",
                 "This build is not signed in a way macOS can match across updates, so permissions may reset.")
    }

    /// Reads the signature of the running process.
    static func current() -> CodeSignatureInfo {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return CodeSignatureInfo(
                identifier: nil, teamIdentifier: nil, isAdHoc: true,
                hasHardenedRuntime: false, designatedRequirement: nil, cdHash: nil
            )
        }

        var staticCode: SecStaticCode?
        var signingInfo: CFDictionary?
        if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode {
            _ = SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInfo
            )
        }

        let info = signingInfo as? [String: Any] ?? [:]

        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = (flags & Self.flagAdHoc) != 0
        let hardened = (flags & Self.flagRuntime) != 0

        var requirement: SecRequirement?
        var requirementText: String?
        if let staticCode,
           SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
           let requirement {
            var text: CFString?
            if SecRequirementCopyString(requirement, [], &text) == errSecSuccess {
                requirementText = text as String?
            }
        }

        return CodeSignatureInfo(
            identifier: info[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
            isAdHoc: isAdHoc,
            hasHardenedRuntime: hardened,
            designatedRequirement: requirementText,
            cdHash: primaryCDHash(from: info)
        )
    }

    /// `kSecCodeSignatureAdhoc` and `kSecCodeSignatureRuntime` are members of an
    /// anonymous C enum in `CSCommon.h`, which Swift does not surface. They are
    /// stable ABI values that have never changed, so they are declared here
    /// against the header rather than reached for through the framework.
    private static let flagAdHoc: UInt32 = 0x0002
    private static let flagRuntime: UInt32 = 0x10000

    private static func primaryCDHash(from info: [String: Any]) -> String? {
        guard let hashes = info[kSecCodeInfoCdHashes as String] as? [Data],
              let first = hashes.first else { return nil }
        return first.map { String(format: "%02x", $0) }.joined()
    }
}
