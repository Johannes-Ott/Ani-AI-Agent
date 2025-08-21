const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

function createMain(){
  const win = new BrowserWindow({
    width: 1280, height: 860, title: 'ANI – Desktop',
    webPreferences: { contextIsolation: true, preload: path.join(__dirname, 'preload.js') }
  });
  win.loadFile(path.join(__dirname,'renderer','index.html'));
}

// Ensure the main directory structure exists
const projectRoot = path.resolve(process.cwd(), '..');
const cfgDir = path.join(projectRoot, '.config');
const settingsPath = path.join(cfgDir, 'settings.json');
const workflowsDir = path.join(projectRoot, 'workflows');

function ensureConfigDir() {
  if (!fs.existsSync(cfgDir)) fs.mkdirSync(cfgDir, { recursive: true });
}

function loadSettings() {
  try {
    if (fs.existsSync(settingsPath)) {
      const raw = fs.readFileSync(settingsPath, 'utf-8');
      const obj = JSON.parse(raw);
      return {
        n8nBaseUrl: obj.n8nBaseUrl || 'http://localhost:5678',
        n8nApiKey: obj.n8nApiKey || ''
      };
    }
  } catch (e) { console.error('loadSettings error:', e); }
  return { n8nBaseUrl: 'http://localhost:5678', n8nApiKey: '' };
}

function saveSettings(newSettings) {
  ensureConfigDir();
  const toSave = {
    n8nBaseUrl: (newSettings.n8nBaseUrl || 'http://localhost:5678').trim(),
    n8nApiKey: (newSettings.n8nApiKey || '').trim()
  };
  fs.writeFileSync(settingsPath, JSON.stringify(toSave, null, 2), 'utf-8');
  return toSave;
}

async function n8nRequest(method, url, apiKey, body) {
  const headers = { 'Content-Type': 'application/json', 'X-N8N-API-KEY': apiKey };
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  if (!res.ok) {
    const err = new Error(`HTTP ${res.status} ${res.statusText}`);
    err.status = res.status; err.body = json; throw err;
  }
  return json;
}

async function listAllWorkflows(baseUrl, apiKey) {
  const url = `${baseUrl.replace(/\/+$/,'')}/rest/workflows`;
  return n8nRequest('GET', url, apiKey);
}
async function createWorkflow(baseUrl, apiKey, wf) {
  const url = `${baseUrl.replace(/\/+$/,'')}/rest/workflows`;
  return n8nRequest('POST', url, apiKey, wf);
}
async function updateWorkflow(baseUrl, apiKey, id, wf) {
  const url = `${baseUrl.replace(/\/+$/,'')}/rest/workflows/${encodeURIComponent(id)}`;
  return n8nRequest('PATCH', url, apiKey, wf);
}

function readWorkflowFiles() {
  if (!fs.existsSync(workflowsDir)) throw new Error(`Workflows-Ordner fehlt: ${workflowsDir}`);
  const files = fs.readdirSync(workflowsDir).filter(f => f.toLowerCase().endsWith('.json'));
  if (files.length === 0) throw new Error(`Keine .json Workflows in ${workflowsDir}`);
  return files.map(f => ({
    file: f,
    abs: path.join(workflowsDir, f),
    json: JSON.parse(fs.readFileSync(path.join(workflowsDir, f), 'utf-8'))
  }));
}

