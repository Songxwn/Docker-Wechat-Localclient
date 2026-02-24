const { app, BrowserWindow, shell, Tray, Menu, ipcMain } = require('electron');
const path = require('path');
const Store = require('electron-store');
const { randomUUID } = require('crypto');

const store = new Store();
const appVersion = require('./package.json').version;

const DEFAULT_URL = 'https://localhost:3001';
const CONFIG_KEYS = {
  connections: 'connections',
  defaultConnectionId: 'defaultConnectionId',
};

const DEFAULT_CONNECTION = {
  name: '本地微信',
  url: DEFAULT_URL,
  ignoreSsl: true,
  openExternal: false,
  username: '',
  password: '',
};

function getConnections() {
  const list = store.get(CONFIG_KEYS.connections, []);
  if (list.length === 0) {
    const first = { id: randomUUID(), ...DEFAULT_CONNECTION };
    store.set(CONFIG_KEYS.connections, [first]);
    store.set(CONFIG_KEYS.defaultConnectionId, first.id);
    return [first];
  }
  return list;
}

function getDefaultConnectionId() {
  return store.get(CONFIG_KEYS.defaultConnectionId, null) || (getConnections()[0]?.id ?? null);
}

let mainWindow = null;
let tray = null;

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    title: 'WeChat Selkies - 本地远程客户端',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      webSecurity: true,
    },
    show: false,
  });
  const iconPath = path.join(__dirname, 'assets', 'icon.png');
  try {
    if (require('fs').existsSync(iconPath)) win.setIcon(iconPath);
  } catch (_) {}

  win.once('ready-to-show', () => win.show());
  win.loadFile(path.join(__dirname, 'index.html'));
  mainWindow = win;
  win.on('closed', () => {
    mainWindow = null;
  });
}

function createTray() {
  const iconPath = path.join(__dirname, 'assets', 'tray.png');
  tray = new Tray(iconPath);
  const contextMenu = Menu.buildFromTemplate([
    { label: '显示主窗口', click: () => mainWindow?.show() },
    { label: '退出', click: () => app.quit() },
  ]);
  tray.setToolTip('WeChat Selkies - 本地远程客户端');
  tray.setContextMenu(contextMenu);
  tray.on('double-click', () => mainWindow?.show());
}

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  createWindow();
  try {
    const trayPath = path.join(__dirname, 'assets', 'tray.png');
    const fs = require('fs');
    if (fs.existsSync(trayPath)) createTray();
  } catch (_) {}
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
  else mainWindow?.show();
});

// 应用版本（供界面显示）
ipcMain.handle('get-app-version', () => appVersion);

// 连接列表
ipcMain.handle('get-connections', () => ({
  connections: getConnections(),
  defaultId: getDefaultConnectionId(),
}));

ipcMain.handle('save-connection', (_e, conn) => {
  const list = getConnections();
  const id = conn.id || randomUUID();
  const entry = {
    id,
    name: conn.name || '未命名',
    url: conn.url || DEFAULT_URL,
    ignoreSsl: conn.ignoreSsl !== false,
    openExternal: !!conn.openExternal,
    username: (conn.username || '').trim(),
    password: conn.password != null ? String(conn.password) : '',
  };
  const idx = list.findIndex((c) => c.id === id);
  if (idx >= 0) list[idx] = entry;
  else list.push(entry);
  store.set(CONFIG_KEYS.connections, list);
  return { connections: list, defaultId: getDefaultConnectionId() };
});

ipcMain.handle('delete-connection', (_e, id) => {
  const list = getConnections().filter((c) => c.id !== id);
  let defaultId = getDefaultConnectionId();
  if (defaultId === id) defaultId = list[0]?.id ?? null;
  store.set(CONFIG_KEYS.connections, list);
  store.set(CONFIG_KEYS.defaultConnectionId, defaultId);
  return { connections: list, defaultId };
});

ipcMain.handle('set-default-connection', (_e, id) => {
  store.set(CONFIG_KEYS.defaultConnectionId, id);
  return getDefaultConnectionId();
});

// 打开微信：传入 connection 或 connectionId
ipcMain.handle('open-wechat', async (_e, opts) => {
  let conn = opts.connection;
  if (!conn && opts.connectionId) {
    conn = getConnections().find((c) => c.id === opts.connectionId);
  }
  if (!conn) {
    const defaultId = getDefaultConnectionId();
    conn = getConnections().find((c) => c.id === defaultId) || getConnections()[0];
  }
  if (!conn) return { opened: 'none' };
  const url = (conn.url || '').trim() || DEFAULT_URL;
  const useExternal = !!conn.openExternal;
  if (useExternal) {
    await shell.openExternal(url);
    return { opened: 'external' };
  }
  const wechatWin = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    title: `WeChat Selkies - ${conn.name || '微信'}`,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      webSecurity: !conn.ignoreSsl,
    },
  });
  const iconPath = path.join(__dirname, 'assets', 'icon.png');
  try {
    if (require('fs').existsSync(iconPath)) wechatWin.setIcon(iconPath);
  } catch (_) {}
  if (conn.ignoreSsl) {
    wechatWin.webContents.session.setCertificateVerifyProc((_, callback) => callback(0));
  }
  const username = (conn.username || '').trim();
  const password = conn.password != null ? String(conn.password) : '';
  if (username || password) {
    try {
      const u = new URL(url);
      const origin = u.origin;
      const auth = Buffer.from(`${username}:${password}`).toString('base64');
      wechatWin.webContents.session.webRequest.onBeforeSendHeaders(
        { urls: [origin + '/*', origin] },
        (details, callback) => {
          const headers = { ...details.requestHeaders };
          headers['Authorization'] = 'Basic ' + auth;
          callback({ requestHeaders: headers });
        }
      );
    } catch (_) {}
  }
  wechatWin.webContents.setWindowOpenHandler(({ url: u }) => {
    shell.openExternal(u);
    return { action: 'deny' };
  });
  wechatWin.loadURL(url);
  return { opened: 'internal' };
});

ipcMain.on('open-external', (_e, url) => {
  if (url && typeof url === 'string') shell.openExternal(url);
});
