const String simpleFileManagerHtmlPage = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>文件简易管理</title>
<style>
  * { box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; }
  body { margin: 0; min-height: 100dvh; height: 100dvh; display: flex; flex-direction: column; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f4f6fb; color: #1f2937; overflow: hidden; }
  header { padding: clamp(14px, 1.6vw, 20px) clamp(16px, 1.8vw, 24px); background: #fff; border-bottom: 1px solid #e5e7eb; display: flex; align-items: center; justify-content: space-between; gap: 12px; flex: 0 0 auto; }
  h1 { margin: 0; font-size: 20px; }
  .status { color: #667085; font-size: 13px; word-break: break-all; }
  main { flex: 1 1 auto; min-height: 0; width: 100%; display: grid; grid-template-columns: minmax(280px, 30vw) minmax(0, 1fr); gap: clamp(10px, 1.2vw, 16px); padding: clamp(10px, 1.2vw, 16px); overflow: hidden; }
  aside, section { min-height: 0; height: 100%; background: #fff; border: 1px solid #e5e7eb; border-radius: 16px; overflow: hidden; box-shadow: 0 8px 22px rgba(15,23,42,.05); }
  aside { display: flex; flex-direction: column; }
  section { display: flex; min-width: 0; }
  .pane-title { padding: 14px 16px; border-bottom: 1px solid #eef2f7; font-weight: 700; display: flex; justify-content: space-between; gap: 8px; align-items: center; }
  .toolbar { padding: 12px; display: flex; gap: 8px; border-bottom: 1px solid #eef2f7; }
  input { width: 100%; border: 1px solid #d0d5dd; border-radius: 10px; padding: 10px 12px; font-size: 14px; }
  button { border: 0; border-radius: 10px; padding: 9px 12px; background: #eef2ff; color: #3730a3; font-weight: 700; cursor: pointer; white-space: nowrap; }
  button.primary { background: #4f46e5; color: white; }
  button.danger { background: #fee2e2; color: #b42318; }
  button.icon { padding: 6px 8px; border-radius: 8px; font-size: 12px; }
  button.ghost { background: transparent; color: #667085; }
  button:disabled { opacity: .5; cursor: not-allowed; }
  .list { overflow: auto; padding: 8px; }
  .entry { width: 100%; display: flex; align-items: center; gap: 8px; padding: 10px; border-radius: 10px; cursor: pointer; }
  .entry:hover, .entry.active { background: #f2f4ff; }
  .entry-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .entry-meta { color: #98a2b3; font-size: 12px; }
  .favorite { color: #f59e0b; }
  .editor { display: grid; grid-template-rows: auto 1fr; height: 100%; }
  #editorPanel > * { flex: 1 1 auto; min-width: 0; min-height: 0; }
  .editor-head { padding: 12px 16px; border-bottom: 1px solid #eef2f7; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
  .file-title { min-width: 0; }
  .file-title strong, .file-title span { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file-title span { color: #667085; font-size: 12px; margin-top: 3px; }
  textarea { width: 100%; height: 100%; resize: none; border: 0; outline: none; padding: 16px; font: 14px/1.6 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  .empty { height: 100%; display: grid; place-items: center; color: #667085; text-align: center; padding: 24px; }
  .split { display: grid; grid-template-rows: minmax(0, 1fr) minmax(150px, 32%); min-height: 0; }
  .favorites { border-top: 1px solid #eef2f7; display: grid; grid-template-rows: auto minmax(0, 1fr); min-height: 0; overflow: hidden; }
  .favorites .list { min-height: 0; overflow: auto; padding-bottom: 22px; }
  .toast { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); background: #111827; color: #fff; padding: 10px 14px; border-radius: 999px; opacity: 0; transition: opacity .2s; pointer-events: none; max-width: 92vw; }
  .toast.show { opacity: 1; }
  @media (max-width: 760px) {
    header { align-items: flex-start; flex-direction: column; gap: 8px; padding: 12px; }
    h1 { font-size: 18px; }
    main { grid-template-columns: 1fr; grid-template-rows: minmax(260px, 40dvh) minmax(0, 1fr); gap: 10px; padding: 10px; }
    aside, section, .editor { min-height: 0; }
    .editor-head { align-items: stretch; flex-direction: column; }
    .split { grid-template-rows: minmax(0, 1fr) minmax(112px, 28%); }
    .pane-title { padding: 12px 14px; }
    .toolbar { padding: 10px; }
    .list { padding: 6px; }
    .entry { padding: 8px 10px; }
    textarea { padding: 14px; font-size: 13px; }
    .editor-head .actions { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px; }
  }
</style>
</head>
<body>
<header>
  <div><h1>文件简易管理</h1><div class="status" id="pathLabel">加载中...</div></div>
  <button onclick="loadTree(currentPath)">刷新</button>
</header>
<main>
  <aside>
    <div class="pane-title"><span>文件树</span><button class="ghost" onclick="goRoot()">根目录</button></div>
    <div class="toolbar"><input id="pathInput" placeholder="输入路径后回车"><button onclick="loadTree(pathInput.value)">打开</button></div>
    <div class="split">
      <div class="list" id="tree"></div>
      <div class="favorites"><div class="pane-title">收藏路径</div><div class="list" id="favorites"></div></div>
    </div>
  </aside>
  <section id="editorPanel"><div class="empty">请选择左侧的文本文件进行编辑。</div></section>
</main>
<div class="toast" id="toast"></div>
<script>
let rootPath = '';
let currentPath = '';
let currentFile = '';
let favorites = [];
const tree = document.getElementById('tree');
const favoritesEl = document.getElementById('favorites');
const pathInput = document.getElementById('pathInput');
const pathLabel = document.getElementById('pathLabel');
const editorPanel = document.getElementById('editorPanel');
pathInput.addEventListener('keydown', e => { if (e.key === 'Enter') loadTree(pathInput.value); });
document.addEventListener('keydown', e => {
  if ((e.ctrlKey || e.metaKey) && e.key && e.key.toLowerCase() === 's') {
    e.preventDefault();
    if (currentFile) saveFile();
  }
});
function toast(message) { const el = document.getElementById('toast'); el.textContent = message; el.classList.add('show'); setTimeout(() => el.classList.remove('show'), 2200); }
async function api(url, options) { const res = await fetch(url, options); const data = await res.json().catch(() => ({})); if (!res.ok) throw new Error(data.error || ('HTTP ' + res.status)); return data; }
async function loadTree(path) {
  try {
    const data = await api('/api/tree?path=' + encodeURIComponent(path || ''));
    rootPath = data.rootPath; currentPath = data.path; favorites = data.favorites || [];
    pathInput.value = currentPath; pathLabel.textContent = currentPath;
    renderTree(data); renderFavorites();
  } catch (e) { toast('打开目录失败：' + e.message); }
}
function renderTree(data) {
  tree.innerHTML = '';
  if (data.parentPath) tree.appendChild(entry({name:'..', path:data.parentPath, type:'directory'}, true));
  for (const item of data.entries) tree.appendChild(entry(item, false));
}
function entry(item) {
  const row = document.createElement('div'); row.className = 'entry' + (item.path === currentFile ? ' active' : '');
  const icon = item.type === 'directory' ? '📁' : (item.editable ? '📝' : '📄');
  row.innerHTML = '<span>' + icon + '</span><span class="entry-name"></span><span class="entry-meta">' + (item.favorite ? '★' : '') + '</span>' + (item.type === 'file' ? '<button class="danger icon" title="删除文件">删除</button>' : '');
  row.querySelector('.entry-name').textContent = item.name;
  row.title = item.path;
  const deleteBtn = row.querySelector('button');
  if (deleteBtn) deleteBtn.onclick = e => { e.stopPropagation(); confirmDeleteFile(item.path, item.name); };
  row.onclick = () => item.type === 'directory' ? loadTree(item.path) : (item.editable ? openFile(item.path) : toast('该文件类型暂不支持编辑'));
  return row;
}
function renderFavorites() {
  favoritesEl.innerHTML = '';
  if (!favorites.length) { favoritesEl.innerHTML = '<div class="entry"><span class="entry-name">暂无收藏</span></div>'; return; }
  for (const path of favorites) {
    const row = document.createElement('div'); row.className = 'entry'; row.title = path;
    row.innerHTML = '<span class="favorite">★</span><span class="entry-name"></span><button class="ghost">移除</button>';
    row.querySelector('.entry-name').textContent = path;
    row.querySelector('.entry-name').onclick = () => openPath(path);
    row.querySelector('button').onclick = e => { e.stopPropagation(); removeFavorite(path); };
    favoritesEl.appendChild(row);
  }
}
async function openPath(path) { try { await openFile(path); } catch (_) { loadTree(path); } }
async function openFile(path) {
  const data = await api('/api/file?path=' + encodeURIComponent(path)); currentFile = data.path;
  editorPanel.innerHTML = '<div class="editor"><div class="editor-head"><div class="file-title"><strong></strong><span></span></div><div class="actions"><button id="favBtn"></button><button class="danger" id="deleteBtn">删除</button><button class="primary" id="saveBtn">保存</button></div></div><textarea id="content"></textarea></div>';
  editorPanel.querySelector('strong').textContent = data.name; editorPanel.querySelector('span').textContent = data.path;
  document.getElementById('content').value = data.content;
  document.getElementById('saveBtn').onclick = saveFile;
  document.getElementById('deleteBtn').onclick = () => confirmDeleteFile(data.path, data.name);
  document.getElementById('favBtn').textContent = data.favorite ? '取消收藏' : '收藏路径';
  document.getElementById('favBtn').onclick = () => data.favorite ? removeFavorite(data.path) : addFavorite(data.path);
}
async function saveFile() {
  if (!currentFile) return;
  try { await api('/api/file', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({path: currentFile, content: document.getElementById('content').value})}); toast('已保存'); }
  catch (e) { toast('保存失败：' + e.message); }
}
async function addFavorite(path) { try { const data = await api('/api/favorites', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({path})}); favorites = data.favorites || []; renderFavorites(); toast('已收藏'); } catch (e) { toast('收藏失败：' + e.message); } }
async function removeFavorite(path) { try { const data = await api('/api/favorites?path=' + encodeURIComponent(path), {method:'DELETE'}); favorites = data.favorites || []; renderFavorites(); toast('已移除收藏'); } catch (e) { toast('移除失败：' + e.message); } }
async function confirmDeleteFile(path, name) {
  if (!confirm('确定删除文件 “' + name + '”？\n\n此操作不可撤销。')) return;
  try {
    const data = await api('/api/file?path=' + encodeURIComponent(path), {method:'DELETE'});
    favorites = data.favorites || favorites.filter(item => item !== path);
    if (currentFile === path) {
      currentFile = '';
      editorPanel.innerHTML = '<div class="empty">文件已删除，请从左侧选择其他文本文件。</div>';
    }
    renderFavorites();
    await loadTree(currentPath);
    toast('已删除文件');
  } catch (e) { toast('删除失败：' + e.message); }
}
function goRoot() { loadTree(rootPath); }
loadTree('');
</script>
</body>
</html>
''';