async function importWorkflows(settings) {
  const baseUrl = (settings.n8nBaseUrl || 'http://localhost:5678').trim();
  const apiKey  = (settings.n8nApiKey || '').trim();
  if (!apiKey) throw new Error('Kein API-Key gesetzt.');

  // Vorhandene Workflows abholen
  const existing = await listAllWorkflows(baseUrl, apiKey);
  const byName = new Map();
  if (Array.isArray(existing)) {
    for (const wf of existing) if (wf && wf.name) byName.set(wf.name, wf.id);
  } else if (existing && Array.isArray(existing.data)) {
    for (const wf of existing.data) if (wf && wf.name) byName.set(wf.name, wf.id);
  }

  const files = readWorkflowFiles();
  const results = [];
  for (const f of files) {
    const wfName = f.json.name || path.basename(f.file, '.json');
    f.json.name = wfName; // sicherstellen
    try {
      if (byName.has(wfName)) {
        const id = byName.get(wfName);
        await updateWorkflow(baseUrl, apiKey, id, f.json);
        results.push({ file: f.file, action: 'updated', id, ok: true });
      } else {
        const created = await createWorkflow(baseUrl, apiKey, f.json);
        const id = created?.id ?? created?.data?.id ?? null;
        results.push({ file: f.file, action: 'created', id, ok: true });
      }
    } catch (e) {
      results.push({ file: f.file, action: 'error', ok: false, message: e.message, detail: e.body });
    }
  }
  return results;
}
// Windows
ipcMain.handle('window.openUnity', async () => {
  const w = new BrowserWindow({
    width: 1280, height: 860, title: 'ANI – Unity Studio',
    webPreferences: { contextIsolation: true, preload: path.join(__dirname,'preload.js') }
  });
  w.loadFile(path.join(__dirname,'renderer','unity.html'));
  return true;
});
ipcMain.handle('env.get', async () => {
  return { n8n: process.env.PORT_N8N || '5678', ollama: process.env.PORT_OLLAMA || '11434' };
});
ipcMain.handle('open.n8n', async (_e, url) => { if (url) await shell.openExternal(url); return true; });
ipcMain.handle('settings:get', async () => loadSettings());
ipcMain.handle('settings:save', async (_e, obj) => saveSettings(obj || {}));
ipcMain.handle('workflows:import', async (_e, obj) => {
  const current = loadSettings();
  const merged = {
    n8nBaseUrl: (obj && obj.n8nBaseUrl) || current.n8nBaseUrl,
    n8nApiKey:  (obj && obj.n8nApiKey)  || current.n8nApiKey
  };
  return importWorkflows(merged);
});


// FS helpers (restrict to user-chosen paths)
ipcMain.handle('fs.openFolderDialog', async () => {
  const res = await dialog.showOpenDialog({ properties:['openDirectory','createDirectory'] });
  return res.canceled ? null : res.filePaths[0];
});
ipcMain.handle('fs.openFileDialog', async () => {
  const res = await dialog.showOpenDialog({ properties:['openFile'] });
  return res.canceled ? null : res.filePaths[0];
});
ipcMain.handle('fs.saveFileDialog', async (_e, suggest) => {
  const res = await dialog.showSaveDialog({ defaultPath: suggest || undefined });
  return res.canceled ? null : res.filePath;
});
ipcMain.handle('fs.listDir', async (_e, dir) => {
  try {
    const items = fs.readdirSync(dir).map(name=>{
      const p = path.join(dir,name);
      const s = fs.statSync(p);
      return { name, path: p, type: s.isDirectory() ? 'dir':'file', size: s.size };
    });
    return { ok:true, items };
  } catch(err) { return { ok:false, error: err.message }; }
});
ipcMain.handle('fs.readFile', async (_e, p) => {
  try { return { ok:true, content: fs.readFileSync(p,'utf8') }; }
  catch(err){ return { ok:false, error: err.message }; }
});
ipcMain.handle('fs.writeFile', async (_e, p, content) => {
  try { fs.writeFileSync(p, content, 'utf8'); return { ok:true }; }
  catch(err){ return { ok:false, error: err.message }; }
});
ipcMain.handle('fs.mkDir', async (_e, p) => {
  try { fs.mkdirSync(p,{recursive:true}); return { ok:true }; }
  catch(err){ return { ok:false, error: err.message }; }
});

// Proc helpers
ipcMain.handle('proc.run', async (_e, cmd, args, cwd) => {
  return new Promise((resolve) => {
    try {
      const child = spawn(cmd, args || [], { cwd: cwd || undefined, shell: process.platform === 'win32' });
      let out = '', err = '';
      child.stdout.on('data', d => out += d.toString());
      child.stderr.on('data', d => err += d.toString());
      child.on('close', code => resolve({ ok: code===0, code, stdout: out, stderr: err }));
    } catch (e) {
      resolve({ ok:false, code:-1, stdout:'', stderr: e.message });
    }
  });
});
ipcMain.handle('unity.openProject', async (_e, unityExe, projectPath) => {
  return new Promise((resolve) => {
    try {
      const args = ['-projectPath', projectPath];
      const child = spawn(unityExe, args, { detached: true, stdio: 'ignore' });
      child.unref();
      resolve({ ok:true });
    } catch (e) {
      resolve({ ok:false, error: e.message });
    }
  });
});

app.whenReady().then(()=>{
  createMain();
  app.on('activate', ()=>{ if (BrowserWindow.getAllWindows().length === 0) createMain(); });
});
app.on('window-all-closed', ()=>{ if (process.platform !== 'darwin') app.quit(); });
