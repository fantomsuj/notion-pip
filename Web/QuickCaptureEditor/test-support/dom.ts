import { Window } from "happy-dom";

export function installTestDOM(): Window {
  const testWindow = new Window({ url: "https://notion-pip.test/" });
  const globalValues: Record<string, unknown> = {
    window: testWindow,
    document: testWindow.document,
    navigator: testWindow.navigator,
    Node: testWindow.Node,
    Element: testWindow.Element,
    HTMLElement: testWindow.HTMLElement,
    HTMLButtonElement: testWindow.HTMLButtonElement,
    HTMLInputElement: testWindow.HTMLInputElement,
    KeyboardEvent: testWindow.KeyboardEvent,
    Event: testWindow.Event,
    InputEvent: testWindow.InputEvent,
    ClipboardEvent: testWindow.ClipboardEvent,
    MutationObserver: testWindow.MutationObserver,
    DOMParser: testWindow.DOMParser,
    getComputedStyle: testWindow.getComputedStyle.bind(testWindow),
    requestAnimationFrame: testWindow.requestAnimationFrame.bind(testWindow),
    cancelAnimationFrame: testWindow.cancelAnimationFrame.bind(testWindow),
  };
  for (const [name, value] of Object.entries(globalValues)) {
    Object.defineProperty(globalThis, name, {
      configurable: true,
      value,
      writable: true,
    });
  }
  return testWindow;
}
