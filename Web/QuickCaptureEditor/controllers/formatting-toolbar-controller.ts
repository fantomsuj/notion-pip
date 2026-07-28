import type { Editor } from "@tiptap/core";

import {
  executeFormattingCommand,
  formattingState,
  isLinkPaste,
  type FormattingCommand,
} from "../formatting.ts";

export class FormattingToolbarController {
  private readonly toolbar: HTMLElement;
  private readonly page: HTMLElement | null;
  private readonly buttons: HTMLButtonElement[];
  private isLocked: (() => boolean) | undefined;

  constructor(toolbar: HTMLElement, page: HTMLElement | null) {
    this.toolbar = toolbar;
    this.page = page;
    this.buttons = Array.from(
      toolbar.querySelectorAll<HTMLButtonElement>("[data-format]"),
    );
  }

  bind(editor: Editor, isLocked: () => boolean): void {
    this.isLocked = isLocked;
    this.buttons.forEach((button) => this.bindButton(editor, button));
    this.toolbar.addEventListener("focusout", () => {
      setTimeout(() => {
        if (!this.hasRegionFocus(editor)) this.close();
      }, 0);
    });
  }

  handleEditorKeyDown(editor: Editor, event: KeyboardEvent): boolean {
    if (event.key === "Escape" && !this.toolbar.hidden) {
      event.preventDefault();
      this.close();
      return true;
    }
    if (event.key === "Tab"
        && event.shiftKey !== true
        && !this.toolbar.hidden
        && !editor.view.state.selection.empty) {
      event.preventDefault();
      this.buttons[0]?.focus();
      return true;
    }
    return false;
  }

  refresh(editor: Editor, isLocked: boolean): void {
    const { selection } = editor.state;
    const selectedText = editor.state.doc.textBetween(selection.from, selection.to);
    if (!editor.isEditable
        || isLocked
        || (!editor.isFocused && !this.toolbar.contains(document.activeElement))
        || selection.empty
        || selectedText.length === 0) {
      this.close();
      return;
    }

    const active = formattingState(editor);
    this.buttons.forEach((button) => {
      const command = button.dataset.format as FormattingCommand | undefined;
      button.setAttribute("aria-pressed", String(command !== undefined && active[command]));
    });
    this.toolbar.hidden = false;

    const parentRect = this.page?.getBoundingClientRect()
      ?? this.toolbar.offsetParent?.getBoundingClientRect();
    if (parentRect === undefined) return;
    const start = editor.view.coordsAtPos(selection.from);
    const end = editor.view.coordsAtPos(selection.to);
    const selectionCenter = (Math.min(start.left, end.left) + Math.max(start.right, end.right)) / 2;
    const left = selectionCenter - parentRect.left - this.toolbar.offsetWidth / 2;
    this.toolbar.style.left = `${Math.max(0, Math.min(left, parentRect.width - this.toolbar.offsetWidth))}px`;
    this.toolbar.style.top = `${Math.max(0, Math.min(start.top, end.top) - parentRect.top - this.toolbar.offsetHeight - 8)}px`;
  }

  close(): void {
    this.toolbar.hidden = true;
  }

  handleEditorBlur(editor: Editor): void {
    setTimeout(() => {
      if (!this.hasRegionFocus(editor)) this.close();
    }, 0);
  }

  setMutationLocked(locked: boolean): void {
    this.buttons.forEach((button) => { button.disabled = locked; });
    if (locked) this.close();
  }

  private bindButton(editor: Editor, button: HTMLButtonElement): void {
    const retainEditorFocus = (event: Event): void => { event.preventDefault(); };
    button.addEventListener("pointerdown", retainEditorFocus);
    button.addEventListener("mousedown", retainEditorFocus);
    button.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        this.close();
        editor.view.focus();
      } else if (event.key === " "
          || event.key === "Spacebar"
          || event.key === "Enter"
          || event.code === "Space"
          || event.code === "Enter"
          || event.keyCode === 32
          || event.keyCode === 13) {
        event.preventDefault();
        button.click();
      } else if (event.key === "Tab") {
        const index = this.buttons.indexOf(button);
        const target = this.buttons[index + (event.shiftKey ? -1 : 1)];
        if (target !== undefined) {
          event.preventDefault();
          target.focus();
        } else if (event.shiftKey && index === 0) {
          event.preventDefault();
          setTimeout(() => this.restoreEditorSelectionFocus(editor), 0);
        }
      }
    });
    button.addEventListener("click", () => {
      const command = button.dataset.format as FormattingCommand | undefined;
      if (command === undefined) return;
      const activatedFromKeyboard = document.activeElement === button;
      let href: string | undefined;
      if (command === "link" && !editor.isActive("link")) {
        const candidate = window.prompt("Paste a link");
        if (candidate === null || !isLinkPaste(editor.state.selection, candidate)) {
          if (activatedFromKeyboard) button.focus();
          else editor.view.focus();
          this.refresh(editor, this.isLocked?.() ?? true);
          return;
        }
        href = candidate.trim();
      }
      executeFormattingCommand(editor, command, href);
      if (activatedFromKeyboard) button.focus();
      else editor.view.focus();
      this.refresh(editor, this.isLocked?.() ?? true);
    });
  }

  private hasRegionFocus(editor: Editor): boolean {
    const focused = document.activeElement;
    return focused !== null
      && (editor.view.dom.contains(focused) || this.toolbar.contains(focused));
  }

  private restoreEditorSelectionFocus(editor: Editor): void {
    editor.commands.focus(null, { scrollIntoView: false });
    editor.view.dom.focus({ preventScroll: true });
    editor.view.focus();
    this.refresh(editor, this.isLocked?.() ?? true);
  }
}
