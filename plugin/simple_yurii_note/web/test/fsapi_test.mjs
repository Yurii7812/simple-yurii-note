// fsapi.cjs (Electron main の vault 操作 + Python sync) の単体テスト。
//   node test/fsapi_test.mjs
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fsapi = require(path.join(__dirname, "..", "electron", "fsapi.cjs"));

const NOTES = {
  "index.md": "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n[g](g.md)\n[a](a.md)\n",
  "g.md": "---\ntime: 2026-01-01 00:00:01\ntitle: G\nattribute: group\n---\n\n# G\n\n[b](b.md)\n### Parent\n### BackLink\n",
  "a.md": "---\ntime: 2026-01-01 00:00:02\ntitle: a\n---\n\n# a\n\nsee [gone](999999999999.md) here\n### Parent\n### BackLink\n",
  "b.md": "---\ntime: 2026-01-01 00:00:03\ntitle: b\n---\n\n# b\n\n### Parent\n### BackLink\n",
};

async function snapshot(root) {
  const out = {};
  for (const rel of await fsapi.listMd(root)) out[rel] = fs.readFileSync(path.join(root, rel), "utf8");
  return out;
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), "fsapi-"));
let failures = 0;
function check(name, ok, extra = "") {
  if (!ok) { failures++; console.error("FAIL:", name, extra); }
  else console.log("ok:", name);
}

try {
  for (const [rel, text] of Object.entries(NOTES)) fs.writeFileSync(path.join(root, rel), text);

  // listVault
  const lv = await fsapi.listVault(root);
  check("listVault count", lv.rels.length === 4, String(lv.rels.length));
  check("titleState empty", Object.keys(lv.titleState).length === 0);

  // safeJoin escapes
  let escaped = false;
  try { fsapi.safeJoin(root, "../outside.md"); } catch { escaped = true; }
  check("safeJoin rejects escape", escaped);

  // plain write/read
  await fsapi.writeNote(root, "b.md", NOTES["b.md"] + "\n");
  check("write/read", (await fsapi.readNote(root, "b.md")).endsWith("\n"));

  // apply: 編集（a にリンク追加）+ Python sync
  await fsapi.apply(root, { writes: [{ rel: "a.md", text: NOTES["a.md"].replace("### Parent", "[b](b.md)\n### Parent") }] });
  const s1 = await snapshot(root);
  check("sync pruned inline dangling (kept text)", s1["a.md"].includes("see gone here"), s1["a.md"]);
  check("sync linked a->b (b has backlink a)", s1["b.md"].includes("[a](a.md)"), s1["b.md"]);
  check("sync group g became parent of b", s1["b.md"].includes("[G](g.md)"), s1["b.md"]);

  // idempotency: 2 回目の apply で内容が変わらない
  const before = await snapshot(root);
  await fsapi.apply(root, {});
  const after = await snapshot(root);
  check("idempotent", JSON.stringify(before) === JSON.stringify(after));

  // delete
  await fsapi.apply(root, { deletes: ["b.md"] });
  check("delete removes file", !fs.existsSync(path.join(root, "b.md")));
  const afterDelete = await snapshot(root);
  check("delete prunes refs", !afterDelete["a.md"].includes("(b.md)"), afterDelete["a.md"]);

  // hasSwap
  fs.writeFileSync(path.join(root, ".g.md.swp"), "");
  check("hasSwap detects", await fsapi.hasSwap(root, "g.md"));
  fs.rmSync(path.join(root, ".g.md.swp"));
  check("hasSwap false", !(await fsapi.hasSwap(root, "g.md")));
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

if (failures) { console.error(`\n${failures} failure(s)`); process.exit(1); }
console.log("\nfsapi test: OK");
