import * as vault from "./vault.js";
import { runSync, parseNote, dumpTitleState, relPath, dirname, basename, stem, normalizePath, UP_MARK, RELATED_MARK, DOWN_MARK } from "./sync.js";
import { createEditor } from "./editor.js";

const LINK_LINE_RE = /^\s*(\[[^\]]*\]\([^)]+\))\s*(?:—\s*\S+)?\s*$/;
const INLINE_LINK_RE = /\[([^\]]*)\]\(([^)]+)\)/;

const state = {
  root: null,
  files: new Map(),
  rels: [],
  notes: new Map(),
  titleState: {},
  tabs: [],
  current: null,
  parentLines: [],
  relatedLines: [],
  backLines: [],
  fm: [],
  dirty: false,
  loading: false,
};

const els = {};
let editor = null;

function $(id) { return document.getElementById(id); }

// ---------------------------------------------------------------- utilities

function toast(msg) {
  const t = $("toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast._t);
  toast._t = setTimeout(() => t.classList.remove("show"), 2200);
}

function parseAll() {
  state.notes = new Map();
  for (const rel of state.rels) state.notes.set(rel, parseNote(state.files.get(rel) || "", rel));
}

function resolver(target, baseDir) {
  const t = String(target).split("#")[0].trim();
  if (!t) return null;
  const cand = t.startsWith("/") ? normalizePath(t.slice(1)) : normalizePath((baseDir ? baseDir + "/" : "") + t);
  return state.notes.has(cand) ? cand : null;
}

function linkLines(lines, rel) {
  const out = [];
  for (const ln of lines) {
    const m = INLINE_LINK_RE.exec(ln);
    if (!m) continue;
    const target = m[2].split("#")[0].trim();
    if (!target.toLowerCase().endsWith(".md")) continue;
    const rp = resolver(target, dirname(rel));
    if (rp) out.push({ rel: rp, title: state.notes.get(rp)?.title || stem(rp) });
  }
  return out;
}

function titleOf(rel) { return state.notes.get(rel)?.title || stem(rel); }

// ---------------------------------------------------------------- vault open

async function boot() {
  wireToolbar();
  // Electron ならパス固定で自動オープン。フォルダ選択は無い。
  if (vault.isElectron()) {
    await openVault(null);
    return;
  }
  // ここから下はブラウザで開いた場合。基本は Electron を案内する。
  const electronUA = /Electron/i.test(navigator.userAgent);
  const canFSA = typeof window.showDirectoryPicker === "function";
  $("overlay").hidden = false;
  $("overlay-open").style.display = "none";
  $("overlay-pick").style.display = "none";
  if (electronUA) {
    $("overlay-msg").innerHTML = "アプリの初期化に失敗しました（preload 未読込）。<br>"
      + "一度閉じて <b>\\A</b> または <code>npm run app</code> で起動し直してください。";
    return;
  }
  if (!canFSA) {
    $("overlay-msg").innerHTML = "このアプリは <b>Electron</b> で起動してください。<br>"
      + "Vim で <b>\\A</b>、または <code>web/bin/simple-yurii-note-app.sh</code>。<br>"
      + "<small>ブラウザ（Brave / Firefox）ではノートを読み書きできません。</small>";
    return;
  }
  $("overlay-msg").innerHTML = "このアプリは <b>Electron</b> での利用を推奨します。<br>"
    + "Chrome 系ブラウザで続ける場合だけ、下のボタンでフォルダを選べます。";
  $("overlay-pick").textContent = "Chrome: フォルダを選ぶ";
  $("overlay-pick").style.display = "";
  $("overlay-pick").onclick = pickAndOpen;
}

async function pickAndOpen() {
  try {
    const handle = await vault.pickVault();
    $("overlay").hidden = true;
    await openVault(handle);
  } catch (e) {
    if (e?.name === "AbortError") return;
    const msg = $("overlay-msg");
    if (e?.name === "SecurityError" || /security|not allowed|denied/i.test(e?.message || "")) {
      msg.innerHTML = "ブラウザがフォルダ選択を許可しませんでした。<br>"
        + "<b>Electron アプリ</b>を使ってください（Vim で <b>\\A</b>）。";
      $("overlay").hidden = false;
    } else {
      msg.textContent = "選択できませんでした: " + (e?.message || e);
      $("overlay").hidden = false;
    }
  }
}

async function openVault(handle) {
  state.root = handle;
  const { files, rels, titleState } = await vault.readVault(handle);
  state.files = files;
  state.rels = rels;
  state.titleState = titleState;
  parseAll();
  $("toolbar").classList.add("ready");
  $("vault-name").textContent = vault.isElectron() ? (vault.rootName() || "vault") : handle.name;
  renderSidebar();
  const start = state.notes.has("index.md") ? "index.md" : state.rels[0];
  if (start) openNote(start);
  window.addEventListener("focus", refreshFromDisk);
}

async function refreshFromDisk() {
  if (!state.root || state.dirty) return;
  try {
    const { files, rels } = await vault.readVault(state.root);
    state.files = files; state.rels = rels; parseAll();
    renderSidebar();
    if (state.current && !state.dirty) {
      const n = state.notes.get(state.current);
      if (n && editor.getDoc() !== n.body.join("\n")) loadNoteToEditor(n);
    }
    renderRelations();
  } catch { /* ignore */ }
}

// ---------------------------------------------------------------- sidebar

function renderSidebar() {
  const q = ($("search").value || "").trim().toLowerCase();
  const words = q ? q.split(/\s+/) : [];
  const list = [];
  for (const rel of state.rels) {
    const n = state.notes.get(rel);
    const hay = (n.title + " " + n.body.join("\n")).toLowerCase();
    if (words.length && !words.every((w) => hay.includes(w))) continue;
    list.push({ rel, title: n.title, group: n.attr === "group" || basename(rel) === "index.md" });
  }
  list.sort((a, b) => a.title.localeCompare(b.title, "ja"));
  const box = $("note-list");
  box.innerHTML = "";
  for (const it of list) {
    const d = document.createElement("div");
    d.className = "note-item" + (it.rel === state.current ? " active" : "") + (it.group ? " is-group" : "");
    d.innerHTML = `<span class="ni-title"></span><span class="ni-file"></span>`;
    d.querySelector(".ni-title").textContent = it.title || stem(it.rel);
    d.querySelector(".ni-file").textContent = it.group ? "group" : stem(it.rel);
    d.onclick = () => openNote(it.rel);
    box.appendChild(d);
  }
}

function renderTabs() {
  const box = $("tabs");
  box.innerHTML = "";
  for (const rel of state.tabs) {
    const t = document.createElement("div");
    t.className = "tab" + (rel === state.current ? " active" : "");
    const s = document.createElement("span");
    s.textContent = titleOf(rel);
    const x = document.createElement("button");
    x.textContent = "×";
    x.onclick = (e) => { e.stopPropagation(); closeTab(rel); };
    t.append(s, x);
    t.onclick = () => openNote(rel);
    box.appendChild(t);
  }
}

// ---------------------------------------------------------------- open note

async function openNote(rel) {
  if (!state.notes.has(rel)) { toast("見つかりません: " + rel); return; }
  if (state.current === rel) { renderSidebar(); renderTabs(); return; }
  if (state.dirty) {
    const ok = await saveCurrent({ autosave: true });
    if (!ok && !confirm("保存できませんでした（Vim が使用中の可能性）。破棄して移動しますか？")) return;
    state.dirty = false;
    updateDirtyUI();
  }
  if (!state.tabs.includes(rel)) state.tabs.push(rel);
  state.current = rel;
  const n = state.notes.get(rel);
  loadNoteToEditor(n);
  renderTabs();
  renderSidebar();
  renderRelations();
  $("title-input").value = n.title;
  $("title-input").disabled = false;
  $("empty").hidden = true;
  $("note-view").hidden = false;
  updateDirtyUI();
}

function loadNoteToEditor(n) {
  state.fm = n.fm.slice();
  state.parentLines = n.parent.slice();
  state.relatedLines = n.related.slice();
  state.backLines = n.back.slice();
  state.loading = true;
  editor.setDoc(n.body.join("\n"));
  state.loading = false;
}

function closeTab(rel) {
  const i = state.tabs.indexOf(rel);
  if (i >= 0) state.tabs.splice(i, 1);
  if (state.current === rel) {
    const next = state.tabs[Math.max(0, i - 1)];
    if (next) openNote(next);
    else { state.current = null; $("note-view").hidden = true; $("empty").hidden = false; $("title-input").disabled = true; renderTabs(); renderRelations(); }
  } else renderTabs();
}

// ---------------------------------------------------------------- relations panel

function renderRelations() {
  const rel = state.current;
  const setList = (boxId, items, { removable = false, addLabel = null, onAdd = null } = {}) => {
    const box = $(boxId);
    box.innerHTML = "";
    const h = document.createElement("div");
    h.className = "rel-head";
    h.textContent = box.dataset.label || "";
    const ul = document.createElement("div");
    ul.className = "rel-list";
    for (const it of items) {
      const row = document.createElement("div");
      row.className = "rel-item";
      const a = document.createElement("a");
      a.textContent = it.title;
      a.onclick = () => openNote(it.rel);
      row.appendChild(a);
      if (removable) {
        const b = document.createElement("button");
        b.textContent = "×"; b.title = "外す";
        b.onclick = () => { it.remove(); };
        row.appendChild(b);
      }
      ul.appendChild(row);
    }
    if (items.length === 0) {
      const e = document.createElement("div"); e.className = "rel-empty"; e.textContent = "なし"; ul.appendChild(e);
    }
    box.append(h, ul);
    if (addLabel) {
      const b = document.createElement("button");
      b.className = "rel-add"; b.textContent = addLabel;
      b.onclick = onAdd;
      box.appendChild(b);
    }
  };

  if (!rel) {
    $("rel-parent").innerHTML = ""; $("rel-related").innerHTML = ""; $("rel-children").innerHTML = ""; $("rel-back").innerHTML = "";
    return;
  }
  const n = state.notes.get(rel);

  const parents = linkLines(state.parentLines, rel).map((it) => ({
    ...it,
    remove: () => {
      const idx = state.parentLines.findIndex((ln) => {
        const m = INLINE_LINK_RE.exec(ln);
        return m && resolver(m[2], dirname(rel)) === it.rel;
      });
      if (idx >= 0) { state.parentLines.splice(idx, 1); markDirty(); renderRelations(); }
    },
  }));
  setList("rel-parent", parents, { removable: true, addLabel: "＋ 親を追加", onAdd: () => pickNote((r) => addParent(r)) });

  const relatedItems = linkLines(state.relatedLines, rel).map((it) => ({
    ...it,
    remove: () => {
      const idx = state.relatedLines.findIndex((ln) => {
        const m = INLINE_LINK_RE.exec(ln);
        return m && resolver(m[2], dirname(rel)) === it.rel;
      });
      if (idx >= 0) { state.relatedLines.splice(idx, 1); markDirty(); renderRelations(); }
    },
  }));
  setList("rel-related", relatedItems, { removable: true, addLabel: "＋ 関連を追加", onAdd: () => pickNote((r) => addRelated(r)) });

  const children = linkLines(n.body, rel).map((it) => ({ ...it }));
  setList("rel-children", children, { addLabel: "＋ 子を追加", onAdd: () => pickNote((r) => addChild(r)) });

  const backs = linkLines(n.back, rel).map((it) => ({ ...it }));
  setList("rel-back", backs);
}

function addParent(targetRel) {
  const rel = state.current;
  const line = `[${titleOf(targetRel)}](${relPath(dirname(rel), targetRel)})`;
  if (!state.parentLines.some((l) => { const m = INLINE_LINK_RE.exec(l); return m && resolver(m[2], dirname(rel)) === targetRel; })) {
    state.parentLines.push(line);
    markDirty(); renderRelations(); toast("親に追加（保存で反映）");
  }
}

// zr 相当: ### Related に相互追加（今のノートと相手の両方に書く）。
// sync は Related を勝手に作らないので、ここで両ノートを明示的に書く。
async function addRelated(targetRel) {
  const rel = state.current;
  if (!rel || rel === targetRel) return;
  const dupIn = (lines, dir, want) => lines.some((l) => {
    const m = INLINE_LINK_RE.exec(l);
    return m && resolver(m[2], dir) === want;
  });
  const tn = state.notes.get(targetRel);
  if (!tn) return;
  if (!dupIn(state.relatedLines, dirname(rel), targetRel)) {
    state.relatedLines.push(`[${titleOf(targetRel)}](${relPath(dirname(rel), targetRel)})`);
  }
  if (!dupIn(tn.related, dirname(targetRel), rel)) {
    tn.related.push(`[${titleOf(rel)}](${relPath(dirname(targetRel), rel)})`);
  }
  const title = $("title-input").value.trim() || stem(rel);
  const overrides = new Map([
    [rel, assembleNote(rel, {
      fm: setFmTitle(state.fm, title), body: [], parent: state.parentLines,
      related: state.relatedLines, back: state.backLines,
    }, editor.getDoc().split("\n"))],
    [targetRel, assembleNote(targetRel, tn)],
  ]);
  await syncAndWrite(overrides);
  toast("関連に相互追加しました");
}

function addChild(targetRel) {
  const rel = state.current;
  const line = `[${titleOf(targetRel)}](${relPath(dirname(rel), targetRel)})`;
  const body = editor.getDoc();
  if (!body.includes(`](${relPath(dirname(rel), targetRel)})`)) {
    editor.setDoc((body.trimEnd() ? body.trimEnd() + "\n" : "") + line);
    markDirty(); toast("子に追加（保存で反映）");
  }
}

// ---------------------------------------------------------------- pick note modal

function pickNote(cb) {
  const m = $("modal");
  m.hidden = false;
  m.innerHTML = "";
  const box = document.createElement("div");
  box.className = "modal-box";
  const inp = document.createElement("input");
  inp.placeholder = "ノートを検索…";
  const list = document.createElement("div");
  list.className = "modal-list";
  const render = () => {
    const q = inp.value.trim().toLowerCase();
    list.innerHTML = "";
    for (const rel of state.rels) {
      if (rel === state.current) continue;
      const t = titleOf(rel).toLowerCase();
      if (q && !t.includes(q) && !rel.toLowerCase().includes(q)) continue;
      const d = document.createElement("div");
      d.className = "modal-item";
      d.textContent = titleOf(rel) + "  (" + stem(rel) + ")";
      d.onclick = () => { m.hidden = true; cb(rel); };
      list.appendChild(d);
    }
  };
  inp.oninput = render;
  box.append(inp, list);
  m.appendChild(box);
  render();
  inp.focus();
  m.onclick = (e) => { if (e.target === m) m.hidden = true; };
}

// ---------------------------------------------------------------- save & sync

function markDirty() { state.dirty = true; updateDirtyUI(); scheduleAutosave(); }

let autosaveTimer = null;
let autosaveBusy = false;
const AUTOSAVE_MS = 1200;

function scheduleAutosave() {
  if (autosaveTimer) clearTimeout(autosaveTimer);
  autosaveTimer = setTimeout(() => { autosaveTimer = null; runAutosave(); }, AUTOSAVE_MS);
}

async function runAutosave() {
  if (!state.dirty || !state.current) return;
  if (autosaveBusy) { scheduleAutosave(); return; }
  autosaveBusy = true;
  try { await saveCurrent({ autosave: true }); }
  finally { autosaveBusy = false; }
}

function updateDirtyUI() {
  $("note-view").classList.toggle("dirty", state.dirty);
  $("save-btn").disabled = !state.dirty;
  $("save-state").textContent = state.dirty ? "編集中…" : "自動保存済";
}

function setFmTitle(fm, title) {
  const out = fm.slice();
  for (let i = 0; i < out.length; i++) {
    if (/^\s*title\s*:/.test(out[i])) { out[i] = "title: " + title; return out; }
  }
  if (out.length && out[out.length - 1].trim() === "---") out.splice(out.length - 1, 0, "title: " + title);
  else out.push("title: " + title);
  return out;
}

// ノート 1 つ分のテキストを組み立てる（saveCurrent と同じ並び）。
// bodyLines を渡せばそれを本文に、省略すれば n.body を使う。
function assembleNote(rel, n, bodyLines) {
  const lines = [...n.fm, ...(bodyLines !== undefined ? bodyLines : n.body)];
  if (basename(rel) !== "index.md") {
    const last = lines[lines.length - 1];
    if (last === undefined || (last.trim() !== "" && !LINK_LINE_RE.test(last))) lines.push("");
    lines.push(UP_MARK, ...n.parent);
    if (n.related.some((l) => l.trim() !== "")) lines.push(RELATED_MARK, ...n.related);
    lines.push(DOWN_MARK, ...n.back);
  }
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
  return lines.join("\n") + "\n";
}

async function saveCurrent(opts = {}) {
  const rel = state.current;
  if (!rel) return true;
  if (autosaveTimer) { clearTimeout(autosaveTimer); autosaveTimer = null; }
  if (await vault.hasSwap(state.root, rel)) {
    if (opts.autosave) { $("save-state").textContent = "Vim が使用中"; return false; }
    if (!confirm("Vim がこのノートを開いている可能性があります（.swp あり）。保存しますか？")) return false;
  }
  if (!opts.autosave) $("save-state").textContent = "保存中…";
  const title = $("title-input").value.trim() || stem(rel);
  const fm = setFmTitle(state.fm, title);
  const bodyLines = editor.getDoc().split("\n");
  const raw = assembleNote(rel, { fm, body: [], parent: state.parentLines, related: state.relatedLines, back: state.backLines }, bodyLines);
  await syncAndWrite(new Map([[rel, raw]]));
  if (!opts.autosave) toast("保存しました");
  return true;
}

// state.files は「最後にディスクと一致していた内容」を保つ。
// 編集は overrides として渡し、sync 後の最終テキストがディスクと違うものだけ書く。
async function syncAndWrite(overrides) {
  if (vault.isElectron()) {
    // Electron: 生テキストを書いて Python sync に任せる（同期の正は Python）
    const writes = [];
    if (overrides) for (const [rel, text] of overrides) writes.push({ rel, text });
    await vault.apply(state.root, { writes });
    const rv = await vault.readVault(null);
    state.files = rv.files;
    state.rels = rv.rels;
    state.titleState = rv.titleState;
    parseAll();
    renderSidebar();
    syncSelfFromNotes();
    renderRelations();
    renderTabs();
    state.dirty = false;
    updateDirtyUI();
    return;
  }
  const input = new Map(state.files);
  if (overrides) for (const [k, v] of overrides) input.set(k, v);
  const res = runSync(input, state.titleState);
  for (const [file, text] of input) {
    const finalText = res.changed.has(file) ? res.changed.get(file) : text;
    if (finalText !== state.files.get(file)) {
      await vault.writeFile(state.root, file, finalText);
      state.files.set(file, finalText);
    }
  }
  if (res.titleStateChanged) {
    await vault.writeFile(state.root, ".pkm_title_state_v2.json", dumpTitleState(res.titleState));
    state.titleState = res.titleState;
  }
  state.rels = [...state.files.keys()].sort();
  parseAll();
  renderSidebar();
  syncSelfFromNotes();
  renderRelations();
  renderTabs();
  state.dirty = false;
  updateDirtyUI();
}

function syncSelfFromNotes() {
  const n = state.notes.get(state.current);
  if (!n) return;
  state.fm = n.fm.slice();
  state.parentLines = n.parent.slice();
  state.relatedLines = n.related.slice();
  state.backLines = n.back.slice();
  const body = n.body.join("\n");
  if (editor.getDoc() !== body) { state.loading = true; editor.setDoc(body); state.loading = false; }
}

// ---------------------------------------------------------------- new / delete

function timestampName() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${String(d.getFullYear()).slice(2)}${p(d.getMonth() + 1)}${p(d.getDate())}${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.md`;
}

function isoNow() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

async function newNote(isGroup) {
  let name = timestampName();
  while (state.files.has(name)) name = timestampName();
  const t = name.replace(/\.md$/, "");
  const attr = isGroup ? "attribute: group\n" : "";
  let text = `---\ntime: ${isoNow()}\ntitle: ${t}\n${attr}---\n\n# ${t}\n\n`;
  const cur = state.current;
  const overrides = new Map();
  if (cur) {
    text += "\n" + UP_MARK + "\n" + `[${titleOf(cur)}](${cur})` + "\n" + DOWN_MARK + "\n";
    // 今のノート側に子リンクを足す
    const link = `[${t}](${relPath(dirname(cur), name)})`;
    const curNote = state.notes.get(cur);
    const bodyLines = [...curNote.body];
    while (bodyLines.length && bodyLines[bodyLines.length - 1].trim() === "") bodyLines.pop();
    if (bodyLines.length && !LINK_LINE_RE.test(bodyLines[bodyLines.length - 1])) bodyLines.push("");
    bodyLines.push(link);
    const lines = [...state.fm, ...bodyLines, UP_MARK, ...state.parentLines];
    if (state.relatedLines.some((l) => l.trim() !== "")) lines.push(RELATED_MARK, ...state.relatedLines);
    lines.push(DOWN_MARK, ...state.backLines);
    overrides.set(cur, lines.join("\n") + "\n");
  } else {
    text += "\n" + UP_MARK + "\n" + DOWN_MARK + "\n";
  }
  overrides.set(name, text);
  await syncAndWrite(overrides);
  openNote(name);
  toast(isGroup ? "グループを作成しました" : "ノートを作成しました");
}

async function deleteCurrent() {
  const rel = state.current;
  if (!rel) return;
  if (!confirm(`「${titleOf(rel)}」を削除しますか？（実ファイルを削除します）`)) return;
  await vault.deleteFile(state.root, rel);
  state.files.delete(rel);
  state.rels = state.rels.filter((r) => r !== rel);
  state.tabs = state.tabs.filter((r) => r !== rel);
  state.current = null;
  await syncAndWrite();
  const next = state.tabs[state.tabs.length - 1] || (state.notes.has("index.md") ? "index.md" : state.rels[0]);
  if (next) openNote(next);
  else { $("note-view").hidden = true; $("empty").hidden = false; }
  toast("削除しました");
}

// ---------------------------------------------------------------- toolbar wiring

function wireToolbar() {
  $("open-btn").onclick = pickAndOpen;
  $("save-btn").onclick = saveCurrent;
  $("new-btn").onclick = () => newNote(false);
  $("new-group-btn").onclick = () => newNote(true);
  $("delete-btn").onclick = deleteCurrent;
  $("theme-btn").onclick = toggleTheme;
  $("search").oninput = renderSidebar;
  $("title-input").oninput = markDirty;
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") { e.preventDefault(); saveCurrent(); }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "o") { e.preventDefault(); $("search").focus(); $("search").select(); }
    if (e.key === "Escape") { $("modal").hidden = true; }
  });
  // 自動保存: タブを隠す/閉じる前に書き残す
  document.addEventListener("visibilitychange", () => {
    if (document.hidden && state.dirty) saveCurrent({ autosave: true });
  });
  window.addEventListener("beforeunload", (e) => {
    if (state.dirty) { e.preventDefault(); e.returnValue = ""; }
  });
}

