// CodeMirror 6 + Obsidian 風ライブプレビュー。
// カーソルが乗っていない行は Markdown 記法を隠して描画し、実体は生テキストのまま。
import { EditorState, Compartment } from "@codemirror/state";
import {
  EditorView, keymap, Decoration, WidgetType, ViewPlugin,
  drawSelection, highlightActiveLine, dropCursor, rectangularSelection,
  crosshairCursor, highlightSpecialChars,
} from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxHighlighting, defaultHighlightStyle, HighlightStyle } from "@codemirror/language";
import { autocompletion } from "@codemirror/autocomplete";
import { searchKeymap, highlightSelectionMatches, search } from "@codemirror/search";
import { tags } from "@lezer/highlight";

class ImageWidget extends WidgetType {
  constructor(alt, src, getURL) {
    super();
    this.alt = alt;
    this.src = src;
    this.getURL = getURL;
  }
  eq(o) { return o.src === this.src && o.alt === this.alt; }
  toDOM() {
    const wrap = document.createElement("span");
    wrap.className = "cm-md-img";
    const img = document.createElement("img");
    img.alt = this.alt;
    wrap.appendChild(img);
    Promise.resolve(this.getURL ? this.getURL(this.src) : null).then((u) => {
      if (u) img.src = u;
      else img.replaceWith(document.createTextNode(this.alt || this.src));
    }).catch(() => {});
    return wrap;
  }
  ignoreEvent() { return true; }
}

