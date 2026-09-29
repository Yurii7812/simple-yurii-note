// simple_sync の JS 移植。
// 正は plugin/simple_yurii_note/python/note_format_v2.py の simple_sync()。
// 挙動を変えたら web/test/sync_diff.mjs (Python との差分テスト) を必ず回す。
//
// 表記:
//   - ノートは vault ルートからの相対 posix パス (例 "260909105059.md") で扱う。
//   - 同期は全ノート分のテキストを一括で受け取り、変更のあったノートの
//     新テキストだけを返す (書き込みは vault.js 側)。

export const UP_MARK = "### Parent";
export const DOWN_MARK = "### BackLink";
export const TITLE_STATE_FILE = ".pkm_title_state_v2.json";

const INLINE_LINK_RE = /\[([^\]]*)\]\(([^)]+)\)/;
const LINK_LINE_RE = /^\s*(\[[^\]]*\]\([^)]+\))\s*(?:—\s*\S+)?\s*$/;
const GROUP_ATTR_RE = /^\s*(?:attribute|属性)\s*:\s*(?:group|グループ|小グループ|カテゴリー|キーワード)\s*$/;

const ATTR_ALIASES = {
  "グループ": "group",
  "カテゴリー": "group",
  "キーワード": "group",
  "小グループ": "group",
};

// ---- path helpers -----------------------------------------------------------

export function normalizePath(p) {
  const parts = [];
  for (const seg of String(p).split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") parts.pop();
    else parts.push(seg);
  }
  return parts.join("/");
}

export function dirname(p) {
  const i = p.lastIndexOf("/");
  return i < 0 ? "" : p.slice(0, i);
}

export function basename(p) {
  const i = p.lastIndexOf("/");
  return i < 0 ? p : p.slice(i + 1);
}

export function stem(p) {
  const b = basename(p);
  const i = b.lastIndexOf(".");
  return i > 0 ? b.slice(0, i) : b;
}

// Python os.path.relpath(target, from_dir) 相当 (vault 相対)。
export function relPath(fromDir, target) {
  const f = fromDir ? fromDir.split("/") : [];
  const t = target.split("/");
  let i = 0;
  while (i < f.length && i < t.length && f[i] === t[i]) i++;
  const out = [];
  for (let k = 0; k < f.length - i; k++) out.push("..");
  for (let k = i; k < t.length; k++) out.push(t[k]);
  return out.join("/");
}

// ---- regex helpers ----------------------------------------------------------

function* matchAll(re, str) {
  const flags = re.flags.includes("g") ? re.flags : re.flags + "g";
  const rx = new RegExp(re.source, flags);
  let m;
  while ((m = rx.exec(str)) !== null) {
    yield m;
    if (m.index === rx.lastIndex) rx.lastIndex++;
  }
}

function replaceInlineLinks(line, cb) {
  return line.replace(
    new RegExp(INLINE_LINK_RE.source, "g"),
    (...args) => {
      // args: [full, disp, target, offset, string]
      return cb(args[0], args[1], args[2]);
    },
  );
}

function linkTarget(line) {
  const m = INLINE_LINK_RE.exec(line);
  return m ? m[2].split("#")[0].trim() : "";
}

// ---- parse ------------------------------------------------------------------

function splitFrontMatter(lines) {
  if (lines.length && lines[0].trim() === "---") {
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") return [lines.slice(0, i + 1), lines.slice(i + 1)];
    }
  }
  return [[], lines.slice()];
}

function fmTitle(fm) {
  for (const ln of fm) {
    const m = /^\s*title\s*:\s*(.+?)\s*$/.exec(ln);
    if (m) return m[1];
  }
  return "";
}

