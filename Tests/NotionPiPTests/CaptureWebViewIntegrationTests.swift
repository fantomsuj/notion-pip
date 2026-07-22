import AppKit
import Foundation
import WebKit
import XCTest
@testable import NotionPiP

@MainActor
final class CaptureWebViewIntegrationTests: XCTestCase {
    func testEmptyAuthoritativeDraftFocusesTitleAndExposesAccessibleBody() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "empty-focus-draft" }
        )

        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }
        let state = try await focusState(in: session.webView)

        XCTAssertEqual(state["activeID"], "title")
        XCTAssertEqual(state["role"], "textbox")
        XCTAssertEqual(state["ariaLabel"], "Note content")
        XCTAssertEqual(state["ariaMultiline"], "true")
    }

    func testPopulatedAuthoritativeDraftFocusesBodyAtItsEnd() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "populated-focus-draft",
                title: "Existing note",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Continue here"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)

        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }
        let state = try await focusState(in: session.webView)

        XCTAssertEqual(state["activeIsEditor"], "true")
        XCTAssertEqual(state["body"], "Continue here")
        XCTAssertEqual(state["textBeforeCaret"], "Continue here")
    }

    func testNewerSnapshotForSameDraftPreservesCurrentFocus() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "same-draft-focus",
                title: "Existing note",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Existing body"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let result = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            title.focus();
            window.NotionPiPBridge.applyNativeReply({
              version: 1,
              id: 'same-draft-refresh',
              ok: true,
              result: {
                kind: 'restored',
                revision: 2,
                snapshot: {
                  draftID: 'same-draft-focus',
                  title: 'Refreshed note',
                  document: {
                    type: 'doc',
                    content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Refreshed body' }] }],
                  },
                  revision: 2,
                },
              },
            });
            return { activeID: document.activeElement.id, title: title.value };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]

        XCTAssertEqual(result?["activeID"], "title")
        XCTAssertEqual(result?["title"], "Refreshed note")
    }

    func testTitleNavigationKeysMoveFocusIntoBody() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "title-key-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        for key in ["Enter", "Tab", "ArrowDown"] {
            let activeIsEditor = try await session.webView.callAsyncJavaScript(
                """
                const title = document.querySelector('#title');
                title.focus();
                title.setSelectionRange(title.value.length, title.value.length);
                title.dispatchEvent(new KeyboardEvent('keydown', { key: pressedKey, bubbles: true }));
                return document.activeElement.matches('#editor .tiptap');
                """,
                arguments: ["pressedKey": key],
                in: nil,
                contentWorld: .page
            ) as? Bool
            XCTAssertEqual(activeIsEditor, true, "Expected \(key) to focus the body")
        }
    }

    func testShiftTabInTitlePreservesReverseFocusTraversal() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "reverse-title-key-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let result = try await session.webView.callAsyncJavaScript(
            """
            const title = document.querySelector('#title');
            title.focus();
            const allowed = title.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Tab',
              shiftKey: true,
              bubbles: true,
              cancelable: true,
            }));
            return {
              activeIsTitle: document.activeElement === title,
              defaultPrevented: !allowed,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Bool]

        XCTAssertEqual(result?["activeIsTitle"], true)
        XCTAssertEqual(result?["defaultPrevented"], false)
    }

    func testArrowUpAtStartOfBodyReturnsFocusToTitle() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "body-key-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let activeID = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            const selection = window.getSelection();
            const range = document.createRange();
            range.setStart(editor.firstChild, 0);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            editor.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
            return document.activeElement.id;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(activeID, "title")
    }

    func testArrowUpAtStartOfNestedFirstBlockReturnsFocusToTitle() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "nested-body-key-draft",
                title: "Nested first block",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"blockquote","content":[{"type":"paragraph","content":[{"type":"text","text":"Nested body"}]}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let activeID = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('blockquote p').firstChild;
            editor.focus();
            const selection = window.getSelection();
            const range = document.createRange();
            range.setStart(text, 0);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            editor.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
            return document.activeElement.id;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(activeID, "title")
    }

    func testSlashMenuFiltersHeadingsAndKeyboardSelectionProducesHeadingTwo() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "slash-heading-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("/hea", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#slash-menu').hidden && document.querySelectorAll('#slash-menu [role=option]').length === 3"
        }
        let opened = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const menu = document.querySelector('#slash-menu');
            const options = Array.from(menu.querySelectorAll('[role="option"]'));
            return {
              labels: options.map((option) => option.textContent.trim()).join('|'),
              active: editor.getAttribute('aria-activedescendant') || '',
              menuActive: menu.getAttribute('aria-activedescendant') || '',
              role: menu.getAttribute('role') || '',
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]
        sendWebKey("\u{F701}", keyCode: 125, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#editor .tiptap').getAttribute('aria-activedescendant') === 'slash-option-heading2'"
        }
        sendWebKey("\r", keyCode: 36, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return Boolean(document.querySelector('#editor .tiptap h2')) && document.querySelector('#slash-menu').hidden"
        }
        let selected = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            return {
              headingTwo: Boolean(editor.querySelector('h2')),
              body: editor.innerText,
              closed: document.querySelector('#slash-menu').hidden,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(opened?["labels"] as? String, "Heading 1|Heading 2|Heading 3")
        XCTAssertEqual(opened?["active"] as? String, "slash-option-heading1")
        XCTAssertEqual(opened?["menuActive"] as? String, "slash-option-heading1")
        XCTAssertEqual(opened?["role"] as? String, "listbox")
        XCTAssertEqual(selected?["headingTwo"] as? Bool, true)
        XCTAssertEqual(normalizedDOMText(selected?["body"] as? String), "")
        XCTAssertEqual(selected?["closed"] as? Bool, true)
    }

    func testSlashMenuKeepsFinalKeyboardOptionVisible() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "slash-scroll-draft" }
        )
        session.webView.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            document.querySelector('#editor .tiptap').focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("/", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelectorAll('#slash-menu [role=option]').length === 10"
        }

        for commandID in [
            "heading1", "heading2", "heading3", "bulletList", "orderedList",
            "taskList", "quote", "codeBlock", "divider",
        ] {
            sendWebKey("\u{F701}", keyCode: 125, to: session.webView)
            try await waitForJavaScriptCondition(in: session.webView) {
                "return document.querySelector('#slash-menu').getAttribute('aria-activedescendant') === 'slash-option-\(commandID)'"
            }
        }

        let visibility = try await session.webView.callAsyncJavaScript(
            """
            const menu = document.querySelector('#slash-menu');
            const active = document.getElementById(menu.getAttribute('aria-activedescendant'));
            const menuBounds = menu.getBoundingClientRect();
            const activeBounds = active.getBoundingClientRect();
            return {
              activeID: active.id,
              visible: activeBounds.top >= menuBounds.top && activeBounds.bottom <= menuBounds.bottom,
              scrollTop: menu.scrollTop,
              activeTop: activeBounds.top,
              activeBottom: activeBounds.bottom,
              menuTop: menuBounds.top,
              menuBottom: menuBounds.bottom,
              clientHeight: menu.clientHeight,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(visibility?["activeID"] as? String, "slash-option-divider")
        XCTAssertEqual(visibility?["visible"] as? Bool, true, "\(String(describing: visibility))")
        XCTAssertGreaterThan(visibility?["scrollTop"] as? Double ?? 0, 0)
    }

    func testSlashMenuEscapeDismissesWithoutDeletingQueryText() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "slash-escape-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("/hea", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#slash-menu').hidden && document.querySelector('#editor .tiptap').innerText.trim() === '/hea'"
        }
        sendWebKey("\u{1b}", keyCode: 53, to: session.webView)
        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const menu = document.querySelector('#slash-menu');
            return {
              closed: menu.hidden,
              body: editor.innerText,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(result?["closed"] as? Bool, true)
        XCTAssertEqual(normalizedDOMText(result?["body"] as? String), "/hea")
    }

    func testContextualFormattingToolbarShowsActiveStateAboveSelectionAndKeepsEditorFocus() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "format-toolbar-draft",
                title: "Formatting",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","marks":[{"type":"bold"}],"text":"Selected text"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('strong').firstChild;
            editor.focus();
            const range = document.createRange();
            range.setStart(text, 0);
            range.setEnd(text, 8);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event('selectionchange'));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#format-toolbar').hidden && document.querySelector('[data-format=bold]').getAttribute('aria-pressed') === 'true'"
        }
        let result = try await session.webView.callAsyncJavaScript(
            """
            const toolbar = document.querySelector('#format-toolbar');
            const italic = toolbar.querySelector('[data-format=italic]');
            const selectedBounds = window.getSelection().getRangeAt(0).getBoundingClientRect();
            const toolbarBounds = toolbar.getBoundingClientRect();
            italic.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
            italic.click();
            return {
              boldPressed: toolbar.querySelector('[data-format=bold]').getAttribute('aria-pressed'),
              italicPressed: italic.getAttribute('aria-pressed'),
              aboveSelection: toolbarBounds.bottom <= selectedBounds.top,
              activeIsEditor: document.activeElement.matches('#editor .tiptap'),
              italicApplied: Boolean(document.querySelector('#editor .tiptap em')),
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(result?["boldPressed"] as? String, "true")
        XCTAssertEqual(result?["italicPressed"] as? String, "true")
        XCTAssertEqual(result?["aboveSelection"] as? Bool, true)
        XCTAssertEqual(result?["activeIsEditor"] as? Bool, true)
        XCTAssertEqual(result?["italicApplied"] as? Bool, true)
    }

    func testContextualFormattingToolbarDismissesOnEscape() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "format-escape-draft",
                title: "Formatting",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Selected text"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('p').firstChild;
            editor.focus();
            const range = document.createRange();
            range.setStart(text, 0);
            range.setEnd(text, 8);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event('selectionchange'));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#format-toolbar').hidden"
        }
        sendWebKey("\u{1b}", keyCode: 53, to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#format-toolbar').hidden"
        }
        let selectedText = try await session.webView.callAsyncJavaScript(
            "return window.getSelection().toString()",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String

        XCTAssertEqual(selectedText, "Selected")
    }

    func testPastingHTTPSURLOverSelectionLinksWithoutReplacingText() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "format-link-paste-draft",
                title: "Formatting",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Selected text"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(repository: repository)
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            const text = editor.querySelector('p').firstChild;
            editor.focus();
            const range = document.createRange();
            range.setStart(text, 0);
            range.setEnd(text, 8);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.dispatchEvent(new Event('selectionchange'));
            await new Promise((resolve) => setTimeout(resolve, 20));
            const clipboard = new DataTransfer();
            clipboard.setData('text/plain', 'https://example.com/reference');
            editor.dispatchEvent(new ClipboardEvent('paste', {
              bubbles: true,
              cancelable: true,
              clipboardData: clipboard,
            }));
            await new Promise((resolve) => setTimeout(resolve, 20));
            const link = editor.querySelector('a');
            return {
              body: editor.innerText,
              href: link?.getAttribute('href') || '',
              linkedText: link?.textContent || '',
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]

        XCTAssertEqual(normalizedDOMText(result?["body"]), "Selected text")
        XCTAssertEqual(result?["href"], "https://example.com/reference")
        XCTAssertEqual(result?["linkedText"], "Selected")
    }

    func testMarkdownMarkersCreateHeadingQuoteAndListNodes() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "markdown-markers-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("# Heading", to: session.webView)
        sendWebKey("\r", keyCode: 36, to: session.webView)
        sendWebText("> Quoted", to: session.webView)
        sendWebKey("\r", keyCode: 36, to: session.webView)
        sendWebKey("\r", keyCode: 36, to: session.webView)
        sendWebText("- Listed", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return Boolean(document.querySelector('#editor .tiptap h1') && document.querySelector('#editor .tiptap blockquote') && document.querySelector('#editor .tiptap ul:not([data-type=taskList])'))"
        }
        let result = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            return {
              heading: editor.querySelector('h1')?.textContent || '',
              quote: editor.querySelector('blockquote')?.textContent || '',
              list: editor.querySelector('ul:not([data-type="taskList"])')?.textContent || '',
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]

        XCTAssertEqual(result?["heading"], "Heading")
        XCTAssertEqual(result?["quote"], "Quoted")
        XCTAssertEqual(result?["list"], "Listed")
    }

    func testTaskItemCreatedFromMarkerAutosavesThroughBridge() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "task-item-draft" }
        )
        try await waitUntil { session.status == .ready }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return !document.querySelector('#title').disabled"
        }

        _ = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            editor.focus();
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        sendWebText("[ ] Ship capture", to: session.webView)
        try await waitForJavaScriptCondition(in: session.webView) {
            "return Boolean(document.querySelector('#editor .tiptap ul[data-type=taskList] li[data-checked]')) && document.querySelector('#editor .tiptap').innerText.includes('Ship capture')"
        }
        let taskDOM = try await session.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('#editor .tiptap');
            return {
              taskList: Boolean(editor.querySelector('ul[data-type="taskList"]')),
              taskItem: Boolean(editor.querySelector('ul[data-type="taskList"] li[data-checked]')),
              checked: editor.querySelector('input[type="checkbox"]')?.checked ?? true,
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]

        XCTAssertEqual(taskDOM?["taskList"] as? Bool, true)
        XCTAssertEqual(taskDOM?["taskItem"] as? Bool, true)
        XCTAssertEqual(taskDOM?["checked"] as? Bool, false)
        let saved = try await waitForDraft(repository, id: "task-item-draft") {
            let document = String(decoding: $0.editorDocument, as: UTF8.self)
            return document.contains("taskList")
                && document.contains("taskItem")
                && document.contains("Ship capture")
        }
        XCTAssertGreaterThan(saved.revision, 1)
    }

    func testEditorRemainsLockedUntilDelayedReadyInstallsAuthoritativeDraft() async throws {
        let gate = BlockingBridgeRequestGate { request in
            if case .ready = request { return true }
            return false
        }
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "ready-locked-draft" },
            beforeBridgeRequest: { request in await gate.suspendIfMatched(request) }
        )
        try await waitUntil { gate.entered }

        let attempted = try await attemptUserEditorInput(
            title: "Must not be accepted before ready",
            body: "early body",
            in: session.webView
        )

        XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
        XCTAssertEqual(attempted["editorEditable"] as? String, "false")
        XCTAssertEqual(attempted["title"] as? String, "")
        XCTAssertEqual(normalizedDOMText(attempted["body"] as? String), "")
        let controls = try await editorLockState(in: session.webView)
        XCTAssertEqual(controls["newNoteDisabled"] as? Bool, true)
        XCTAssertEqual(controls["toolbarDisabled"] as? Bool, true)
        gate.resume()
        try await waitUntil { session.status == .ready }
        let unlocked = try await editorLockState(in: session.webView)
        XCTAssertEqual(unlocked["titleDisabled"] as? Bool, false)
        XCTAssertEqual(unlocked["editorEditable"] as? String, "true")
    }

    func testStashLocksEveryMutationControlUntilNewDraftSnapshotIsApplied() async throws {
        let gate = BlockingBridgeRequestGate { request in
            if case .stash = request { return true }
            return false
        }
        var identifiers = ["stash-locked-draft", "stash-next-draft"].makeIterator()
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! },
            beforeBridgeRequest: { request in await gate.suspendIfMatched(request) }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Captured before stash",
            body: "captured stash body",
            in: session.webView
        )
        _ = try await waitForDraft(repository, id: "stash-locked-draft") {
            $0.title == "Captured before stash"
        }

        _ = try await session.webView.callAsyncJavaScript(
            "document.querySelector('#new-note').click(); return true",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { gate.entered }
        let attempted = try await attemptUserEditorInput(
            title: "Must not replace stashed capture",
            body: "must not replace stash body",
            in: session.webView
        )

        XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
        XCTAssertEqual(attempted["editorEditable"] as? String, "false")
        let controls = try await editorLockState(in: session.webView)
        XCTAssertEqual(controls["newNoteDisabled"] as? Bool, true)
        XCTAssertEqual(controls["toolbarDisabled"] as? Bool, true)
        gate.resume()
        _ = try await waitForDraft(repository, id: "stash-locked-draft") {
            $0.disposition == .stashed
        }
        try await waitForJavaScriptCondition(in: session.webView) {
            "return document.querySelector('#title').value === '' && !document.querySelector('#title').disabled"
        }
        let stashedValue = try await repository.draft(id: "stash-locked-draft")
        let stashed = try XCTUnwrap(stashedValue)
        XCTAssertEqual(stashed.title, "Captured before stash")
        XCTAssertTrue(String(decoding: stashed.editorDocument, as: UTF8.self).contains("captured stash body"))
    }

    func testRestoreDrainsQueuedOldDraftEditBeforeSwitchingSnapshots() async throws {
        let repository = try CaptureRepository(inMemory: true)
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "restore-target",
                title: "Stashed target",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"target body"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .stashed
            ),
            expectedRevision: 0
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "old-active-draft" }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Queued old draft edit",
            body: "queued old draft body",
            in: session.webView
        )

        let restoredValue = try await session.webView.callAsyncJavaScript(
            "return await window.NotionPiPBridge.restore(draftID, expectedRevision)",
            arguments: ["draftID": "restore-target", "expectedRevision": 1],
            in: nil,
            contentWorld: .page
        )
        let restoredReply = try XCTUnwrap(restoredValue as? [String: Any])

        XCTAssertEqual(restoredReply["ok"] as? Bool, true, "\(restoredReply)")
        let oldDraftValue = try await repository.draft(id: "old-active-draft")
        let oldDraft = try XCTUnwrap(oldDraftValue)
        XCTAssertEqual(oldDraft.title, "Queued old draft edit")
        XCTAssertTrue(String(decoding: oldDraft.editorDocument, as: UTF8.self).contains("queued old draft body"))
        XCTAssertEqual(oldDraft.disposition, .stashed)
        let targetValue = try await repository.draft(id: "restore-target")
        let target = try XCTUnwrap(targetValue)
        XCTAssertEqual(target.disposition, .active)
        let installed = try await editorDOM(in: session.webView)
        XCTAssertEqual(installed["title"], "Stashed target")
        XCTAssertEqual(normalizedDOMText(installed["body"]), "target body")
    }

    func testOlderSameDraftSnapshotCannotReplaceNewerLiveDOM() async throws {
        let repository = try CaptureRepository(inMemory: true)
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { "monotonic-draft" }
        )
        try await waitUntil { session.status == .ready }
        _ = try await editEditor(
            title: "Newer live title",
            body: "newer live body",
            in: session.webView
        )
        _ = try await waitForDraft(repository, id: "monotonic-draft") {
            $0.revision == 2 && $0.title == "Newer live title"
        }

        let applied = try await session.webView.callAsyncJavaScript(
            """
            return window.NotionPiPBridge.applyNativeReply({
              version: 1,
              id: 'older-snapshot',
              ok: true,
              result: {
                kind: 'restored',
                revision: 1,
                snapshot: {
                  draftID: 'monotonic-draft',
                  title: 'Older title',
                  document: {
                    type: 'doc',
                    content: [{ type: 'paragraph', content: [{ type: 'text', text: 'older body' }] }],
                  },
                  revision: 1,
                },
              },
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool
        let installed = try await editorDOM(in: session.webView)

        XCTAssertEqual(applied, true)
        XCTAssertEqual(installed["title"], "Newer live title")
        XCTAssertEqual(normalizedDOMText(installed["body"]), "newer live body")
    }

    func testBundledEditorRunsRealReplyBridgeAndRestoresStashedContentAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("WebKitCapture.store")
        var stashedRevision: Int?

        weak var releasedSession: CaptureEditorSession?
        do {
            var identifiers = ["web-draft", "next-draft"].makeIterator()
            let repository = try CaptureRepository(storeURL: storeURL)
            var session: CaptureEditorSession? = CaptureEditorSession(
                repository: repository,
                draftID: { identifiers.next()! }
            )
            releasedSession = session
            let liveSession = try XCTUnwrap(session)
            try await waitUntil { liveSession.status == .ready }
            let bootstrapped = try await liveSession.webView.callAsyncJavaScript(
                "return Boolean(window.NotionPiPBridge && document.querySelector('#editor .tiptap'))",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? Bool
            XCTAssertEqual(bootstrapped, true)

            let edited = try await liveSession.webView.callAsyncJavaScript(
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
                arguments: ["newTitle": "Real WebKit", "newBody": "real webkit body"],
                in: nil,
                contentWorld: .page
            ) as? [String: String]
            XCTAssertEqual(edited?["title"], "Real WebKit")
            XCTAssertEqual(normalizedDOMText(edited?["body"]), "real webkit body")

            let saved = try await waitForDraft(repository, id: "web-draft") {
                $0.revision == 2 && $0.title == "Real WebKit"
            }
            XCTAssertTrue(String(decoding: saved.editorDocument, as: UTF8.self).contains("real webkit body"))

            _ = try await liveSession.webView.callAsyncJavaScript(
                "document.querySelector('#new-note').click(); return true",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            let stored = try await waitForDraft(repository, id: "web-draft") {
                $0.disposition == .stashed
            }
            XCTAssertEqual(stored.disposition, .stashed)
            XCTAssertEqual(stored.title, "Real WebKit")
            stashedRevision = stored.revision

            session?.tearDownBridge()
            session = nil
        }
        XCTAssertNil(releasedSession)

        let reopened = try CaptureRepository(storeURL: storeURL)
        let relaunched = CaptureEditorSession(repository: reopened, draftID: { "unused" })
        try await waitUntil { relaunched.status == .ready }
        let expectedRevision = try XCTUnwrap(stashedRevision)
        let restoreValue = try await relaunched.webView.callAsyncJavaScript(
            "return await window.NotionPiPBridge.restore(draftID, expectedRevision)",
            arguments: ["draftID": "web-draft", "expectedRevision": expectedRevision],
            in: nil,
            contentWorld: .page
        )
        let restoreReply = try XCTUnwrap(restoreValue as? [String: Any])
        XCTAssertEqual(restoreReply["ok"] as? Bool, true, "\(restoreReply)")
        let result = try XCTUnwrap(restoreReply["result"] as? [String: Any])
        let restored = try XCTUnwrap(result["snapshot"] as? [String: Any])

        XCTAssertEqual(restored["title"] as? String, "Real WebKit")
        XCTAssertEqual(restored["revision"] as? Int, expectedRevision + 1)
        let document = try XCTUnwrap(restored["document"] as? [String: Any])
        let content = try XCTUnwrap(document["content"] as? [[String: Any]])
        let paragraph = try XCTUnwrap(content.first)
        let textNodes = try XCTUnwrap(paragraph["content"] as? [[String: Any]])
        XCTAssertEqual(textNodes.first?["text"] as? String, "real webkit body")
        let restoredDOM = try await relaunched.webView.callAsyncJavaScript(
            "return { title: document.querySelector('#title').value, body: document.querySelector('#editor .tiptap').innerText }",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: String]
        XCTAssertEqual(restoredDOM?["title"], "Real WebKit")
        XCTAssertEqual(normalizedDOMText(restoredDOM?["body"]), "real webkit body")
    }

    func testNativeSaveAsNewCapturesNewestUnsentTiptapDocument() async throws {
        var identifiers = ["conflict-draft", "conflict-copy"].makeIterator()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(Date(timeIntervalSince1970: 1_700_000_000))
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! }
        )
        try await waitUntil { session.status == .ready }
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "conflict-draft",
                title: "Native latest",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"native"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )

        let staleDOM = try await editEditor(
            title: "Cached conflict work",
            body: "cached conflict body",
            in: session.webView
        )
        XCTAssertEqual(normalizedDOMText(staleDOM["body"]), "cached conflict body")
        try await waitUntil { session.conflict != nil }

        let newestDOM = try await editEditor(
            title: "Newest unsent JS work",
            body: "newest unsent JS body",
            in: session.webView
        )
        XCTAssertEqual(normalizedDOMText(newestDOM["body"]), "newest unsent JS body")

        await session.resolve(.saveAsNew)

        XCTAssertNil(session.conflict)
        let copyValue = try await repository.draft(id: "conflict-copy")
        let copy = try XCTUnwrap(copyValue)
        XCTAssertEqual(copy.title, "Newest unsent JS work")
        XCTAssertTrue(String(decoding: copy.editorDocument, as: UTF8.self).contains("newest unsent JS body"))
        let installed = try await editorDOM(in: session.webView)
        XCTAssertEqual(installed["title"], "Newest unsent JS work")
        XCTAssertEqual(normalizedDOMText(installed["body"]), "newest unsent JS body")

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(session.conflict)
        let draftsAfterDebounce = try await repository.drafts()
        XCTAssertEqual(draftsAfterDebounce.count, 2)
        XCTAssertEqual(draftsAfterDebounce.filter { $0.id == "conflict-copy" }.count, 1)
    }

    func testConflictRecoveryLocksRealEditorWhileNativeReplyIsInFlight() async throws {
        var identifiers = ["locked-draft", "locked-copy"].makeIterator()
        let gate = BlockingConflictResolutionGate()
        let repository = try CaptureRepository(
            inMemory: true,
            clock: TestCaptureClock(Date(timeIntervalSince1970: 1_700_000_000))
        )
        let session = CaptureEditorSession(
            repository: repository,
            draftID: { identifiers.next()! },
            beforeConflictResolution: { _ in await gate.suspend() }
        )
        try await waitUntil { session.status == .ready }
        _ = try await repository.saveDraft(
            DraftMutation(
                id: "locked-draft",
                title: "Native latest",
                editorDocument: Data(#"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"native"}]}]}"#.utf8),
                sourceDocument: nil,
                disposition: .active
            ),
            expectedRevision: 1
        )
        _ = try await editEditor(
            title: "Initial conflict",
            body: "initial conflict body",
            in: session.webView
        )
        try await waitUntil { session.conflict != nil }
        _ = try await editEditor(
            title: "Final captured work",
            body: "final captured body",
            in: session.webView
        )

        let resolution = Task { await session.resolve(.saveAsNew) }
        try await waitUntil { gate.entered }
        let attempted = try await attemptUserEditorInput(
            title: "Must not replace capture",
            body: "must not replace body",
            in: session.webView
        )

        XCTAssertEqual(attempted["titleDisabled"] as? Bool, true)
        XCTAssertEqual(attempted["editorEditable"] as? String, "false")
        XCTAssertEqual(attempted["title"] as? String, "Final captured work")
        XCTAssertEqual(
            normalizedDOMText(attempted["body"] as? String),
            "final captured body"
        )

        gate.resume()
        await resolution.value

        let copyValue = try await repository.draft(id: "locked-copy")
        let copy = try XCTUnwrap(copyValue)
        XCTAssertEqual(copy.title, "Final captured work")
        XCTAssertTrue(String(decoding: copy.editorDocument, as: UTF8.self).contains("final captured body"))
        let unlocked = try await editorLockState(in: session.webView)
        XCTAssertEqual(unlocked["titleDisabled"] as? Bool, false)
        XCTAssertEqual(unlocked["editorEditable"] as? String, "true")
    }

}

@MainActor
private func focusState(in webView: WKWebView) async throws -> [String: String] {
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
private func editEditor(title: String, body: String, in webView: WKWebView) async throws -> [String: String] {
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
private func editorDOM(in webView: WKWebView) async throws -> [String: String] {
    let value = try await webView.callAsyncJavaScript(
        "return { title: document.querySelector('#title').value, body: document.querySelector('#editor .tiptap').innerText }",
        arguments: [:],
        in: nil,
        contentWorld: .page
    )
    return try XCTUnwrap(value as? [String: String])
}

@MainActor
private func attemptUserEditorInput(
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
private func editorLockState(in webView: WKWebView) async throws -> [String: Any] {
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
private func sendWebText(_ text: String, to webView: WKWebView) {
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
private func sendWebKey(
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
private func waitForDraft(
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
private func waitUntil(
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

@MainActor
private func waitForJavaScriptCondition(
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

private enum CaptureWebViewIntegrationError: Error {
    case timeout
}

private func normalizedDOMText(_ value: String?) -> String? {
    value?.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
private final class BlockingConflictResolutionGate {
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
private final class BlockingBridgeRequestGate {
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