const RE = {
  heading: /^(#{1,6})\s+/,
  quote: /^(\s*>+\s?)/,
  hr: /^\s*([-*_])(?:\s*\1){2,}\s*$/,
  code: /`([^`\n]+)`/g,
  image: /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
  link: /\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g,
  bold: /\*\*([^*\n]+)\*\*|__([^_\n]+)__/g,
  italic: /(?<![*_])\*([^*\n]+)\*(?!\*)|(?<![*_])_([^_\n]+)_(?!_)/g,
  strike: /~~([^~\n]+)~~/g,
};

function overlaps(occ, a, b) {
  for (const [x, y] of occ) if (a < y && x < b) return true;
  return false;
}

function decorateLine(line, active, decos, cfg) {
  const text = line.text;
  const base = line.from;
  const occ = [];

  const h = RE.heading.exec(text);
  if (h) {
    decos.push(Decoration.line({ class: `cm-md-h${Math.min(h[1].length, 6)}` }).range(base));
    if (!active) {
      occ.push([0, h[0].length]);
      decos.push(Decoration.replace({}).range(base, base + h[0].length));
    }
  }
  if (RE.quote.test(text)) decos.push(Decoration.line({ class: "cm-md-quote" }).range(base));
  if (RE.hr.test(text)) decos.push(Decoration.line({ class: "cm-md-hr" }).range(base));

  const addSpan = (re, handler) => {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text)) !== null) {
      const a = m.index;
      const b = a + m[0].length;
      if (overlaps(occ, a, b)) continue;
      occ.push([a, b]);
      handler(m, a, b);
    }
  };

  if (!active) addSpan(RE.code, (m, a, b) => {
    decos.push(Decoration.mark({ class: "cm-md-code" }).range(base + a + 1, base + b - 1));
    decos.push(Decoration.replace({}).range(base + a, base + a + 1));
    decos.push(Decoration.replace({}).range(base + b - 1, base + b));
  });

  addSpan(RE.image, (m, a, b) => {
    if (active) return;
    decos.push(Decoration.replace({ widget: new ImageWidget(m[1], m[2], cfg.getImageURL) }).range(base + a, base + b));
  });

  addSpan(RE.link, (m, a, b) => {
    const disp = m[1];
    const tg = m[2];
    const dispStart = base + a + 1;
    const dispEnd = dispStart + disp.length;
    const isMd = tg.toLowerCase().endsWith(".md");
    decos.push(Decoration.mark({
      class: isMd ? "cm-md-link cm-md-link-md" : "cm-md-link",
      attributes: isMd ? { "data-md-href": tg } : {},
    }).range(dispStart, dispEnd));
    if (!active) {
      decos.push(Decoration.replace({}).range(base + a, dispStart));
      decos.push(Decoration.replace({}).range(dispEnd, base + b));
    }
  });

  if (!active) addSpan(RE.strike, (m, a, b) => {
    const inner = m[1];
    const s = base + a + 2;
    decos.push(Decoration.mark({ class: "cm-md-strike" }).range(s, s + inner.length));
    decos.push(Decoration.replace({}).range(base + a, s));
    decos.push(Decoration.replace({}).range(s + inner.length, base + b));
  });

  if (!active) addSpan(RE.bold, (m, a, b) => {
    const inner = m[1] || m[2];
    const s = base + a + 2;
    decos.push(Decoration.mark({ class: "cm-md-bold" }).range(s, s + inner.length));
    decos.push(Decoration.replace({}).range(base + a, s));
    decos.push(Decoration.replace({}).range(s + inner.length, base + b));
  });

  if (!active) addSpan(RE.italic, (m, a, b) => {
    const inner = m[1] || m[2];
    const s = base + a + 1;
    decos.push(Decoration.mark({ class: "cm-md-em" }).range(s, s + inner.length));
    decos.push(Decoration.replace({}).range(base + a, s));
    decos.push(Decoration.replace({}).range(s + inner.length, base + b));
  });
}

function buildDecorations(view, cfg) {
  const doc = view.state.doc;
  const decos = [];
  const activeLines = new Set();
  for (const r of view.state.selection.ranges) {
    const a = doc.lineAt(r.from).number;
    const b = doc.lineAt(r.to).number;
    for (let l = a; l <= b; l++) activeLines.add(l);
  }
  for (const { from, to } of view.visibleRanges) {
    let pos = from;
    while (pos <= to) {
      const line = doc.lineAt(pos);
      decorateLine(line, activeLines.has(line.number), decos, cfg);
      if (line.to + 1 > to) break;
      pos = line.to + 1;
    }
  }
  return Decoration.set(decos, true);
}

function livePreview(cfg) {
  return ViewPlugin.fromClass(class {
    constructor(view) { this.decorations = buildDecorations(view, cfg); }
    update(u) {
      if (u.docChanged || u.selectionSet || u.viewportChanged) {
        this.decorations = buildDecorations(u.view, cfg);
      }
    }
  }, {
    decorations: (v) => v.decorations,
    provide: (plugin) => EditorView.atomicRanges.of((view) => view.plugin(plugin)?.decorations || Decoration.none),
  });
}

const mdHighlight = HighlightStyle.define([
  { tag: tags.heading, fontWeight: "700" },
  { tag: tags.strong, fontWeight: "700" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.link, color: "#6aa6ff" },
  { tag: tags.url, color: "#6aa6ff" },
  { tag: tags.monospace, color: "#e5a05a" },
  { tag: tags.comment, color: "#8a8f98" },
  { tag: tags.quote, color: "#9aa0a6" },
]);

const readOnlyCompartment = new Compartment();

export function createEditor(opts) {
  const cfg = {
    getImageURL: opts.getImageURL || (() => null),
    listNotes: opts.listNotes || (() => []),
  };

  const completion = (ctx) => {
    const before = ctx.matchBefore(/\]\(([^)\s]*)$/);
    if (!before) return null;
    const brace = before.text.lastIndexOf("](");
    const from = before.from + brace + 2;
    const options = cfg.listNotes().map((n) => ({ label: n.rel, detail: n.title, type: "text" }));
    return { from, options, validFor: /^[^)\s]*$/ };
  };

  const state = EditorState.create({
    doc: opts.doc || "",
    extensions: [
      highlightSpecialChars(),
      history(),
      drawSelection(),
      dropCursor(),
      rectangularSelection(),
      crosshairCursor(),
      highlightActiveLine(),
      highlightSelectionMatches(),
      search({ top: true }),
      EditorView.lineWrapping,
      markdown({ base: markdownLanguage }),
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      syntaxHighlighting(mdHighlight),
      autocompletion({ override: [completion], activateOnTyping: true }),
      keymap.of([
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
        indentWithTab,
        { key: "Mod-Enter", run: () => { opts.onSave?.(); return true; } },
        { key: "Mod-s", run: () => { opts.onSave?.(); return true; } },
      ]),
      readOnlyCompartment.of([]),
      livePreview(cfg),
      EditorView.updateListener.of((u) => { if (u.docChanged) opts.onChange?.(u.state.doc.toString()); }),
      EditorView.domEventHandlers({
        mousedown: (e) => {
          const el = e.target?.closest?.("[data-md-href]");
          if (el) {
            e.preventDefault();
            opts.onNavigate?.(el.getAttribute("data-md-href"));
            return true;
          }
          return false;
        },
      }),
      EditorView.theme({
        "&": { fontSize: "16px", height: "100%" },
        ".cm-content": { padding: "18px 8px 40vh 8px" },
        ".cm-scroller": { fontFamily: "var(--font-body)", lineHeight: "1.75" },
        ".cm-gutters": { display: "none" },
        "&.cm-focused": { outline: "none" },
      }),
    ],
  });

  const view = new EditorView({ state, parent: opts.parent });

  return {
    view,
    getDoc: () => view.state.doc.toString(),
    setDoc(text) {
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    },
    focus: () => view.focus(),
    setReadOnly(ro) {
      view.dispatch({ effects: readOnlyCompartment.reconfigure(ro ? [EditorState.readOnly.of(true), EditorView.editable.of(false)] : []) });
    },
  };
}