// ---------------------------------------------------------------- theme

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  try { localStorage.setItem("pkm-theme", theme); } catch { /* ignore */ }
  const b = $("theme-btn");
  if (b) b.textContent = theme === "dark" ? "☀" : "🌙";
}

function toggleTheme() {
  applyTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
}

function initTheme() {
  let t = "light";
  try { t = localStorage.getItem("pkm-theme") || "light"; } catch { /* ignore */ }
  applyTheme(t);
}

// ---------------------------------------------------------------- boot

function init() {
  for (const id of ["overlay", "overlay-msg", "overlay-open", "overlay-pick", "toolbar", "vault-name",
    "search", "note-list", "tabs", "title-input", "editor", "empty", "note-view", "save-btn",
    "new-btn", "new-group-btn", "delete-btn", "theme-btn", "modal",
    "toast", "save-state", "open-btn", "rel-parent", "rel-related", "rel-children", "rel-back"]) {
    els[id] = $(id);
  }
  $("rel-parent").dataset.label = "親 (Parent)";
  $("rel-related").dataset.label = "関連 (Related)";
  $("rel-children").dataset.label = "子 (本文リンク)";
  $("rel-back").dataset.label = "被リンク (BackLink)";
  initTheme();

  editor = createEditor({
    parent: $("editor"),
    doc: "",
    onChange: () => { if (!state.loading) markDirty(); },
    onSave: saveCurrent,
    onNavigate: (href) => {
      if (!href.toLowerCase().endsWith(".md")) return;
      const rp = resolver(href, dirname(state.current));
      if (rp) openNote(rp);
      else toast("リンク先が見つかりません: " + href);
    },
    getImageURL: async (src) => {
      if (/^[a-z]+:\/\//i.test(src)) return src;
      const rel = normalizePath((dirname(state.current || "") + "/") + src);
      return vault.objectURL(state.root, rel);
    },
    listNotes: () => state.rels.map((rel) => ({ rel, title: titleOf(rel) })),
  });

  boot();

  // デバッグ・テスト用フック（ローカルアプリなので常時公開）
  window.simpleYuriiNote = {
    state, openNote, saveCurrent, syncAndWrite, pickAndOpen, parseAll,
    getEditor: () => editor,
  };
}

document.addEventListener("DOMContentLoaded", init);
