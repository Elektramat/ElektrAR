import XCTest

/// Enforces the checkable rules of DESIGN.md on the app's screens: no system colours, no
/// see-through brand buttons, no grey materials. Colours belong in Theme.swift.
final class DesignRulesTests: XCTestCase {
    private static let forbidden: [(rule: String, pattern: String)] = [
        ("System colour (use a Theme token)",
         #"Color\.(purple|pink|yellow|teal|cyan|orange|green|red|mint|indigo|brown)\b"#),
        ("System colour (use a Theme token)",
         #"\.system(Purple|Pink|Yellow|Teal|Cyan|Orange|Green|Red|Mint|Indigo|Brown)\b"#),
        ("System colour (use a Theme token)",
         #"(foregroundStyle|tint|fill|color|background)\(\.(purple|pink|yellow|teal|cyan|orange|green|red|mint|indigo|brown)\b"#),
        ("See-through button (use brandProminentButton)", #"\.buttonStyle\(\.bordered\)"#),
        ("Grey material (use .surface)", #"\b(regular|thin|thick|ultraThin|ultraThick)Material\b"#),
        ("See-through brand colour", #"Theme\.(accent|cta|brandSurface)\.opacity\("#),
    ]

    func testViewsFollowDesignRules() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Kabelmeter")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Theme.swift" }
        XCTAssertFalse(files.isEmpty, "No Swift files found under \(app.path)")

        var violations: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for (rule, pattern) in Self.forbidden where line.range(of: pattern, options: .regularExpression) != nil {
                    violations.append("\(file.lastPathComponent):\(index + 1): \(rule): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, "DESIGN.md rules broken:\n" + violations.joined(separator: "\n"))
    }

    func testRuleCatchesKnownBadLines() {
        let bad = ["Text(\"x\").foregroundStyle(.purple)", "Button(\"Wijzig\") {}.buttonStyle(.bordered)",
                   ".background(.regularMaterial, in: Capsule())", "let c = UIColor.systemPink",
                   "Theme.accent.opacity(0.3)"]
        for line in bad {
            XCTAssertTrue(Self.forbidden.contains { line.range(of: $0.pattern, options: .regularExpression) != nil },
                          "Not caught: \(line)")
        }
        let good = ["Text(\"x\").foregroundStyle(Theme.ink)", ".brandProminentButton(Theme.accent)",
                    ".surface(Capsule())", "Color(Token.secondary)"]
        for line in good {
            XCTAssertFalse(Self.forbidden.contains { line.range(of: $0.pattern, options: .regularExpression) != nil },
                           "False alarm: \(line)")
        }
    }
}
