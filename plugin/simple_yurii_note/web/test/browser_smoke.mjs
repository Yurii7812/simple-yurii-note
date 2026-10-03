// ブラウザ (Chromium) で app を実際に動かす E2E スモークテスト。
// showDirectoryPicker を OPFS に差し替え、シードした vault を JS sync し、
// 同じ入力に Python sync を掛けた結果と全ファイル一致するか比較する。
//
//   node test/browser_smoke.mjs
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(__dirname, "..");
const pyScript = path.resolve(__dirname, "../../python/note_format_v2.py");

const NOTES = {
  "index.md": `---
time: 2026-01-01 00:00:00
title: Index
attribute: group
---

# Index

[日記](g.md)
[a](a.md)
`,
  "g.md": `---
time: 2026-01-01 00:00:01
title: 日記
attribute: group
---

# 日記

[b](b.md)
### Parent
[Index](index.md)
### BackLink
`,
  "a.md": `---
time: 2026-01-01 00:00:02
title: a
---

# a

[b](b.md)
see [gone](999999999999.md) here
### Parent
[Index](index.md)
### BackLink
`,
  "b.md": `---
time: 2026-01-01 00:00:03
title: タイトル未設定
---

# b

### Parent
[a](a.md)
### Related
[r](r.md)
### BackLink
`,
  "r.md": `---
time: 2026-01-01 00:00:04
title: 関連ノート
---

# 関連ノート

### Parent
### Related
[b](b.md)
### BackLink
`,
};

// 1) Python で同期した期待結果を作る
const pyDir = fs.mkdtempSync(path.join(os.tmpdir(), "syn-smoke-py-"));
for (const [rel, text] of Object.entries(NOTES)) fs.writeFileSync(path.join(pyDir, rel), text);
execFileSync("python3", [pyScript, "update", pyDir], { stdio: "ignore" });
const expected = {};
for (const f of fs.readdirSync(pyDir)) {
  if (f.endsWith(".md")) expected[f] = fs.readFileSync(path.join(pyDir, f), "utf8");
}

