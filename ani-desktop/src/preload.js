const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('ani', {
  // windows
  openUnity: () => ipcRenderer.invoke('window.openUnity'),
  openN8n: (url) => ipcRenderer.invoke('open.n8n', url),
  getEnv: () => ipcRenderer.invoke('env.get'),

  // fs
  listDir: (dir) => ipcRenderer.invoke('fs.listDir', dir),
  readFile: (p) => ipcRenderer.invoke('fs.readFile', p),
  writeFile: (p, content) => ipcRenderer.invoke('fs.writeFile', p, content),
  mkDir: (p) => ipcRenderer.invoke('fs.mkDir', p),
  openFolderDialog: () => ipcRenderer.invoke('fs.openFolderDialog'),
  openFileDialog: () => ipcRenderer.invoke('fs.openFileDialog'),
  saveFileDialog: (suggest) => ipcRenderer.invoke('fs.saveFileDialog', suggest),

  // proc
  runCommand: (cmd, args, cwd) => ipcRenderer.invoke('proc.run', cmd, args, cwd),
  tryOpenUnityProject: (unityExe, projectPath) => ipcRenderer.invoke('unity.openProject', unityExe, projectPath),

  // Settings + Workflow-Import
  getSettings: () => ipcRenderer.invoke('settings:get'),
  saveSettings: (obj) => ipcRenderer.invoke('settings:save', obj),
  importWorkflows: (obj) => ipcRenderer.invoke('workflows:import', obj),
});
