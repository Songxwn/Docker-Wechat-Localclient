(function () {
  const DEFAULT_URL = 'https://localhost:3001';

  const connectionList = document.getElementById('connectionList');
  const emptyHint = document.getElementById('emptyHint');
  const btnAdd = document.getElementById('btnAdd');
  const modalOverlay = document.getElementById('modalOverlay');
  const modal = document.getElementById('modal');
  const modalTitle = document.getElementById('modalTitle');
  const connectionForm = document.getElementById('connectionForm');
  const editId = document.getElementById('editId');
  const connName = document.getElementById('connName');
  const connUrl = document.getElementById('connUrl');
  const connIgnoreSsl = document.getElementById('connIgnoreSsl');
  const connOpenExternal = document.getElementById('connOpenExternal');
  const btnModalCancel = document.getElementById('btnModalCancel');
  const btnModalSave = document.getElementById('btnModalSave');

  let connections = [];
  let defaultId = null;

  function normalizeUrl(value) {
    const s = (value || '').trim();
    if (!s) return '';
    if (!/^https?:\/\//i.test(s)) return 'https://' + s;
    return s;
  }

  async function loadConnections() {
    if (typeof wechatClient === 'undefined') return;
    const data = await wechatClient.getConnections();
    connections = data.connections || [];
    defaultId = data.defaultId || null;
    renderList();
  }

  function renderList() {
    connectionList.innerHTML = '';
    emptyHint.hidden = connections.length > 0;
    connections.forEach((c) => {
      const li = document.createElement('li');
      li.className = 'connection-item';
      const isDefault = c.id === defaultId;
      li.innerHTML = `
        <div class="connection-info">
          <span class="connection-name">${escapeHtml(c.name)}</span>
          <span class="connection-url">${escapeHtml(c.url)}</span>
          ${isDefault ? '<span class="default-badge">默认</span>' : ''}
        </div>
        <div class="connection-actions">
          <button type="button" class="btn btn-sm btn-primary" data-action="open" data-id="${escapeAttr(c.id)}">连接</button>
          <button type="button" class="btn btn-sm btn-secondary" data-action="edit" data-id="${escapeAttr(c.id)}">编辑</button>
          ${!isDefault ? `<button type="button" class="btn btn-sm btn-secondary" data-action="default" data-id="${escapeAttr(c.id)}">设为默认</button>` : ''}
          <button type="button" class="btn btn-sm btn-danger" data-action="delete" data-id="${escapeAttr(c.id)}">删除</button>
        </div>
      `;
      connectionList.appendChild(li);
    });
    connectionList.querySelectorAll('[data-action]').forEach((btn) => {
      btn.addEventListener('click', handleListAction);
    });
  }

  function escapeHtml(s) {
    const div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  function escapeAttr(s) {
    return String(s).replace(/"/g, '&quot;');
  }

  function handleListAction(e) {
    const btn = e.target.closest('[data-action][data-id]');
    if (!btn) return;
    const action = btn.dataset.action;
    const id = btn.dataset.id;
    const conn = connections.find((c) => c.id === id);
    if (!conn) return;
    if (action === 'open') {
      openWechat(conn);
      return;
    }
    if (action === 'edit') {
      openModal(conn);
      return;
    }
    if (action === 'default') {
      setDefault(id);
      return;
    }
    if (action === 'delete') {
      deleteConnection(id);
    }
  }

  async function openWechat(conn) {
    if (typeof wechatClient === 'undefined') {
      window.open(conn.url || DEFAULT_URL, '_blank');
      return;
    }
    try {
      await wechatClient.openWechat({ connection: conn });
    } catch (err) {
      console.error(err);
    }
  }

  async function setDefault(id) {
    if (typeof wechatClient === 'undefined') return;
    await wechatClient.setDefaultConnection(id);
    await loadConnections();
  }

  async function deleteConnection(id) {
    if (typeof wechatClient === 'undefined') return;
    if (!confirm('确定要删除该连接吗？')) return;
    await wechatClient.deleteConnection(id);
    await loadConnections();
  }

  function openModal(conn) {
    if (conn) {
      modalTitle.textContent = '编辑连接';
      editId.value = conn.id;
      connName.value = conn.name || '';
      connUrl.value = conn.url || DEFAULT_URL;
      connIgnoreSsl.checked = conn.ignoreSsl !== false;
      connOpenExternal.checked = !!conn.openExternal;
    } else {
      modalTitle.textContent = '添加连接';
      editId.value = '';
      connName.value = '';
      connUrl.value = DEFAULT_URL;
      connIgnoreSsl.checked = true;
      connOpenExternal.checked = false;
    }
    modalOverlay.removeAttribute('hidden');
    connName.focus();
  }

  function closeModal() {
    modalOverlay.setAttribute('hidden', '');
  }

  connectionForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = editId.value || undefined;
    const name = connName.value.trim() || '未命名';
    const url = normalizeUrl(connUrl.value) || DEFAULT_URL;
    if (typeof wechatClient === 'undefined') return;
    btnModalSave.disabled = true;
    try {
      await wechatClient.saveConnection({
        id: id || undefined,
        name,
        url,
        ignoreSsl: connIgnoreSsl.checked,
        openExternal: connOpenExternal.checked,
      });
      closeModal();
      await loadConnections();
    } finally {
      btnModalSave.disabled = false;
    }
  });

  btnAdd.addEventListener('click', () => openModal(null));
  btnModalCancel.addEventListener('click', closeModal);
  modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) closeModal();
  });

  loadConnections();
})();
