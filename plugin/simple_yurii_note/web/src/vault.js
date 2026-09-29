// File System Access API を使った vault への読み書き。
// サーバーは使わない。ブラウザ (Chromium/Brave) から直接フォルダを触る。

import { TITLE_STATE_FILE } from "./sync.js";

const IDB_NAME = "simple-yurii-note-web";
const IDB_STORE = "kv";
const SKIP_DIRS = new Set(["_tmp"]);

const blobURLCache = new Map();

export function hasFSA() {
  return typeof window !== "undefined" && typeof window.showDirectoryPicker === "function";
}

export async function isSecureEnough() {
  return typeof window !== "undefined" && window.isSecureContext;
}

// ---- IndexedDB (ハンドル保存) ----------------------------------------------

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

// file:// などで IndexedDB が応答しない場合に備えてタイムアウトさせる。
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
  const handle = await window.showDirectoryPicker({ id: "simple-yurii-note-vault", mode: "readwrite" });
  await idbSet("vault", handle);
  return handle;
}

// 保存済みハンドルを返す。権限は付与済みなら granted、未付与なら needsPermission。
export async function restoreVault() {
  const handle = await idbGet("vault");
  if (!handle) return null;
  try {
    const p = await handle.queryPermission({ mode: "readwrite" });
    if (p === "granted") return { handle, granted: true };
    return { handle, granted: false };
  } catch {
    return null;
  }
}

export async function requestPermission(handle) {
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
    if (handle.kind === "directory") {
      yield* walk(handle, rel);
    } else {
      yield { rel, name, handle };
    }
  }
}

// 全 .md を読む -> Map<rel, text>。 titleState も返す。
export async function readVault(rootHandle) {
  const files = new Map();
  const rels = [];
  for await (const ent of walk(rootHandle)) {
    if (!ent.name.toLowerCase().endsWith(".md")) continue;
    try {
      const f = await ent.handle.getFile();
      files.set(ent.rel, await f.text());
      rels.push(ent.rel);
    } catch { /* 読めないファイルは飛ばす */ }
  }
  rels.sort();
  let titleState = {};
  try {
    const fh = await rootHandle.getFileHandle(TITLE_STATE_FILE);
    const f = await fh.getFile();
    titleState = JSON.parse(await f.text());
  } catch { /* 無ければ空 */ }
  return { files, rels, titleState };
}

async function getDirHandle(rootHandle, dirPath, create = false) {
  let dir = rootHandle;
  if (!dirPath) return dir;
  for (const seg of dirPath.split("/")) dir = await dir.getDirectoryHandle(seg, { create });
  return dir;
}

export async function readFile(rootHandle, rel) {
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
  const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1));
  const f = await fh.getFile();
  return f.text();
}

export async function writeFile(rootHandle, rel, text) {
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "", true);
  const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1), { create: true });
  const w = await fh.createWritable();
  await w.write(text);
  await w.close();
}

export async function writeRawFile(rootHandle, rel, data) {
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "", true);
  const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1), { create: true });
  const w = await fh.createWritable();
  await w.write(data);
  await w.close();
}

export async function deleteFile(rootHandle, rel) {
  const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
  await dir.removeEntry(rel.slice(rel.lastIndexOf("/") + 1));
}

// 画像などを blob URL で返す (表示用)。rel は vault 相対パス。
export async function objectURL(rootHandle, rel) {
  if (blobURLCache.has(rel)) return blobURLCache.get(rel);
  try {
    const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
    const fh = await dir.getFileHandle(rel.slice(rel.lastIndexOf("/") + 1));
    const f = await fh.getFile();
    const url = URL.createObjectURL(f);
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

// Vim が同じノートを開いているか (.name.swp の存在チェック)。
export async function hasSwap(rootHandle, rel) {
  try {
    const dir = await getDirHandle(rootHandle, rel.includes("/") ? rel.slice(0, rel.lastIndexOf("/")) : "");
    const name = rel.slice(rel.lastIndexOf("/") + 1);
    for await (const [n] of dir.entries()) {
      if (n === `.${name}.swp` || n === `.${name}.swo`) return true;
    }
  } catch { /* ignore */ }
  return false;
}
