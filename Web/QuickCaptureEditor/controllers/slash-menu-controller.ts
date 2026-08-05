import type { Editor } from "@tiptap/core";

import {
  executeBlockCommand,
  filterBlockCommands,
  routeOverlayKey,
  slashQueryAtSelection,
  type BlockCommand,
} from "../block-commands.ts";

export class SlashMenuController {
  private items: readonly BlockCommand[] = [];
  private activeIndex = 0;
  private readonly menu: HTMLElement;
  private readonly page: HTMLElement | null;

  constructor(menu: HTMLElement, page: HTMLElement | null) {
    this.menu = menu;
    this.page = page;
  }

  get isOpen(): boolean {
    return !this.menu.hidden;
  }

  handleKeyDown(editor: Editor, event: KeyboardEvent): boolean {
    const route = routeOverlayKey({
      key: event.key,
      isOpen: this.isOpen,
      isComposing: event.isComposing,
      keyCode: event.keyCode,
    });
    if (route === "none") return false;

    event.preventDefault();
    if (route === "dismiss") {
      this.close(editor);
    } else if (route === "select") {
      const selected = this.items[this.activeIndex];
      if (selected !== undefined) executeBlockCommand(editor, selected.id);
      this.close(editor);
    } else if (this.items.length > 0) {
      const change = route === "previous" ? -1 : 1;
      this.activeIndex = (this.activeIndex + change + this.items.length) % this.items.length;
      this.render(editor);
    }
    return true;
  }

  refresh(editor: Editor, isLocked: boolean): void {
    if (!editor.isEditable || isLocked) {
      this.close(editor);
      return;
    }
    const slashQuery = slashQueryAtSelection(editor.state);
    if (slashQuery === undefined) {
      this.close(editor);
      return;
    }
    const items = filterBlockCommands(slashQuery.query);
    if (items.length === 0) {
      this.close(editor);
      return;
    }
    const wasOpen = this.isOpen;
    this.items = items;
    this.activeIndex = wasOpen
      ? Math.min(this.activeIndex, this.items.length - 1)
      : 0;
    this.render(editor);

    const parentRect = this.page?.getBoundingClientRect()
      ?? this.menu.offsetParent?.getBoundingClientRect();
    if (parentRect !== undefined) {
      const caret = editor.view.coordsAtPos(slashQuery.to);
      this.menu.style.left = `${Math.max(0, caret.left - parentRect.left)}px`;
      this.menu.style.top = `${Math.max(0, caret.bottom - parentRect.top + 6)}px`;
    }
  }

  close(editor: Editor): void {
    if (!this.isOpen && this.items.length === 0) return;
    this.menu.hidden = true;
    this.menu.replaceChildren();
    this.items = [];
    this.activeIndex = 0;
    this.menu.removeAttribute("aria-activedescendant");
    editor.view.dom.setAttribute("aria-expanded", "false");
    editor.view.dom.removeAttribute("aria-activedescendant");
  }

  private render(editor: Editor): void {
    const options = this.items.map((item, index) => {
      const option = document.createElement("button");
      option.type = "button";
      option.id = `slash-option-${item.id}`;
      option.className = "slash-option";
      option.setAttribute("role", "option");
      option.setAttribute("aria-selected", String(index === this.activeIndex));
      option.tabIndex = -1;
      option.textContent = item.label;
      option.addEventListener("mousedown", (event) => { event.preventDefault(); });
      option.addEventListener("click", () => {
        executeBlockCommand(editor, item.id);
        this.close(editor);
      });
      return option;
    });
    this.menu.replaceChildren(...options);
    this.menu.hidden = false;
    const activeID = options[this.activeIndex]?.id;
    editor.view.dom.setAttribute("aria-expanded", "true");
    if (activeID === undefined) {
      this.menu.removeAttribute("aria-activedescendant");
      editor.view.dom.removeAttribute("aria-activedescendant");
    } else {
      this.menu.setAttribute("aria-activedescendant", activeID);
      editor.view.dom.setAttribute("aria-activedescendant", activeID);
    }
    options[this.activeIndex]?.scrollIntoView({ block: "nearest", inline: "nearest" });
  }
}
