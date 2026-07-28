export type BlockCommandID =
  | "text"
  | "heading1"
  | "heading2"
  | "heading3"
  | "bulletList"
  | "orderedList"
  | "taskList"
  | "quote"
  | "codeBlock"
  | "divider";

export type TiptapBlockCommand =
  | "setParagraph"
  | "toggleHeading"
  | "toggleBulletList"
  | "toggleOrderedList"
  | "toggleTaskList"
  | "toggleBlockquote"
  | "toggleCodeBlock"
  | "setHorizontalRule";

export interface BlockCommand {
  readonly id: BlockCommandID;
  readonly label: string;
  readonly aliases: readonly string[];
  readonly command: TiptapBlockCommand;
}

export const BLOCK_COMMANDS: readonly BlockCommand[] = [
  { id: "text", label: "Text", aliases: ["paragraph", "plain text"], command: "setParagraph" },
  { id: "heading1", label: "Heading 1", aliases: ["h1", "title"], command: "toggleHeading" },
  { id: "heading2", label: "Heading 2", aliases: ["h2", "subtitle"], command: "toggleHeading" },
  { id: "heading3", label: "Heading 3", aliases: ["h3", "subheading"], command: "toggleHeading" },
  {
    id: "bulletList",
    label: "Bulleted list",
    aliases: ["bullet", "unordered", "ul"],
    command: "toggleBulletList",
  },
  {
    id: "orderedList",
    label: "Numbered list",
    aliases: ["numbered", "ordered", "ol"],
    command: "toggleOrderedList",
  },
  {
    id: "taskList",
    label: "To-do list",
    aliases: ["todo", "task", "checklist"],
    command: "toggleTaskList",
  },
  { id: "quote", label: "Quote", aliases: ["blockquote", "citation"], command: "toggleBlockquote" },
  { id: "codeBlock", label: "Code block", aliases: ["code", "preformatted"], command: "toggleCodeBlock" },
  {
    id: "divider",
    label: "Divider",
    aliases: ["horizontal rule", "separator", "hr"],
    command: "setHorizontalRule",
  },
];

export function filterBlockCommands(query: string): readonly BlockCommand[] {
  const normalizedQuery = query.trim().toLocaleLowerCase();
  if (normalizedQuery.length === 0) return BLOCK_COMMANDS;
  return BLOCK_COMMANDS.filter((item) =>
    [item.label, ...item.aliases]
      .some((term) => term.toLocaleLowerCase().includes(normalizedQuery)),
  );
}

export interface SlashEditorState {
  readonly selection: {
    readonly empty: boolean;
    readonly from: number;
    readonly $from: {
      readonly parentOffset: number;
      readonly parent: {
        readonly isTextblock: boolean;
        textBetween(from: number, to: number): string;
      };
    };
  };
}

export interface SlashQuery {
  readonly from: number;
  readonly to: number;
  readonly query: string;
}

export function slashQueryAtSelection(state: SlashEditorState): SlashQuery | undefined {
  const { selection } = state;
  if (!selection.empty || !selection.$from.parent.isTextblock) return undefined;
  const text = selection.$from.parent.textBetween(0, selection.$from.parentOffset);
  const match = /^\/(.*)$/.exec(text);
  if (match === null) return undefined;
  return {
    from: selection.from - selection.$from.parentOffset,
    to: selection.from,
    query: match[1] ?? "",
  };
}

export interface BlockCommandTarget {
  focus(): BlockCommandTarget;
  deleteRange(range: { from: number; to: number }): BlockCommandTarget;
  setParagraph(): BlockCommandTarget;
  toggleHeading(options: { level: 1 | 2 | 3 }): BlockCommandTarget;
  toggleBulletList(): BlockCommandTarget;
  toggleOrderedList(): BlockCommandTarget;
  toggleTaskList(): BlockCommandTarget;
  toggleBlockquote(): BlockCommandTarget;
  toggleCodeBlock(): BlockCommandTarget;
  setHorizontalRule(): BlockCommandTarget;
  run(): boolean;
}

export interface BlockCommandEditor {
  readonly state: SlashEditorState;
  chain(): BlockCommandTarget;
}

export function executeBlockCommand(editor: BlockCommandEditor, id: string): boolean {
  if (!BLOCK_COMMANDS.some((item) => item.id === id)) return false;
  const slashQuery = slashQueryAtSelection(editor.state);
  if (slashQuery === undefined) return false;
  const chain = editor.chain()
    .focus()
    .deleteRange({ from: slashQuery.from, to: slashQuery.to });
  switch (id) {
    case "text": return chain.setParagraph().run();
    case "heading1": return chain.toggleHeading({ level: 1 }).run();
    case "heading2": return chain.toggleHeading({ level: 2 }).run();
    case "heading3": return chain.toggleHeading({ level: 3 }).run();
    case "bulletList": return chain.toggleBulletList().run();
    case "orderedList": return chain.toggleOrderedList().run();
    case "taskList": return chain.toggleTaskList().run();
    case "quote": return chain.toggleBlockquote().run();
    case "codeBlock": return chain.toggleCodeBlock().run();
    case "divider": return chain.setHorizontalRule().run();
    default: return false;
  }
}

interface CompositionKeyInput {
  readonly isComposing?: boolean;
  readonly keyCode?: number;
}

export function isCompositionKey(input: CompositionKeyInput): boolean {
  return input.isComposing === true || input.keyCode === 229;
}

export type OverlayRoute = "previous" | "next" | "select" | "dismiss" | "none";

export interface OverlayKeyInput extends CompositionKeyInput {
  readonly key: string;
  readonly isOpen: boolean;
}

export function routeOverlayKey(input: OverlayKeyInput): OverlayRoute {
  if (isCompositionKey(input)) return "none";
  if (!input.isOpen) return "none";
  switch (input.key) {
    case "ArrowUp": return "previous";
    case "ArrowDown": return "next";
    case "Enter": return "select";
    case "Escape": return "dismiss";
    default: return "none";
  }
}
