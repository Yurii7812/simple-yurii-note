// simple_yurii_note デスクトップアプリ (Electron)。
// vault のパスは固定 (既定 ~/files/yurii-note)。フォルダ選択は無い。
// 同期の正は Python: 保存時に note_format_v2.py を回す。
const { app, BrowserWindow, ipcMain, Menu } = require("electron");
const path = require("path");
const os = require("os");
const fsapi = require("./fsapi.cjs");

const ROOT = path.resolve(process.env.PKM_ROOT || path.join(os.homedir(), "files", "yurii-note"));
process.env.PKM_ROOT_NAME = path.basename(ROOT);

function createWindow() {
  const win = new BrowserWindow({
    width: 1120,
    height: 800,
    title: "simple_yurii_note — " + ROOT,
    backgroundColor: "#ffffff",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });
  Menu.setApplicationMenu(null);
  const logs = [];
  win.webContents.on("console-message", (...args) => {
    const d = args[1] && typeof args[1] === "object" ? args[1] : null;
    logs.push(d ? `${d.level}:${d.message}` : `${args[1]}:${args[2]}`);
  });
  win.webContents.on("preload-error", (_e, p, err) => logs.push("preload-error " + p + " " + err));
  win.loadFile(path.join(__dirname, "..", "index.html"));
  if (process.env.PKM_TEST_OUT) {
    win.webContents.on("did-finish-load", () => {
      setTimeout(async () => {
        let diag = {};
        try {
          diag = await win.webContents.executeJavaScript(`(() => ({
            hasPkm: !!window.pkm,
            pkmMode: window.pkm && window.pkm.mode,
            hasFSA: typeof window.showDirectoryPicker,
            overlayHidden: document.getElementById('overlay') && document.getElementById('overlay').hidden,
            overlayOpenDisplay: document.getElementById('overlay-open') && getComputedStyle(document.getElementById('overlay-open')).display,
            noteItems: document.querySelectorAll('.note-item').length,
            hasHook: !!window.simpleYuriiNote
          }))()`);
        } catch (e) { diag.err = String(e); }
        diag.logs = logs.slice(-30);
        try { diag.mainRels = (await fsapi.listVault(ROOT)).rels; } catch (e) { diag.mainErr = String(e); }
        require("fs").writeFileSync(process.env.PKM_TEST_OUT, JSON.stringify(diag, null, 2));
        app.quit();
      }, 3000);
    });
  }
}

ipcMain.handle("pkm:list", () => fsapi.listVault(ROOT));
ipcMain.handle("pkm:read", (_e, rel) => fsapi.readNote(ROOT, rel));
ipcMain.handle("pkm:write", (_e, rel, text) => fsapi.writeNote(ROOT, rel, text));
ipcMain.handle("pkm:remove", (_e, rel) => fsapi.deleteNote(ROOT, rel));
ipcMain.handle("pkm:readBinary", (_e, rel) => fsapi.readBinary(ROOT, rel));
ipcMain.handle("pkm:hasSwap", (_e, rel) => fsapi.hasSwap(ROOT, rel));
ipcMain.handle("pkm:apply", (_e, payload) => fsapi.apply(ROOT, payload));

app.whenReady().then(createWindow);
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
