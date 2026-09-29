// vault への読み書き。実行環境で実装を切り替える。
//   - Electron: main プロセスの window.pkm (Node fs + Python sync) を使う
//   - ブラウザ : File System Access API を直接使う
// 同期の正は Python (note_format_v2.py)。Electron では保存時に main が Python を呼ぶ。

import { TITLE_STATE_FILE } from "./sync.js";

const IDB_NAME = "simple-yurii-note-web";
const IDB_STORE = "kv";
const SKIP_DIRS = new Set(["_tmp"]);

const blobURLCache = new Map();

export function isElectron() {
  return typeof window !== "undefined" && !!window.pkm && window.pkm.mode === "electron";
}

export function hasFSA() {
  if (isElectron()) return true;
  return typeof window !== "undefined" && typeof window.showDirectoryPicker === "function";
}

export function rootName() {
  return isElectron() ? window.pkm.rootName : "";
}

// ---- IndexedDB (ブラウザのハンドル保存) ------------------------------------

function idbOpen() {
  return new Promise((resolve, reject) => {
    let req;
    try { req = indexedDB.open(IDB_NAME, 1); } catch (e) { reject(e); return; }
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(IDB_STORE)) req.result.createObjectStore(IDB_STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
    req.onblocked = () => reject(new Error("idb blocked"));
  });
}

function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, rej) => setTimeout(() => rej(new Error("timeout: " + label)), ms)),
  ]);
}

async function idbSet(key, val) {
  try {
    const db = await withTimeout(idbOpen(), 1500, "idb open");
    await withTimeout(new Promise((res, rej) => {
      const tx = db.transaction(IDB_STORE, "readwrite");
      tx.objectStore(IDB_STORE).put(val, key);
      tx.oncomplete = res;
      tx.onerror = () => rej(tx.error);
    }), 1500, "idb put");
  } catch { /* IndexedDB 不可なら毎回選び直す */ }
}

async function idbGet(key) {
  try {
    const db = await withTimeout(idbOpen(), 1500, "idb open");
    return await withTimeout(new Promise((res, rej) => {
      const tx = db.transaction(IDB_STORE, "readonly");
      const r = tx.objectStore(IDB_STORE).get(key);
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    }), 1500, "idb get");
  } catch {
    return undefined;
  }
}

// ---- vault 選択・権限 -------------------------------------------------------

export async function pickVault() {
  if (isElectron()) return null; // パス固定。選択不要
  const handle = await window.showDirectoryPicker({ id: "simple-yurii-note-vault", mode: "readwrite" });
  await idbSet("vault", handle);
  return handle;
}

export async function restoreVault() {
  if (isElectron()) return { handle: null, granted: true };
  const handle = await idbGet("vault");
  if (!handle) return null;
  try {
    const p = await handle.queryPermission({ mode: "readwrite" });
    return { handle, granted: p === "granted" };
  } catch {
    return null;
  }
}

export async function requestPermission(handle) {
  if (isElectron()) return true;
  try {
    let p = await handle.queryPermission({ mode: "readwrite" });
    if (p !== "granted") p = await handle.requestPermission({ mode: "readwrite" });
    return p === "granted";
  } catch {
    return false;
  }
}

// ---- 一覧・読み書き ---------------------------------------------------------

async function* walk(dirHandle, base = "") {
  for await (const [name, handle] of dirHandle.entries()) {
    if (name.startsWith(".") || SKIP_DIRS.has(name)) continue;
    const rel = base ? `${base}/${name}` : name;
    if (handle.kind === "directory") yield* walk(handle, rel);
    else yield { rel, name, handle };
  }
}

export async function readVault(rootHandle) {
  if (isElectron()) {
    const { files, rels, titleState } = await window.pkm.listVault();
    return { files: new Map(files), rels, titleState: titleState || {} };
  }
  const files = new Map();
  const rels = [];
  for await (const ent of walk(rootHandle)) {
    if (!ent.name.toLowerCase().endsWith(".md")) continue;
    try {
      const f = await ent.handle.getFile();
      files.set(ent.rel, await f.text());
      rels.push(ent.rel);
    } catch { /* skip */ }
  }
  rels.sort();
  let titleState = {};
  try {
    const fh = await rootHandle.getFileHandle(TITLE_STATE_FILE);
    titleState = JSON.parse(await (await fh.getFile()).text());
  } catch { /* none */ }
  return { files, rels, titleState };
}

async function getDirHandle(rootHandle, dirPath, create = false) {
  let dir = rootHandle;
  if (!dirPath) return dir;
  for (const seg of dirPath.split("/")) dir = await dir.getDirectoryHandle(seg, { create });
  return dir;
}

export async function readFile(rootHandle, rel) {
  if (isElectron()) return window.pkm.read(rel);
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
  const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1));
  return (await fh.getFile()).text();
}

export async function writeFile(rootHandle, rel, text) {
  if (isElectron()) return window.pkm.write(rel, text);
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "", true);
  const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1), { create: true });
  const w = await fh.createWritable();
  await w.write(text);
  await w.close();
}

export async function deleteFile(rootHandle, rel) {
  if (isElectron()) return window.pkm.remove(rel);
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
  await dir.removeEntry(rel.slice(rel.lastIndexOf("/") + 1));
}

// Electron 専用: 複数書き込み + 削除 + Python sync をまとめて実行
export async function apply(rootHandle, { writes = [], deletes = [] } = {}) {
  if (!isElectron()) throw new Error("apply() is Electron-only");
  return window.pkm.apply({ writes, deletes });
}

export async function objectURL(rootHandle, rel) {
  if (blobURLCache.has(rel)) return blobURLCache.get(rel);
  if (isElectron()) {
    const bytes = await window.pkm.readBinary(rel);
    if (!bytes) return null;
    const url = URL.createObjectURL(new Blob([bytes]));
    blobURLCache.set(rel, url);
    return url;
  }
  try {
    const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
    const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1));
    const url = URL.createObjectURL(await fh.getFile());
    blobURLCache.set(rel, url);
    return url;
  } catch {
    return null;
  }
}

export function invalidateObjectURL(rel) {
  const u = blobURLCache.get(rel);
  if (u) { URL.revokeObjectURL(u); blobURLCache.delete(rel); }
}

export async function hasSwap(rootHandle, rel) {
  if (isElectron()) return window.pkm.hasSwap(rel);
  try {
    const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
    const name = rel.slice(rel.lastIndexOf("/") + 1);
    for await (const [n] of dir.entries()) {
      if (n === `.${name}.swp` || n === `.${name}.swo`) return true;
    }
  } catch { /* ignore */ }
  return false;
}
