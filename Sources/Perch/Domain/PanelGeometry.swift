import CoreGraphics
import Foundation

struct PanelGeometry: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let desiredContentSize: PanelContentSize
    let frame: CGRect
    let visibleFrame: CGRect
    let anchor: PanelFrameAnchor
    let displayAffinity: DisplayAffinity?

    init(
        version: Int = Self.currentVersion,
        desiredContentSize: PanelContentSize,
        frame: CGRect,
        visibleFrame: CGRect,
        anchor: PanelFrameAnchor,
        displayAffinity: DisplayAffinity? = nil
    ) throws {
        guard version == Self.currentVersion else {
            throw PanelGeometryError.unsupportedVersion(version)
        }
        guard Self.isValid(frame), Self.isValid(visibleFrame) else {
            throw PanelGeometryError.invalidFrame
        }
        guard anchor.horizontalInset.isFinite, anchor.verticalInset.isFinite else {
            throw PanelGeometryError.invalidAnchor
        }

        self.version = version
        self.desiredContentSize = desiredContentSize
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.anchor = anchor
        self.displayAffinity = displayAffinity
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case desiredContentSize
        case frame
        case visibleFrame
        case anchor
        case displayAffinity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == 1 || decodedVersion == Self.currentVersion else {
            throw PanelGeometryError.unsupportedVersion(decodedVersion)
        }
        try self.init(
            version: Self.currentVersion,
            desiredContentSize: container.decode(
                PanelContentSize.self,
                forKey: .desiredContentSize
            ),
            frame: container.decode(CGRect.self, forKey: .frame),
            visibleFrame: container.decode(CGRect.self, forKey: .visibleFrame),
            anchor: container.decode(PanelFrameAnchor.self, forKey: .anchor),
            displayAffinity: try container.decodeIfPresent(
                DisplayAffinity.self,
                forKey: .displayAffinity
            )
        )
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}

enum PanelGeometryError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidFrame
    case invalidAnchor
}
