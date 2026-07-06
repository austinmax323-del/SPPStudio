import XCTest
@testable import SPPCore

final class DiagnosticModelTests: XCTestCase {

    func testSeverityOrdering() {
        XCTAssertTrue(Diagnostic.Severity.note < .warning)
        XCTAssertTrue(Diagnostic.Severity.warning < .error)
        XCTAssertEqual([Diagnostic.Severity.warning, .error, .note].max(), .error)
    }

    func testContentDerivedIdentity() {
        let a = Diagnostic(line: 12, column: 5, severity: .error, message: "boom")
        let b = Diagnostic(line: 12, column: 5, severity: .error, message: "boom")
        let c = Diagnostic(line: 12, column: 6, severity: .error, message: "boom")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.id, b.id)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a.id, c.id)
    }

    func testClampsLineAndColumnToOneBased() {
        let d = Diagnostic(line: 0, column: 0, severity: .warning, message: "x")
        XCTAssertEqual(d.line, 1)
        XCTAssertEqual(d.column, 1)
    }
}

final class DiagnosticsParserTests: XCTestCase {

    func testParsesClangErrorWithColumn() {
        let p = DiagnosticsParser.parse(line: "/proj/Sources/Tweak.xm:12:5: error: use of undeclared identifier 'foo'")
        XCTAssertEqual(p?.path, "/proj/Sources/Tweak.xm")
        XCTAssertEqual(p?.diagnostic.line, 12)
        XCTAssertEqual(p?.diagnostic.column, 5)
        XCTAssertEqual(p?.diagnostic.severity, .error)
        XCTAssertEqual(p?.diagnostic.message, "use of undeclared identifier 'foo'")
    }

    func testParsesWarningWithoutColumn() {
        let p = DiagnosticsParser.parse(line: "Sources/main.swift:3: warning: unused variable 'x'")
        XCTAssertEqual(p?.path, "Sources/main.swift")
        XCTAssertEqual(p?.diagnostic.line, 3)
        XCTAssertNil(p?.diagnostic.column)
        XCTAssertEqual(p?.diagnostic.severity, .warning)
    }

    func testParsesNote() {
        let p = DiagnosticsParser.parse(line: "/a/b.m:1:1: note: expanded from macro")
        XCTAssertEqual(p?.diagnostic.severity, .note)
    }

    func testStripsANSIColourCodes() {
        let line = "\u{001B}[1m/proj/File.swift:9:2: \u{001B}[31merror:\u{001B}[0m bad thing"
        let p = DiagnosticsParser.parse(line: line)
        XCTAssertEqual(p?.path, "/proj/File.swift")
        XCTAssertEqual(p?.diagnostic.line, 9)
        XCTAssertEqual(p?.diagnostic.column, 2)
        XCTAssertEqual(p?.diagnostic.severity, .error)
        XCTAssertEqual(p?.diagnostic.message, "bad thing")
    }

    func testIgnoresNonDiagnosticLines() {
        XCTAssertNil(DiagnosticsParser.parse(line: "Compiling Tweak.xm"))
        XCTAssertNil(DiagnosticsParser.parse(line: "In file included from /a/b.h:1:"))
        XCTAssertNil(DiagnosticsParser.parse(line: "make: *** [all] Error 1"))
        XCTAssertNil(DiagnosticsParser.parse(line: ""))
    }
}

final class DiagnosticPathResolverTests: XCTestCase {

    private func project() -> (root: URL, files: [SPPFile]) {
        let root = URL(fileURLWithPath: "/proj")
        let files = [
            SPPFile(name: "Tweak.xm", relativePath: "Sources/Tweak.xm", contentType: .logosXM),
            SPPFile(name: "Helper.m", relativePath: "Sources/util/Helper.m", contentType: .objc),
        ]
        return (root, files)
    }

    func testResolvesAbsolutePath() {
        let (root, files) = project()
        let id = DiagnosticPathResolver.resolveFileID(
            forCompilerPath: "/proj/Sources/Tweak.xm", leaves: files, projectURL: root)
        XCTAssertEqual(id, files[0].id)
    }

    func testResolvesRelativePathSuffix() {
        let (root, files) = project()
        let id = DiagnosticPathResolver.resolveFileID(
            forCompilerPath: "Sources/util/Helper.m", leaves: files, projectURL: root)
        XCTAssertEqual(id, files[1].id)
    }

    func testResolvesUniqueBasenameFallback() {
        let (root, files) = project()
        let id = DiagnosticPathResolver.resolveFileID(
            forCompilerPath: "/somewhere/else/Tweak.xm", leaves: files, projectURL: root)
        XCTAssertEqual(id, files[0].id)
    }

    func testReturnsNilForUnknownFile() {
        let (root, files) = project()
        let id = DiagnosticPathResolver.resolveFileID(
            forCompilerPath: "/proj/Sources/Nope.swift", leaves: files, projectURL: root)
        XCTAssertNil(id)
    }
}
