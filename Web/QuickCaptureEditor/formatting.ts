export type FormattingCommand = "bold" | "italic" | "underline" | "strike" | "code" | "link";

export interface FormattingStateEditor {
  isActive(mark: string): boolean;
}

export interface FormattingState {
  readonly bold: boolean;
  readonly italic: boolean;
  readonly underline: boolean;
  readonly strike: boolean;
  readonly code: boolean;
  readonly link: boolean;
}

export function formattingState(editor: FormattingStateEditor): FormattingState {
  return {
    bold: editor.isActive("bold"),
    italic: editor.isActive("italic"),
    underline: editor.isActive("underline"),
    strike: editor.isActive("strike"),
    code: editor.isActive("code"),
    link: editor.isActive("link"),
  };
}

export interface FormattingCommandTarget {
  focus(): FormattingCommandTarget;
  toggleBold(): FormattingCommandTarget;
  toggleItalic(): FormattingCommandTarget;
  toggleUnderline(): FormattingCommandTarget;
  toggleStrike(): FormattingCommandTarget;
  toggleCode(): FormattingCommandTarget;
  toggleLink(attributes?: { href: string }): FormattingCommandTarget;
  run(): boolean;
}

export interface FormattingEditor {
  chain(): FormattingCommandTarget;
}

export function executeFormattingCommand(
  editor: FormattingEditor,
  command: string,
  href?: string,
): boolean {
  if (!["bold", "italic", "underline", "strike", "code", "link"].includes(command)) {
    return false;
  }
  const chain = editor.chain().focus();
  switch (command) {
    case "bold": return chain.toggleBold().run();
    case "italic": return chain.toggleItalic().run();
    case "underline": return chain.toggleUnderline().run();
    case "strike": return chain.toggleStrike().run();
    case "code": return chain.toggleCode().run();
    case "link": return href === undefined
      ? chain.toggleLink().run()
      : chain.toggleLink({ href }).run();
    default: return false;
  }
}

export interface LinkPasteSelection {
  readonly empty: boolean;
}

export function isLinkPaste(selection: LinkPasteSelection, text: string): boolean {
  if (selection.empty) return false;
  const candidate = text.trim();
  if (candidate.length === 0 || /\s/.test(candidate)) return false;
  try {
    const url = new URL(candidate);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}
