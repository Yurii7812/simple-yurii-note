// Electron main から使う vault 操作 (Node fs) と Python sync。
// electron に依存しない純関数なので単体テストできる (test/fsapi_test.mjs)。
const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const { execFile } = require("child_process");

const SKIP_DIRS = new Set(["_tmp"]);
const TITLE_STATE_FILE = ".pkm_title_state_v2.json";

function safeJoin(root, rel) {
  const p = path.resolve(root, rel);
  const r = path.resolve(root);
  if (p !== r && !p.startsWith(r + path.sep)) throw new Error("path escapes vault: " + rel);
  return p;
}

async function listMd(root, base = "") {
  const out = [];
  const dir = path.join(root, base);
  let ents;
  try { ents = await fsp.readdir(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of ents) {
    if (e.name.startsWith(".") || SKIP_DIRS.has(e.name)) continue;
    const rel = base ? `${base}/${e.name}` : e.name;
    if (e.isDirectory()) out.push(...await listMd(root, rel));
    else if (e.name.toLowerCase().endsWith(".md")) out.push(rel);
  }
  return out;
}

async function readNote(root, rel) {
  return fsp.readFile(safeJoin(root, rel), "utf8");
}

async function readBinary(root, rel) {
  try { return await fsp.readFile(safeJoin(root, rel)); } catch { return null; }
}

async function writeNote(root, rel, text) {
  const p = safeJoin(root, rel);
  await fsp.mkdir(path.dirname(p), { recursive: true });
  await fsp.writeFile(p, text, "utf8");
}

async function deleteNote(root, rel) {
  await fsp.rm(safeJoin(root, rel), { force: true });
}

async function readTitleState(root) {
  try { return JSON.parse(await fsp.readFile(path.join(root, TITLE_STATE_FILE), "utf8")); }
  catch { return {}; }
}

async function listVault(root) {
  const rels = (await listMd(root)).sort();
  const files = [];
  for (const rel of rels) {
    try { files.push([rel, await readNote(root, rel)]); } catch { /* skip */ }
  }
  return { files, rels: files.map(([r]) => r).sort(), titleState: await readTitleState(root) };
}

async function hasSwap(root, rel) {
  const p = safeJoin(root, rel);
  return fs.existsSync(p + ".swp")
    || fs.existsSync(path.join(path.dirname(p), "." + path.basename(p) + ".swp"))
    || fs.existsSync(path.join(path.dirname(p), "." + path.basename(p) + ".swo"));
}

function pythonPath() {
  if (process.env.PKM_PYTHON) return process.env.PKM_PYTHON;
  return path.resolve(__dirname, "..", "..", "python", "note_format_v2.py");
}

// Python の simple_sync を回す (正は Python)。update は全体同期。
function runSync(root) {
  return new Promise((resolve, reject) => {
    const py = pythonPath();
    execFile("python3", [py, "update", root], { timeout: 120000 }, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      resolve(stdout.trim());
    });
  });
}

// 書き込み・削除 -> Python sync -> 一覧メタを返す
async function apply(root, { writes = [], deletes = [] } = {}) {
  for (const d of deletes) await deleteNote(root, d);
  for (const w of writes) await writeNote(root, w.rel, w.text);
  await runSync(root);
  const rels = (await listMd(root)).sort();
  return { rels, titleState: await readTitleState(root) };
}

module.exports = {
  safeJoin, listMd, listVault, readNote, readBinary, writeNote, deleteNote,
  readTitleState, hasSwap, runSync, apply, pythonPath, TITLE_STATE_FILE,
};
