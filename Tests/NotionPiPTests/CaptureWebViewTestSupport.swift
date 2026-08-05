import AppKit
import Foundation
import os
import XCTest
import WebKit
@testable import NotionPiP

@MainActor
func focusState(in webView: WKWebView) async throws -> [String: String] {
    let value = try await webView.callAsyncJavaScript(
        """
        const editor = document.querySelector('#editor .tiptap');
        const selection = window.getSelection();
        let textBeforeCaret = '';
        if (selection.rangeCount > 0 && editor.contains(selection.focusNode)) {
          const before = document.createRange();
          before.selectNodeContents(editor);
          before.setEnd(selection.focusNode, selection.focusOffset);
          textBeforeCaret = before.toString();
        }
        return {
          activeID: document.activeElement.id,
          activeIsEditor: String(document.activeElement.matches('#editor .tiptap')),
          body: editor.innerText.trim(),
          textBeforeCaret,
          role: editor.getAttribute('role') || '',
          ariaLabel: editor.getAttribute('aria-label') || '',
          ariaMultiline: editor.getAttribute('aria-multiline') || '',
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: String])
}

@MainActor
func editEditor(title: String, body: String, in webView: WKWebView) async throws -> [String: String] {
    let value = try await webView.callAsyncJavaScript(
        """
        const title = document.querySelector('#title');
        const editor = document.querySelector('#editor .tiptap');
        title.value = newTitle;
        title.dispatchEvent(new Event('input', { bubbles: true }));
        editor.focus();
        const range = document.createRange();
        range.selectNodeContents(editor);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        document.execCommand('insertText', false, newBody);
        return { title: title.value, body: editor.innerText };
        """,
        arguments: ["newTitle": title, "newBody": body],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: String])
}

@MainActor
func editorDOM(in webView: WKWebView) async throws -> [String: String] {
    let value = try await webView.callAsyncJavaScript(
        "return { title: document.querySelector('#title').value, body: document.querySelector('#editor .tiptap').innerText }",
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: String])
}

@MainActor
func attemptUserEditorInput(
    title: String,
    body: String,
    in webView: WKWebView
) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const title = document.querySelector('#title');
        const editor = document.querySelector('#editor .tiptap');
        title.focus();
        title.select();
        document.execCommand('insertText', false, attemptedTitle);
        editor.focus();
        const range = document.createRange();
        range.selectNodeContents(editor);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        document.execCommand('insertText', false, attemptedBody);
        return {
          titleDisabled: title.disabled,
          editorEditable: editor.getAttribute('contenteditable'),
          title: title.value,
          body: editor.innerText,
        };
        """,
        arguments: ["attemptedTitle": title, "attemptedBody": body],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
func editorLockState(in webView: WKWebView) async throws -> [String: Any] {
    let value = try await webView.callAsyncJavaScript(
        """
        const title = document.querySelector('#title');
        const editor = document.querySelector('#editor .tiptap');
        return {
          titleDisabled: title.disabled,
          editorEditable: editor.getAttribute('contenteditable'),
          newNoteDisabled: document.querySelector('#new-note').disabled,
          toolbarDisabled: Array.from(document.querySelectorAll('[data-command]')).every((button) => button.disabled),
        };
        """,
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: Any])
}

@MainActor
func sendWebText(_ text: String, to webView: WKWebView) {
    let letterKeyCodes: [Character: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
        "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    ]
    for character in text {
        let lowercased = Character(String(character).lowercased())
        if let keyCode = letterKeyCodes[lowercased] {
            sendWebKey(
                String(character),
                charactersIgnoringModifiers: String(lowercased),
                modifiers: character.isUppercase ? .shift : [],
                keyCode: keyCode,
                to: webView
            )
            continue
        }
        switch character {
        case " ": sendWebKey(" ", keyCode: 49, to: webView)
        case "/": sendWebKey("/", keyCode: 44, to: webView)
        case "#": sendWebKey("#", charactersIgnoringModifiers: "3", modifiers: .shift, keyCode: 20, to: webView)
        case ">": sendWebKey(">", charactersIgnoringModifiers: ".", modifiers: .shift, keyCode: 47, to: webView)
        case "-": sendWebKey("-", keyCode: 27, to: webView)
        case "[": sendWebKey("[", keyCode: 33, to: webView)
        case "]": sendWebKey("]", keyCode: 30, to: webView)
        default: XCTFail("Unsupported WebKit test character: \(character)")
        }
    }
}

@MainActor
func sendWebKey(
    _ characters: String,
    charactersIgnoringModifiers: String? = nil,
    modifiers: NSEvent.ModifierFlags = [],
    keyCode: UInt16,
    to webView: WKWebView
) {
    let windowNumber = webView.window?.windowNumber ?? 0
    guard let keyDown = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
        isARepeat: false,
        keyCode: keyCode
    ), let keyUp = NSEvent.keyEvent(
        with: .keyUp,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
        isARepeat: false,
        keyCode: keyCode
    ) else {
        XCTFail("Could not create WebKit key event for \(characters)")
        return
    }
    webView.keyDown(with: keyDown)
    webView.keyUp(with: keyUp)
}

@MainActor
func waitForDraft(
    _ repository: CaptureRepository,
    id: String,
    timeout: Duration = .seconds(5),
    condition: (CaptureDraftSnapshot) -> Bool
) async throws -> CaptureDraftSnapshot {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if let draft = try await repository.draft(id: id), condition(draft) {
            return draft
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw CaptureWebViewIntegrationError.timeout
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw CaptureWebViewIntegrationError.timeout
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

final class WebViewCaptureRepositoryFailure: @unchecked Sendable {
    struct ExpectedFailure: Error {}

    private let lock = NSLock()
    private var checkpoint: CaptureRepositoryHelperFetch?

    func failNext(_ checkpoint: CaptureRepositoryHelperFetch) {
        lock.withLock { self.checkpoint = checkpoint }
    }

    func check(_ checkpoint: CaptureRepositoryHelperFetch) throws {
        try lock.withLock {
            if self.checkpoint == checkpoint {
                self.checkpoint = nil
                throw ExpectedFailure()
            }
        }
    }
}

final class WebViewCaptureSaveFailure: Sendable {
    struct ExpectedFailure: Error {}

    private let operation = OSAllocatedUnfairLock<CaptureRepositorySaveOperation?>(
        initialState: nil
    )

    func failNext(_ operation: CaptureRepositorySaveOperation) {
        self.operation.withLock { $0 = operation }
    }

    func check(_ operation: CaptureRepositorySaveOperation) throws {
        try self.operation.withLock {
            if $0 == operation {
                $0 = nil
                throw ExpectedFailure()
            }
        }
    }
}

actor WebViewBridgeRequestRecorder {
    private var requests: [CaptureBridgeRequest] = []

    func append(_ request: CaptureBridgeRequest) {
        requests.append(request)
    }

    func changedRequests() -> [CaptureBridgeRequest] {
        requests.filter {
            if case .changed = $0 { return true }
            return false
        }
    }
}

@MainActor
func waitForJavaScriptCondition(
    in webView: WKWebView,
    timeout: Duration = .seconds(5),
    expression: () -> String
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        let value = try await webView.callAsyncJavaScript(
            expression(),
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool
        if value == true { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw CaptureWebViewIntegrationError.timeout
}

enum CaptureWebViewIntegrationError: Error {
    case timeout
}

func normalizedDOMText(_ value: String?) -> String? {
    value?.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
final class BlockingConflictResolutionGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class BlockingBridgeRequestGate {
    private let matches: (CaptureBridgeRequest) -> Bool
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(matches: @escaping (CaptureBridgeRequest) -> Bool) {
        self.matches = matches
    }

    func suspendIfMatched(_ request: CaptureBridgeRequest) async {
        guard matches(request) else { return }
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
