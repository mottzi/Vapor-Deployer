import Vapor
import Mist

extension Deployment {

    var computedProperties: [String: any SendableEncodable] { [
        "durationString": durationString,
        "displayStatus": displayStatus.rawValue,
        "shortID": shortID,
        "startedAtUnixMs": startedAtUnixMs,
        "canBeDeployed": canBeDeployed,
        "canBuild": canBuild,
        "canRestoreBinary": canRestoreBinary,
        "canTest": canTest,
        "testsPassed": testsPassed,
        "testsFailed": testsFailed,
        "hasSavedBinary": hasSavedBinary,
        "hasDetails": hasDetails,
        "hasLiveOutputStream": hasLiveOutputStream,
        "outputHTML": outputHTML,
    ] }

    var durationString: String? {
        guard let finishedAt, let startedAt else { return nil }
        return String(format: "%.1fs", finishedAt.timeIntervalSince(startedAt))
    }

    static let staleThreshold: TimeInterval = 30 * 60

    var displayStatus: Status {
        if (status == .building || status == .restoring || status == .testing),
           let referenceTime = (status == .testing ? (testStartedAt ?? startedAt) : startedAt),
           Date.now.timeIntervalSince(referenceTime) > Self.staleThreshold {
            .stale
        } else {
            status
        }
    }

    var shortID: String? { id.map { String($0.uuidString.prefix(8)) } }

    var startedAtUnixMs: Int? { startedAt.map { Int($0.timeIntervalSince1970 * 1000) } }

    var canBeDeployed: Bool {
        switch displayStatus {
            case .building: false
            case .testing: false
            case .restoring: false
            case .running: false
            default: true
        }
    }

    var canBuild: Bool {
        canBeDeployed && !hasSavedBinary
    }

    var hasSavedBinary: Bool {
        binarySizeMB != nil
    }

    var canRestoreBinary: Bool {
        canBeDeployed && hasSavedBinary
    }

    /// Test eligibility — permissive. Allowed on every non-actively-transient state, including
    /// `.running` (the live binary is untouched; tests compile into `.build-tests/`). The queue
    /// lock still serializes execution.
    var canTest: Bool {
        switch displayStatus {
            case .building, .testing, .restoring: false
            default: true
        }
    }

    var testsPassed: Bool { lastTestOutcome == true }
    var testsFailed: Bool { lastTestOutcome == false }

    var hasDetails: Bool {
        output != nil || hasLiveOutputStream
    }

    var hasLiveOutputStream: Bool {
        status == .building || status == .testing
    }

    /// HTML-rendered output: escapes user-facing text and, on failure, wraps the failing pipeline section in a red span.
    var outputHTML: String? {
        guard let output, !output.isEmpty else { return nil }
        return status == .failed
            ? Self.wrapFailedSection(in: output)
            : Self.htmlEscape(output)
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Wraps the transcript from the last `──── label ────` marker to the end in a span the CSS can color red.
    /// All content (inside and outside the span) is HTML-escaped; only the controlled `<span>` tags are raw.
    private static func wrapFailedSection(in text: String) -> String {
        guard let range = text.range(of: "──── ", options: .backwards) else {
            return htmlEscape(text)
        }
        let before = String(text[..<range.lowerBound])
        let after = String(text[range.lowerBound...])
        return htmlEscape(before)
            + "<span class=\"dp-section--error\">"
            + htmlEscape(after)
            + "</span>"
    }

}