function fmAttr(fm) {
  for (const ln of fm) {
    const m = /^\s*(?:attribute|属性)\s*:\s*(.+?)\s*$/.exec(ln);
    if (m) {
      const v = m[1].trim().replace(/^["']|["']$/g, "");
      return ATTR_ALIASES[v] !== undefined ? ATTR_ALIASES[v] : v;
    }
  }
  return "";
}

export function parseNote(text, rel) {
  const [fm, rest] = splitFrontMatter(text.split("\n"));
  const title = fmTitle(fm) || stem(rel);
  const body = [];
  const parent = [];
  const back = [];
  let cur = "body";
  for (const ln of rest) {
    const s = ln.trim();
    if (s === UP_MARK) { cur = "parent"; continue; }
    if (s === DOWN_MARK) { cur = "back"; continue; }
    (cur === "body" ? body : cur === "parent" ? parent : back).push(ln);
  }
  return { fm, title, attr: fmAttr(fm), body, parent, back };
}

function linksFrom(lines) {
  const out = [];
  for (const ln of lines) {
    for (const m of matchAll(INLINE_LINK_RE, ln)) {
      const tg = m[2].split("#")[0].trim();
      if (tg.toLowerCase().endsWith(".md")) out.push([m[1], tg]);
    }
  }
  return out;
}

// ---- resolver ---------------------------------------------------------------

function makeResolver(notes) {
  return (target, baseDir) => {
    const t = String(target).split("#")[0].trim();
    if (!t) return null;
    let cand;
    if (t.startsWith("/")) cand = normalizePath(t.slice(1));
    else cand = normalizePath((baseDir ? baseDir + "/" : "") + t);
    return notes.has(cand) ? cand : null;
  };
}

// ---- per-section transforms -------------------------------------------------

function updateBodyLinkNames(body, rel, resolver, titles, prevTitles) {
  const dir = dirname(rel);
  return body.map((ln) =>
    replaceInlineLinks(ln, (full, disp, tg) => {
      const base = tg.split("#")[0].trim();
      if (!base.toLowerCase().endsWith(".md")) return full;
      const rp = resolver(base, dir);
      if (rp === null || !titles.has(rp)) return full;
      const now = titles.get(rp);
      if (disp === now || disp === prevTitles[rp] || disp === stem(base)) {
        return `[${now}](${tg})`;
      }
      return full;
    }),
  );
}

function preserveParent(existing, rel, resolver, titles) {
  const dir = dirname(rel);
  return existing.map((ln) => {
    const m = INLINE_LINK_RE.exec(ln);
    if (m) {
      const tgFull = m[2];
      const tg = tgFull.split("#")[0].trim();
      const rp = resolver(tg, dir);
      if (rp !== null && titles.has(rp)) return `[${titles.get(rp)}](${tgFull})`;
    }
    return ln;
  });
}

function pruneDangling(lines, rel, resolver) {
  const dir = dirname(rel);
  const out = [];
  for (const ln of lines) {
    if (LINK_LINE_RE.test(ln)) {
      const tg = linkTarget(ln);
      if (tg.toLowerCase().endsWith(".md") && resolver(tg, dir) === null) continue;
      out.push(ln);
      continue;
    }
    out.push(
      replaceInlineLinks(ln, (full, disp, tg) => {
        const base = tg.split("#")[0].trim();
        if (base.toLowerCase().endsWith(".md") && resolver(base, dir) === null) return disp;
        return full;
      }),
    );
  }
  return out;
}

function simpleRender(rel, n, parentLines, back, titles) {
  let lines = n.fm.length ? n.fm.slice() : ["---", "title: " + n.title, "---"];
  lines = lines.concat(n.body);
  if (basename(rel) !== "index.md") {
    const last = lines[lines.length - 1];
    if (lines.length && last.trim() !== "" && !LINK_LINE_RE.test(last)) lines.push("");
    lines.push(UP_MARK);
    lines = lines.concat(parentLines);
    lines.push(DOWN_MARK);
    for (const t of back) lines.push(`[${titles.get(t)}](${relPath(dirname(rel), t)})`);
  }
  while (lines.length && lines[lines.length - 1].trim() === "") lines.pop();
  return lines.join("\n") + "\n";
}

// ---- main -------------------------------------------------------------------

// files: Map<relPath, text>  (全 .md)
// prevTitleState: object (前回 sync のタイトル記録)
// 戻り値: { changed: Map<rel, newText>, titleState, titleStateChanged, notes }
export function runSync(files, prevTitleState) {
  const rels = [...files.keys()].sort();
  const notes = new Map();
  for (const rel of rels) notes.set(rel, parseNote(files.get(rel), rel));

  const titles = new Map();
  for (const rel of rels) titles.set(rel, notes.get(rel).title);

  const prevState = prevTitleState || {};
  const prevTitles = {};
  for (const rel of rels) {
    if (Object.prototype.hasOwnProperty.call(prevState, rel)) prevTitles[rel] = prevState[rel];
  }

  const resolver = makeResolver(notes);
  const res = (tg, base) => resolver(tg, base);

  // incoming は「元の本文」から。表示名更新・掃除の前に固定する (Python と同順)。
  const bodyT = new Map();
  for (const rel of rels) {
    const ts = [];
    for (const [, tg] of linksFrom(notes.get(rel).body)) {
      const rp = res(tg, dirname(rel));
      if (rp !== null && rp !== rel) ts.push(rp);
    }
    bodyT.set(rel, ts);
  }
  const incoming = new Map();
  for (const rel of rels) incoming.set(rel, []);
  for (const rel of rels) {
    const seen = new Set();
    for (const t of bodyT.get(rel)) {
      if (seen.has(t)) continue;
      seen.add(t);
      incoming.get(t).push(rel);
    }
  }

  const indexOf = new Map();
  for (const rel of rels) {
    if (basename(rel) !== "index.md") continue;
    for (const t of bodyT.get(rel)) {
      if (t !== rel) indexOf.set(t, rel);
    }
  }

  const groupSet = new Set();
  for (const rel of rels) {
    const n = notes.get(rel);
    if (basename(rel) === "index.md") { groupSet.add(rel); continue; }
    if (n.fm.some((ln) => GROUP_ATTR_RE.test(ln))) groupSet.add(rel);
  }

  const changed = new Map();
  for (const rel of rels) {
    const n = notes.get(rel);

    n.body = updateBodyLinkNames(n.body, rel, res, titles, prevTitles);
    n.body = pruneDangling(n.body, rel, res);

    let parentLines = preserveParent(n.parent, rel, res, titles);
    parentLines = pruneDangling(parentLines, rel, res);

    const parentSet = new Set();
    for (const [, tg] of linksFrom(n.parent)) {
      const rp = res(tg, dirname(rel));
      if (rp !== null) parentSet.add(rp);
    }

    // index.md との対応は sync が管理する。
    const idx = indexOf.get(rel);
    if (idx !== undefined && !parentSet.has(idx)) {
      parentSet.add(idx);
      parentLines.unshift(`[${titles.get(idx)}](${relPath(dirname(rel), idx)})`);
    } else if (idx === undefined) {
      const drop = new Set();
      const keep = [];
      for (const ln of parentLines) {
        const tgt = linkTarget(ln);
        const rp = tgt ? res(tgt, dirname(rel)) : null;
        if (rp !== null && basename(rp) === "index.md") drop.add(rp);
        else keep.push(ln);
      }
      if (drop.size) {
        parentLines = keep;
        for (const d of drop) parentSet.delete(d);
      }
    }

    const outSet = new Set(bodyT.get(rel));
    const autoParent = [];
    const desired = [];
    const dseen = new Set();
    for (const s of incoming.get(rel)) {
      if (s === rel || dseen.has(s) || outSet.has(s)) continue;
      dseen.add(s);
      if (groupSet.has(s)) { autoParent.push(s); continue; }
      if (parentSet.has(s)) continue;
      desired.push(s);
    }
    for (const s of autoParent) {
      if (parentSet.has(s)) continue;
      parentSet.add(s);
      parentLines.push(`[${titles.get(s)}](${relPath(dirname(rel), s)})`);
    }

    const existingBack = [];
    for (const [, tg] of linksFrom(n.back)) {
      const rp = res(tg, dirname(rel));
      if (rp !== null && !existingBack.includes(rp)) existingBack.push(rp);
    }
    const dset = new Set(desired);
    const back = existingBack.filter((t) => dset.has(t));
    const backSet = new Set(back);
    for (const t of desired) if (!backSet.has(t)) back.push(t);

    const newText = simpleRender(rel, n, parentLines, back, titles);
    if (newText !== files.get(rel)) changed.set(rel, newText);
  }

  const titleState = {};
  for (const rel of rels) titleState[rel] = titles.get(rel);
  const titleStateChanged = !shallowEqual(prevState, titleState);

  return { changed, titleState, titleStateChanged, notes, rels };
}

function shallowEqual(a, b) {
  const ak = Object.keys(a);
  const bk = Object.keys(b);
  if (ak.length !== bk.length) return false;
  for (const k of ak) if (a[k] !== b[k]) return false;
  return true;
}

// Python json.dumps(dict, ensure_ascii=False, indent=0, sort_keys=True) と一致させる。
export function dumpTitleState(obj) {
  const keys = Object.keys(obj).sort();
  if (keys.length === 0) return "{}";
  const items = keys.map((k) => `${JSON.stringify(k)}: ${JSON.stringify(obj[k])}`);
  return "{\n" + items.join(",\n") + "\n}";
}

export function loadTitleState(text) {
  try {
    const data = JSON.parse(text);
    const out = {};
    for (const [k, v] of Object.entries(data)) {
      if (typeof k === "string" && typeof v === "string") out[k] = v;
    }
    return out;
  } catch {
    return {};
  }
}

// 関係グラフ用: rel -> {title, attr, parent:[rel], back:[rel], children:[rel]}
export function relationsOf(notes, rels, resolver) {
  const info = new Map();
  for (const rel of rels) {
    const n = notes.get(rel);
    const parseLinks = (lines) => linksFrom(lines)
      .map(([, tg]) => resolver(tg, dirname(rel)))
      .filter((x) => x !== null && x !== rel);
    info.set(rel, { rel, title: n.title, attr: n.attr, body: parseLinks(n.body), parent: parseLinks(n.parent), back: parseLinks(n.back) });
  }
  return info;
}
