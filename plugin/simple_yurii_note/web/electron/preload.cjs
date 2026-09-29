const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("pkm", {
  mode: "electron",
  rootName: process.env.PKM_ROOT_NAME || "",
  listVault: () => ipcRenderer.invoke("pkm:list"),
  read: (rel) => ipcRenderer.invoke("pkm:read", rel),
  write: (rel, text) => ipcRenderer.invoke("pkm:write", rel, text),
  remove: (rel) => ipcRenderer.invoke("pkm:remove", rel),
  readBinary: (rel) => ipcRenderer.invoke("pkm:readBinary", rel),
  hasSwap: (rel) => ipcRenderer.invoke("pkm:hasSwap", rel),
  apply: (payload) => ipcRenderer.invoke("pkm:apply", payload),
});
