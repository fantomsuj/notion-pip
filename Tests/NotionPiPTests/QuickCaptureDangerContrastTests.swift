import Foundation
import XCTest

final class QuickCaptureDangerContrastTests: XCTestCase {
    func testDangerTokensUseAdaptiveMediaQueriesInCascadeOrder() throws {
        let css = try composerCSS()
        let declarations = dangerDeclarations(in: css)

        XCTAssertEqual(
            declarations.map(\.value),
            ["#b42318", "#ffb4ab", "#8c0d0d", "#ffd2cc"]
        )
        XCTAssertEqual(
            declarations.map(\.context),
            [
                ":root",
                "@media (prefers-color-scheme: dark)",
                "@media (prefers-contrast: more)",
                "@media (prefers-color-scheme: dark) and (prefers-contrast: more)",
            ]
        )
        XCTAssertEqual(declarations.map(\.selector), [":root", ":root", ":root", ":root"])
        XCTAssertEqual(declarations.map(\.sourceOffset), declarations.map(\.sourceOffset).sorted())
    }

    func testDangerTokensMeetWCAGContrastRequirements() throws {
        let css = try composerCSS()
        let declarations = dangerDeclarations(in: css)
        let values = Dictionary(uniqueKeysWithValues: declarations.map { ($0.context, $0.value) })

        let light = try XCTUnwrap(values[":root"])
        let dark = try XCTUnwrap(values["@media (prefers-color-scheme: dark)"])
        let increasedLight = try XCTUnwrap(values["@media (prefers-contrast: more)"])
        let increasedDark = try XCTUnwrap(
            values["@media (prefers-color-scheme: dark) and (prefers-contrast: more)"]
        )

        let lightRatio = try contrastRatio(foreground: light, background: "#ffffff")
        let darkRatio = try contrastRatio(foreground: dark, background: "#1e1e1e")
        let increasedLightRatio = try contrastRatio(
            foreground: increasedLight,
            background: "#ffffff"
        )
        let increasedDarkRatio = try contrastRatio(
            foreground: increasedDark,
            background: "#1e1e1e"
        )

        for ratio in [lightRatio, darkRatio, increasedLightRatio, increasedDarkRatio] {
            XCTAssertGreaterThanOrEqual(ratio, 4.5)
        }
        XCTAssertGreaterThanOrEqual(increasedLightRatio, lightRatio)
        XCTAssertGreaterThanOrEqual(increasedDarkRatio, darkRatio)
    }

    func testErrorStatusUsesDangerToken() throws {
        let css = try composerCSS()

        XCTAssertTrue(
            css.range(
                of: #"#status\s*\[\s*data-state\s*=\s*"error"\s*\]\s*\{[^}]*color\s*:\s*var\(\s*--danger\s*\)\s*;?[^}]*\}"#,
                options: .regularExpression
            ) != nil
        )
    }

    private func composerCSS() throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cssURL = repositoryRoot
            .appendingPathComponent("Sources/NotionPiP/Resources/QuickCapture/composer.css")
        return try String(contentsOf: cssURL, encoding: .utf8)
    }

    private func dangerDeclarations(in css: String) -> [DangerDeclaration] {
        let pattern = #"--danger\s*:\s*(#[0-9a-fA-F]{6})\s*;"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(css.startIndex..., in: css)

        return expression.matches(in: css, range: fullRange).compactMap { match in
            guard
                let declarationRange = Range(match.range, in: css),
                let valueRange = Range(match.range(at: 1), in: css)
            else {
                return nil
            }

            let scopes = scopeHeaders(
                in: css,
                before: declarationRange.lowerBound
            )
            let context = scopes.dropLast().last ?? scopes.last ?? ""

            return DangerDeclaration(
                context: context,
                selector: scopes.last ?? "",
                value: String(css[valueRange]).lowercased(),
                sourceOffset: match.range.location
            )
        }
    }

    private func scopeHeaders(
        in css: String,
        before endIndex: String.Index
    ) -> [String] {
        var scopes: [String] = []
        var headerStart = css.startIndex
        var index = css.startIndex

        while index < endIndex {
            let character = css[index]
            let nextIndex = css.index(after: index)
            switch character {
            case "{":
                scopes.append(
                    css[headerStart..<index]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                headerStart = nextIndex
            case "}":
                if !scopes.isEmpty {
                    scopes.removeLast()
                }
                headerStart = nextIndex
            case ";":
                headerStart = nextIndex
            default:
                break
            }
            index = nextIndex
        }

        return scopes
    }

    private func contrastRatio(foreground: String, background: String) throws -> Double {
        let foregroundLuminance = try relativeLuminance(hex: foreground)
        let backgroundLuminance = try relativeLuminance(hex: background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(hex: String) throws -> Double {
        let value = hex.dropFirst()
        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            throw ContrastError.invalidHex(hex)
        }

        let red = linearized(Double((rgb >> 16) & 0xff) / 255.0)
        let green = linearized(Double((rgb >> 8) & 0xff) / 255.0)
        let blue = linearized(Double(rgb & 0xff) / 255.0)

        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

private struct DangerDeclaration {
    let context: String
    let selector: String
    let value: String
    let sourceOffset: Int
}

private enum ContrastError: Error {
    case invalidHex(String)
}
