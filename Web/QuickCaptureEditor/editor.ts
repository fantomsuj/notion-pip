import {
  QuickCaptureEditorController,
  type QuickCaptureEditorElements,
} from "./quick-capture-editor-controller.ts";

function bootstrap(): void {
  const bridge = window.webkit?.messageHandlers?.captureBridge;
  const editor = document.querySelector<HTMLElement>("#editor");
  const title = document.querySelector<HTMLInputElement>("#title");
  const status = document.querySelector<HTMLElement>("#status");
  const slashMenu = document.querySelector<HTMLElement>("#slash-menu");
  const formatToolbar = document.querySelector<HTMLElement>("#format-toolbar");
  if (bridge === undefined
      || editor === null
      || title === null
      || status === null
      || slashMenu === null
      || formatToolbar === null) return;

  const elements: QuickCaptureEditorElements = {
    editor,
    title,
    status,
    slashMenu,
    formatToolbar,
    page: document.querySelector<HTMLElement>("#page"),
    newNoteButton: document.querySelector<HTMLButtonElement>("#new-note"),
    retryButton: document.querySelector<HTMLButtonElement>("#retry"),
  };
  new QuickCaptureEditorController(bridge, elements).start();
}

if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bootstrap, { once: true });
  } else {
    bootstrap();
  }
}

export {
  executeFormattingCommand,
  formattingState,
  isLinkPaste,
  type FormattingCommand,
  type FormattingCommandTarget,
  type FormattingEditor,
  type FormattingState,
  type FormattingStateEditor,
  type LinkPasteSelection,
} from "./formatting.ts";
export {
  BLOCK_COMMANDS,
  executeBlockCommand,
  filterBlockCommands,
  routeOverlayKey,
  slashQueryAtSelection,
  type BlockCommand,
  type BlockCommandEditor,
  type BlockCommandID,
  type BlockCommandTarget,
  type OverlayKeyInput,
  type OverlayRoute,
  type SlashEditorState,
  type SlashQuery,
  type TiptapBlockCommand,
} from "./block-commands.ts";
export {
  canInstallSnapshot,
  displayTitle,
  normalizeDocument,
  routeTitleKey,
  type TitleKeyInput,
  type TitleRoute,
} from "./editor-state.ts";
export {
  DebouncedChangePublisher,
  requireAutosaveAcknowledgement,
  runAfterPendingChange,
} from "./bridge/debounced-change-publisher.ts";
export { BridgeClient } from "./bridge/bridge-client.ts";
export {
  EditorTransitionGate,
  conflictTransitionOperation,
  type EditorTransitionOperation,
} from "./state/editor-transition-gate.ts";
export { BRIDGE_VERSION } from "./protocol.ts";
