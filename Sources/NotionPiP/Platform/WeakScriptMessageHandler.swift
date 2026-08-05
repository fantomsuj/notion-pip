import WebKit

@MainActor
protocol CaptureScriptMessageHandling: AnyObject {
    func handleScriptMessage(_ request: CaptureBridgeRequest) async -> CaptureBridgeReply
}

@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var delegate: (any CaptureScriptMessageHandling)?
    private let allowedDocumentURL: URL

    init(allowedDocumentURL: URL) {
        self.allowedDocumentURL = allowedDocumentURL
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let id = Self.requestID(from: message.body) ?? "invalid-request"
        do {
            guard JSONSerialization.isValidJSONObject(message.body) else {
                throw CaptureBridgeProtocolError.malformedMessage
            }
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let context = BridgeMessageContext(
                isMainFrame: message.frameInfo.isMainFrame,
                originScheme: message.frameInfo.securityOrigin.protocol,
                originHost: message.frameInfo.securityOrigin.host,
                sourceURL: message.frameInfo.request.url,
                allowedDocumentURL: allowedDocumentURL
            )
            let request = try await Task.detached(priority: .userInitiated) {
                try CaptureBridgeProtocol.decode(data, context: context)
            }.value
            guard let delegate else {
                return (nil, "Capture bridge is unavailable")
            }
            let reply = await delegate.handleScriptMessage(request)
            return (try CaptureBridgeProtocol.replyObject(reply), nil)
        } catch {
            let reply = CaptureBridgeReply.failure(
                id: id,
                code: .invalidMessage,
                message: "The editor sent an invalid request.",
                recoverable: false
            )
            do {
                return (try CaptureBridgeProtocol.replyObject(reply), nil)
            } catch {
                return (nil, "Capture bridge rejected the request")
            }
        }
    }

    private static func requestID(from value: Any) -> String? {
        guard let dictionary = value as? [String: Any],
              let id = dictionary["id"] as? String,
              !id.isEmpty,
              id.utf8.count <= 128
        else {
            return nil
        }
        return id
    }
}
