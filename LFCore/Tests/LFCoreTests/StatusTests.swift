import Testing
import LFCore
@testable import LFKit

@Suite("lf_status")
struct StatusTests {
    @Test("every known status has a distinct, non-empty description")
    func knownStatusesHaveDistinctDescriptions() {
        // Arrange
        let statuses: [lf_status] = [
            LF_OK, LF_ERR_INVALID_ARGUMENT, LF_ERR_IO, LF_ERR_NO_MEMORY,
            LF_ERR_MALFORMED, LF_ERR_UNRESOLVED, LF_ERR_UNSUPPORTED, LF_ERR_CHANGED,
        ]

        // Act
        let descriptions = statuses.map { String(cString: lf_status_string($0)) }

        // Assert
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(Set(descriptions).count == statuses.count)
    }

    @Test("an out-of-range status maps to a fallback description")
    func unknownStatusFallsBack() {
        let description = String(cString: lf_status_string(lf_status(rawValue: 9999)))

        #expect(description == "unknown status")
    }

    @Test("LFError wraps a failing status and keeps its message")
    func lfErrorWrapsStatus() {
        let error = LFError(status: LF_ERR_IO)

        #expect(error.status == LF_ERR_IO)
        #expect(error.message == String(cString: lf_status_string(LF_ERR_IO)))
    }

    @Test("check passes through success and throws on failure")
    func checkThrowsOnlyOnFailure() throws {
        try LFError.check(LF_OK)

        #expect(throws: LFError.self) {
            try LFError.check(LF_ERR_MALFORMED)
        }
    }
}

@Suite("version")
struct VersionTests {
    @Test("Swift version matches the C library version")
    func swiftVersionMatchesC() {
        let cVersion = String(cString: lf_version_string())

        #expect(LFKitInfo.version == cVersion)
        #expect(cVersion.split(separator: ".").count == 3)
    }
}
