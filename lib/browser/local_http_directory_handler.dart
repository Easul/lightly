import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class LocalHttpDirectoryHandler {
  const LocalHttpDirectoryHandler();

  Future<void> serveDirectory(
    HttpRequest request,
    Directory directory, {
    required bool hasUploadKey,
    required Future<void> Function(HttpRequest request, File file) serveFile,
  }) async {
    final indexFile = File(p.join(directory.path, 'index.html'));
    if (await indexFile.exists()) {
      await serveFile(request, indexFile);
      return;
    }

    final entities = await directory
        .list(followLinks: false)
        .where((entity) => !p.basename(entity.path).startsWith('.'))
        .toList();
    entities.sort((a, b) => a.path.compareTo(b.path));

    final rows = entities.map((entity) {
      final name = p.basename(entity.path);
      final href = Uri.encodeComponent(name) + (entity is Directory ? '/' : '');
      return '<li><a href="$href">${const HtmlEscape().convert(name)}${entity is Directory ? '/' : ''}</a></li>';
    }).join();

    final currentPath = request.uri.path.isEmpty ? '/' : request.uri.path;
    final uploadSection =
        '''
<section style="margin:16px 0;padding:16px;border:1px solid #ddd;border-radius:12px;background:#fafafa;">
  <h2 style="margin:0 0 12px;font-size:18px;">上传文件</h2>
  <div style="display:flex;flex-direction:column;gap:10px;max-width:520px;">
    ${hasUploadKey ? '<input id="upload-key" type="text" placeholder="请输入上传密钥" style="padding:10px;border:1px solid #ccc;border-radius:8px;" />' : ''}
    <input id="upload-files" type="file" multiple style="padding:6px 0;" />
    <button onclick="uploadFiles()" style="padding:10px 14px;border:none;border-radius:8px;background:#5B5BD6;color:white;font-size:14px;cursor:pointer;">上传到当前目录</button>
    <div id="upload-status" style="font-size:13px;color:#555;"></div>
  </div>
</section>
<script>
async function uploadFiles() {
  const input = document.getElementById('upload-files');
  const status = document.getElementById('upload-status');
  const keyInput = document.getElementById('upload-key');
  const files = input.files;
  if (!files || files.length === 0) {
    status.textContent = '请选择要上传的文件';
    return;
  }
  status.textContent = '上传中...';
  const currentPath = ${jsonEncode(currentPath)};
  const key = keyInput ? keyInput.value.trim() : '';
  const results = [];
  for (const file of files) {
    const url = '/_upload?path=' + encodeURIComponent(currentPath) + '&filename=' + encodeURIComponent(file.name) + (key ? '&key=' + encodeURIComponent(key) : '');
    try {
      const resp = await fetch(url, { method: 'POST', body: file });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.error || ('HTTP ' + resp.status));
      results.push('✅ ' + file.name + ' 上传成功');
    } catch (err) {
      results.push('❌ ' + file.name + ' 上传失败: ' + err.message);
    }
  }
  status.innerHTML = results.join('<br>');
  setTimeout(() => location.reload(), 800);
}
</script>
''';

    final body =
        '''
<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Index of ${const HtmlEscape().convert(request.uri.path)}</title></head>
<body style="font-family:Arial,sans-serif;padding:16px;line-height:1.5;">
<h1>Index of ${const HtmlEscape().convert(request.uri.path)}</h1>
$uploadSection
<ul>$rows</ul>
</body></html>
''';
    request.response.headers.contentType = ContentType.html;
    request.response.write(body);
    await request.response.close();
  }
}
