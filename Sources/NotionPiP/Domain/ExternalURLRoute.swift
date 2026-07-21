import Foundation

public enum ExternalURLSource: String, Equatable, Sendable {
    case chromeExtension = "chrome-extension"
}

public enum ExternalURLRouteError: Error, Equatable, Sendable {
    case inputTooLong
    case unsupportedScheme
    case invalidRouteShape
    case unknownAction(String)
    case missingPageURL
    case missingSource
    case unknownSource(String)
    case invalidPage(NotionPageReferenceError)
}

public enum ExternalURLRoute: Equatable, Sendable {
    case pin(page: NotionPageReference, source: ExternalURLSource)

    private static let maximumURLLength = 4_096

    public static func parse(_ url: URL) -> Result<ExternalURLRoute, ExternalURLRouteError> {
        guard url.absoluteString.utf8.count <= maximumURLLength else {
            return .failure(.inputTooLong)
        }
        guard url.scheme?.lowercased() == "notion-pip" else {
            return .failure(.unsupportedScheme)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              components.path.isEmpty
        else {
            return .failure(.invalidRouteShape)
        }

        let action = url.host?.lowercased() ?? ""
        guard action == "pin" else {
            return .failure(.unknownAction(action))
        }

        guard let queryItems = components.queryItems else {
            return .failure(.missingPageURL)
        }
        let itemsByName = Dictionary(grouping: queryItems, by: \.name)
        guard Set(itemsByName.keys).isSubset(of: ["url", "source"]),
              itemsByName["url", default: []].count <= 1,
              itemsByName["source", default: []].count <= 1
        else {
            return .failure(.invalidRouteShape)
        }
        guard let rawPageURL = singleValue(named: "url", in: queryItems),
              let pageURL = URL(string: rawPageURL)
        else {
            return .failure(.missingPageURL)
        }
        guard let rawSource = singleValue(named: "source", in: queryItems) else {
            return .failure(.missingSource)
        }
        guard let source = ExternalURLSource(rawValue: rawSource) else {
            return .failure(.unknownSource(rawSource))
        }

        do {
            return .success(.pin(page: try NotionPageReference(validating: pageURL), source: source))
        } catch let error as NotionPageReferenceError {
            return .failure(.invalidPage(error))
        } catch {
            return .failure(.missingPageURL)
        }
    }

    private static func singleValue(named name: String, in items: [URLQueryItem]) -> String? {
        let values = items.filter { $0.name == name }.compactMap(\.value)
        return values.count == 1 ? values[0] : nil
    }
}
