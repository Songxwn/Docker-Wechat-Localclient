const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('wechatClient', {
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  getConnections: () => ipcRenderer.invoke('get-connections'),
  saveConnection: (conn) => ipcRenderer.invoke('save-connection', conn),
  deleteConnection: (id) => ipcRenderer.invoke('delete-connection', id),
  setDefaultConnection: (id) => ipcRenderer.invoke('set-default-connection', id),
  openWechat: (opts) => ipcRenderer.invoke('open-wechat', opts),
  openExternal: (url) => ipcRenderer.send('open-external', url),
});
