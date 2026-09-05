import Foundation
import Testing

@Suite("Release pipeline validation")
struct ReleasePipelineTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(_ script: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + arguments
        process.currentDirectoryURL = repositoryRoot
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func temporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }

    private func appcast(
        version: String = "1.2.3",
        build: String = "9",
        url: String = "https://github.com/example/sustain/releases/download/v1.2.3/Sustain-1.2.3-9.zip",
        signed: Bool = true
    ) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item>
            <title>Sustain \(version)</title>
            <sparkle:version>\(build)</sparkle:version>
            <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
            <pubDate>Tue, 25 Aug 2026 00:00:00 +0000</pubDate>
            <enclosure url="\(url)" length="1234" type="application/octet-stream" sparkle:edSignature="archive-signature"/>
          </item></channel>
        </rss>\(signed ? """

        <!-- sparkle-signatures:
        edSignature: ZmVlZC1zaWduYXR1cmU=
        length: 1234
        -->
        """ : "")
        """
    }

    @Test func stableSignedAppcastAndMatchingMetadataPass() throws {
        let metadata = try temporaryFile(
            named: "release.json",
            contents: #"{"version":"1.2.3","build":"10","minimumSystemVersion":"14.0.0"}"#
        )
        let feed = try temporaryFile(named: "appcast.xml", contents: appcast())

        #expect(try run("scripts/validate-appcast.sh", [feed.path]) == 0)
        #expect(try run("scripts/validate-release.sh", [metadata.path, "v1.2.3", feed.path]) == 0)
    }

    @Test func versionTagAndMonotonicBuildAreEnforced() throws {
        let metadata = try temporaryFile(
            named: "release.json",
            contents: #"{"version":"1.2.3","build":"9","minimumSystemVersion":"14.0.0"}"#
        )
        let feed = try temporaryFile(named: "appcast.xml", contents: appcast(build: "9"))

        #expect(try run("scripts/validate-release.sh", [metadata.path, "v1.2.4", feed.path]) != 0)
        #expect(try run("scripts/validate-release.sh", [metadata.path, "v1.2.3", feed.path]) != 0)
    }

    @Test func unsignedMalformedAndPrereleaseFeedsFailClosed() throws {
        let unsigned = try temporaryFile(named: "unsigned.xml", contents: appcast(signed: false))
        let malformed = try temporaryFile(named: "malformed.xml", contents: "<rss><channel>")
        let prerelease = try temporaryFile(named: "prerelease.xml", contents: appcast(version: "1.2.3-beta.1"))

        #expect(try run("scripts/validate-appcast.sh", [unsigned.path]) != 0)
        #expect(try run("scripts/validate-appcast.sh", [malformed.path]) != 0)
        #expect(try run("scripts/validate-appcast.sh", [prerelease.path]) != 0)
    }

    @Test func insecureMutableOrUnsignedEnclosuresFailClosed() throws {
        let insecure = try temporaryFile(
            named: "insecure.xml",
            contents: appcast(url: "http://example.test/Sustain.zip")
        )
        let mutable = try temporaryFile(
            named: "mutable.xml",
            contents: appcast(url: "https://github.com/example/sustain/releases/download/latest/Sustain.zip")
        )
        let noArchiveSignature = try temporaryFile(
            named: "no-signature.xml",
            contents: appcast().replacingOccurrences(of: " sparkle:edSignature=\"archive-signature\"", with: "")
        )

        #expect(try run("scripts/validate-appcast.sh", [insecure.path]) != 0)
        #expect(try run("scripts/validate-appcast.sh", [mutable.path]) != 0)
        #expect(try run("scripts/validate-appcast.sh", [noArchiveSignature.path]) != 0)
    }
}
