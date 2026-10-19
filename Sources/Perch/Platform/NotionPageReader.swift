import Foundation
import WebKit

typealias NotionPageReaderCompletion = @MainActor (Result<Any?, Error>) -> Void
typealias NotionPageReaderEvaluator = @MainActor (
    WKWebView,
    NotionPageReaderMode,
    @escaping NotionPageReaderCompletion
) -> Void

/// How the reader script should interpret the page in the web view.
enum NotionPageReaderMode: String, Equatable, Sendable {
    /// Walk Notion's rendered blocks and convert them to Markdown.
    case notion
    /// A custom pinned site: copy the main region's visible text.
    case generic
}

/// Reads the page shown in Perch's web view as agent-ready Markdown.
///
/// The script only reads the DOM. It runs in its own content world so the
/// page's scripts can neither see it nor change what it returns.
@MainActor
enum NotionPageReader {
    static let contentWorldName = "PerchPageReader"

    static let evaluate: NotionPageReaderEvaluator = { webView, mode, completion in
        webView.callAsyncJavaScript(
            NotionPageReader.script,
            arguments: ["mode": mode.rawValue],
            in: nil,
            in: WKContentWorld.world(name: NotionPageReader.contentWorldName)
        ) { result in
            MainActor.assumeIsolated {
                switch result {
                case let .success(value):
                    completion(.success(value))
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// Function body for `callAsyncJavaScript`. `mode` is passed as an argument.
    ///
    /// Notion's class names are not a public contract, so every block the
    /// script does not recognize falls back to its visible text rather than
    /// being dropped.
    static let script = #"""
        const MAX_CHARS = 600000;
        const notionSuffix = /\s*[|–—-]\s*Notion\s*$/;
        const listTypes = new Set(['bulleted_list', 'numbered_list', 'to_do', 'toggle']);
        const textOf = (node) => {
          if (!node) return '';
          const value = typeof node.innerText === 'string' ? node.innerText : node.textContent;
          return (value || '').replace(/ /g, ' ');
        };
        const tidy = (value) => value
          .replace(/\r\n?/g, '\n')
          .replace(/[ \t]+\n/g, '\n')
          .replace(/\n{3,}/g, '\n\n')
          .trim();
        const documentTitle = () => (document.title || '').replace(notionSuffix, '').trim();

        if (mode !== 'notion') {
          const region = document.querySelector('main, article, [role="main"]') || document.body;
          const body = tidy(textOf(region)).slice(0, MAX_CHARS);
          return {
            version: 1,
            title: documentTitle(),
            body,
            coverage: 'text',
            unrecognized: 0,
            truncated: body.length >= MAX_CHARS
          };
        }

        const blockSelector = '[data-block-id]';
        const blockType = (el) => {
          for (const name of el.classList) {
            const match = /^notion-(.+)-block$/.exec(name);
            if (match && match[1] !== 'selectable') return match[1];
          }
          return null;
        };
        const ownerBlock = (node) => node.parentElement ? node.parentElement.closest(blockSelector) : null;
        const childBlocks = (el) => Array.from(el.querySelectorAll(blockSelector))
          .filter((child) => ownerBlock(child) === el);
        const ownLeaf = (el) => Array.from(
          el.querySelectorAll('[data-content-editable-leaf="true"], [contenteditable]')
        ).find((leaf) => leaf.closest(blockSelector) === el) || null;

        const absoluteURL = (href) => {
          try { return new URL(href, location.href).href; } catch (_) { return null; }
        };
        const inline = (node) => {
          if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.replace(/ /g, ' ');
          if (node.nodeType !== Node.ELEMENT_NODE) return '';
          if (node.tagName === 'BR') return '\n';
          const inner = Array.from(node.childNodes).map(inline).join('');
          if (node.tagName === 'A' && node.getAttribute('href')) {
            const url = absoluteURL(node.getAttribute('href'));
            const label = inner.trim();
            if (url && label) return `[${label}](${url})`;
          }
          return inner;
        };
        const leafText = (el) => {
          const leaf = ownLeaf(el);
          return leaf ? inline(leaf).replace(/​/g, '').trim() : '';
        };
        const isChecked = (el) => {
          const input = el.querySelector('input[type="checkbox"]');
          if (input && input.closest(blockSelector) === el) return input.checked;
          const leaf = ownLeaf(el);
          if (!leaf) return false;
          const decoration = getComputedStyle(leaf).textDecorationLine || '';
          return decoration.includes('line-through');
        };
        const tableMarkdown = (el) => {
          const rows = Array.from(el.querySelectorAll('tr')).map((row) =>
            Array.from(row.querySelectorAll('td, th')).map((cell) =>
              tidy(textOf(cell)).replace(/\n+/g, ' ').replace(/\|/g, '\\|')
            )
          ).filter((cells) => cells.length > 0);
          if (rows.length === 0) return tidy(textOf(el));
          const width = Math.max(...rows.map((cells) => cells.length));
          const pad = (cells) => cells.concat(Array(width - cells.length).fill(''));
          const line = (cells) => `| ${pad(cells).join(' | ')} |`;
          return [line(rows[0]), line(Array(width).fill('---')), ...rows.slice(1).map(line)].join('\n');
        };
        const indent = (text, prefix) => text.split('\n').map((line) => line ? prefix + line : line).join('\n');
        const quote = (text) => text.split('\n').map((line) => line ? `> ${line}` : '>').join('\n');

        let unrecognized = 0;
        const renderBlock = (el) => {
          const type = blockType(el);
          const children = childBlocks(el);
          const nested = children.length ? joinBlocks(children) : '';
          const text = leafText(el);
          const withNested = (head, prefix) => nested ? `${head}\n${indent(nested, prefix)}` : head;
          switch (type) {
            case 'header': return `# ${text}`;
            case 'sub_header': return `## ${text}`;
            case 'sub_sub_header': return `### ${text}`;
            case 'text': return withNested(text, '    ');
            case 'bulleted_list': return withNested(`- ${text}`, '    ');
            case 'numbered_list': return withNested(`1. ${text}`, '    ');
            case 'to_do': return withNested(`- [${isChecked(el) ? 'x' : ' '}] ${text}`, '    ');
            case 'toggle': return withNested(`- ${text}`, '    ');
            case 'quote':
            case 'callout':
              return quote([text, nested].filter(Boolean).join('\n\n'));
            case 'code': {
              const leaf = ownLeaf(el);
              const code = (leaf ? textOf(leaf) : textOf(el)).replace(/\n$/, '');
              const fence = code.includes('```') ? '~~~' : '```';
              return `${fence}\n${code}\n${fence}`;
            }
            case 'divider': return '---';
            case 'equation': return `$$\n${tidy(textOf(el))}\n$$`;
            case 'image': {
              const image = el.querySelector('img');
              const alt = image ? (image.getAttribute('alt') || '').trim() : '';
              return alt ? `[image: ${alt}]` : '[image]';
            }
            case 'table': return tableMarkdown(el);
            case 'page':
            case 'alias':
            case 'bookmark': {
              const link = el.querySelector('a[href]');
              const url = link ? absoluteURL(link.getAttribute('href')) : null;
              const label = tidy(textOf(link || el)).replace(/\n+/g, ' ');
              return url && label ? `[${label}](${url})` : label;
            }
            case 'column_list':
            case 'column':
              return nested;
            default: {
              if (children.length && !text) return nested;
              unrecognized += 1;
              return tidy(textOf(el));
            }
          }
        };
        const joinBlocks = (blocks) => {
          let output = '';
          let previousType = null;
          for (const block of blocks) {
            if (output.length >= MAX_CHARS) break;
            const rendered = renderBlock(block);
            if (!rendered) continue;
            const type = blockType(block);
            const tight = listTypes.has(type) && listTypes.has(previousType);
            output += output ? (tight ? '\n' : '\n\n') + rendered : rendered;
            previousType = type;
          }
          return output;
        };

        const root = document.querySelector('.notion-page-content');
        const titleNode = document.querySelector(
          '.notion-frame h1, .notion-page-block h1, .notion-page-block [data-content-editable-leaf="true"]'
        );
        const title = tidy(textOf(titleNode)).replace(/\n+/g, ' ') || documentTitle();

        if (!root) {
          const region = document.querySelector('.notion-frame') || document.querySelector('main') || document.body;
          const body = tidy(textOf(region)).slice(0, MAX_CHARS);
          return { version: 1, title, body, coverage: 'text', unrecognized: 0, truncated: body.length >= MAX_CHARS };
        }

        const topBlocks = Array.from(root.querySelectorAll(blockSelector)).filter((block) => {
          const owner = ownerBlock(block);
          return !owner || !root.contains(owner);
        });
        const body = tidy(joinBlocks(topBlocks)).slice(0, MAX_CHARS);
        return {
          version: 1,
          title,
          body,
          coverage: 'blocks',
          unrecognized,
          truncated: body.length >= MAX_CHARS
        };
        """#
}
