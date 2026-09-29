// Python の simple_sync と JS の runSync の差分テスト。
// 使い方:
//   cp -r <vault> /tmp/A ; cp -r <vault> /tmp/B
//   python3 note_format_v2.py update /tmp/A
//   node sync_diff.mjs /tmp/B          # B に JS sync を適用
//   diff -r /tmp/A /tmp/B              # 空なら一致
import fs from "node:fs";
import path from "node:path";
import { runSync, dumpTitleState, loadTitleState, TITLE_STATE_FILE } from "../src/sync.js";

const root = process.argv[2];
if (!root) {
  console.error("usage: node sync_diff.mjs VAULT_DIR");
  process.exit(2);
}

const SKIP_DIRS = new Set(["_tmp"]);
function iterMd(dir, base = "") {
  const out = [];
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name.startsWith(".")) continue;
    const rel = base ? `${base}/${ent.name}` : ent.name;
    if (ent.isDirectory()) {
      if (SKIP_DIRS.has(ent.name)) continue;
      out.push(...iterMd(path.join(dir, ent.name), rel));
    } else if (ent.name.endsWith(".md")) {
      out.push(rel);
    }
  }
  return out;
}

const files = new Map();
for (const rel of iterMd(root).sort()) {
  try {
    files.set(rel, fs.readFileSync(path.join(root, rel), "utf8"));
  } catch (e) {
    console.error("skip (decode):", rel, e.message);
  }
}

let prevTitleState = {};
const tsPath = path.join(root, TITLE_STATE_FILE);
if (fs.existsSync(tsPath)) {
  try { prevTitleState = loadTitleState(fs.readFileSync(tsPath, "utf8")); } catch { /* ignore */ }
}

function apply(filesMap, prev) {
  const res = runSync(filesMap, prev);
  for (const [rel, text] of res.changed) filesMap.set(rel, text);
  return res;
}

const res1 = apply(files, prevTitleState);
// 冪等: 2 回目は 0 changes のはず
const res2 = runSync(files, res1.titleState);

if (res2.changed.size !== 0) {
  console.error(`NOT IDEMPOTENT: 2nd run changed ${res2.changed.size} files`);
  process.exit(1);
}

// 書き出す (Python 側の出力と diff を取るため)
for (const [rel, text] of res1.changed) {
  fs.writeFileSync(path.join(root, rel), text, "utf8");
}
if (res1.titleStateChanged) {
  fs.writeFileSync(tsPath, dumpTitleState(res1.titleState), "utf8");
}

console.log(`ok: changed ${res1.changed.size} file(s), idempotent, titleStateChanged=${res1.titleStateChanged}`);