// 2) ブラウザテストページを生成 (index.html の骨組み + テストスクリプト)
const chrome = findChrome();
const skeleton = fs.readFileSync(path.join(web, "index.html"), "utf8");
const testScript = `<script>
window.__errs=[];
window.onerror=function(m,s,l,c,e){window.__errs.push('onerror: '+m+' @'+(e&&e.stack||''));};
window.addEventListener('unhandledrejection',function(e){window.__errs.push('reject: '+(e.reason&&e.reason.stack||e.reason));});
const NOTES = ${JSON.stringify(NOTES)};
const EXPECT = ${JSON.stringify(expected)};
function setRes(o){var d=document.getElementById('test-result');if(d)d.textContent='RESULT='+JSON.stringify(o);}
function step(s){var d=document.getElementById('test-result');if(d)d.textContent='STEP='+s;}
async function sleep(ms){return new Promise(r=>setTimeout(r,ms));}
function makeFS(files){
  const root={kind:'directory',name:'root',children:new Map()};
  const fileH=(name,f)=>({kind:'file',name,getFile:async()=>({name,text:async()=>f.content}),createWritable:async()=>({write:async(t)=>{f.content=String(t);},close:async()=>{}})});
  const dirH=(node)=>({
    kind:'directory',name:node.name,
    async *entries(){for(const [n,c] of node.children){yield [n, c.kind==='directory'?dirH(c):fileH(n,c)];}},
    async getDirectoryHandle(n,o={}){let c=node.children.get(n);if(!c){if(!o.create)throw new Error('no dir '+n);c={kind:'directory',name:n,children:new Map()};node.children.set(n,c);}return dirH(c);},
    async getFileHandle(n,o={}){let c=node.children.get(n);if(!c){if(!o.create)throw new Error('no file '+n);c={kind:'file',name:n,content:''};node.children.set(n,c);}return fileH(n,c);},
    async removeEntry(n){node.children.delete(n);},
    async queryPermission(){return 'granted';},
    async requestPermission(){return 'granted';},
  });
  for(const [rel,text] of Object.entries(files)){const parts=rel.split('/');let d=root;for(let i=0;i<parts.length-1;i++){let c=d.children.get(parts[i]);if(!c){c={kind:'directory',name:parts[i],children:new Map()};d.children.set(parts[i],c);}d=c;}d.children.set(parts[parts.length-1],{kind:'file',name:parts[parts.length-1],content:text});}
  return dirH(root);
}
async function readAll(dir, base=''){const out={};for await(const [name,h] of dir.entries()){const rel=base?base+'/'+name:name;if(h.kind==='directory'){Object.assign(out,await readAll(h,rel));}else if(name.endsWith('.md')){const f=await h.getFile();out[rel]=await f.text();}}return out;}
async function main(){
  try{
    step('fs');
    const root = makeFS(NOTES);
    window.showDirectoryPicker = async ()=>root;
    step('boot');
    for(let i=0;i<100 && !window.simpleYuriiNote;i++) await sleep(30);
    const app = window.simpleYuriiNote;
    if(!app) throw new Error('app hook missing');
    await app.pickAndOpen();
    await sleep(300);
    step('opened');
    if(app.state.rels.length !== Object.keys(NOTES).length) throw new Error('note count '+app.state.rels.length);
    app.openNote('a.md');
    await sleep(100);
    const docA = app.getEditor().getDoc();
    const ui = {
      sidebarItems: document.querySelectorAll('.note-item').length,
      relParent: document.getElementById('rel-parent').textContent,
      relBack: document.getElementById('rel-back').textContent,
      docHasLink: docA.includes('[b](') || docA.includes('[タイトル未設定]('),
    };
    step('saving');
    await app.saveCurrent();
    await sleep(200);
    const after = await readAll(root);
    const diff = {};
    for(const k of new Set([...Object.keys(after),...Object.keys(EXPECT)])){
      if((after[k]||'') !== (EXPECT[k]||'')) diff[k] = {got:(after[k]||'').slice(0,200), want:(EXPECT[k]||'').slice(0,200)};
    }
    step('autosave');
    // 本文を変えて待つだけ（明示保存しない）で自動保存されるか
    const beforeAuto = (await readAll(root))['a.md'] || '';
    app.getEditor().setDoc(app.getEditor().getDoc().trimEnd() + '\\n[日記](g.md)');
    const dirtyAfterSet = app.state.dirty;
    const docAfterSet = app.getEditor().getDoc();
    await sleep(1900);
    const afterAuto = (await readAll(root))['a.md'] || '';
    const autosaveOk = afterAuto.includes('(g.md)') && afterAuto !== beforeAuto && app.state.dirty === false;
    const autoDbg = {dirty: app.state.dirty, dirtyAfterSet, docTail: docAfterSet.slice(-40), has: afterAuto.includes('(g.md)'), changed: afterAuto !== beforeAuto, afterTail: afterAuto.slice(-120)};
    setRes({errs:window.__errs, ui, diffKeys:Object.keys(diff), diff, autosaveOk, autoDbg});
  }catch(e){ setRes({errs:window.__errs, fatal:String(e&&e.stack||e)}); }
}
main();
</script>`;
const page = skeleton
  .replace('<div id="toast" class="toast"></div>', '<div id="toast" class="toast"></div>\n<div id="test-result">RUNNING</div>')
  .replace('<script src="bundle.js"></script>', testScript + '<script src="bundle.js"></script>');
const pagePath = path.join(web, "__smoke.html");
fs.writeFileSync(pagePath, page);
try {
  const dom = execFileSync(chrome, [
    "--headless=new", "--no-sandbox", "--disable-gpu", "--allow-file-access-from-files",
    "--virtual-time-budget=8000", "--dump-dom", `file://${pagePath}`,
  ], { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });

  const m = /RESULT=(\{.*?\})<\/div>/s.exec(dom);
  if (!m) {
    fs.writeFileSync("/tmp/opencode/smoke_dom.html", dom);
    throw new Error("no RESULT in DOM (wrote /tmp/opencode/smoke_dom.html)");
  }
  const result = JSON.parse(m[1]);
  console.log(JSON.stringify(result, null, 2));
  if (result.fatal) process.exit(1);
  if (result.errs?.length) { console.error("JS errors"); process.exit(1); }
  if (result.diffKeys?.length) { console.error("file mismatch vs Python"); process.exit(1); }
  if (!result.ui || result.ui.sidebarItems < 4) { console.error("sidebar not rendered"); process.exit(1); }
  console.log("browser smoke: OK (JS sync == Python sync, UI rendered)");
} finally {
  fs.rmSync(pagePath, { force: true });
  fs.rmSync(pyDir, { recursive: true, force: true });
}

function findChrome() {
  const candidates = [];
  const base = path.join(os.homedir(), ".cache/ms-playwright");
  if (fs.existsSync(base)) {
    for (const d of fs.readdirSync(base)) {
      if (d.startsWith("chromium-")) candidates.push(path.join(base, d, "chrome-linux64/chrome"));
    }
  }
  candidates.push("chromium", "chromium-browser", "google-chrome", "/usr/bin/brave-browser");
  for (const c of candidates) {
    if (c.includes("/")) { if (fs.existsSync(c)) return c; }
    else { try { return execFileSync("which", [c], { encoding: "utf8" }).trim(); } catch { /* next */ } }
  }
  throw new Error("chromium not found");
}
