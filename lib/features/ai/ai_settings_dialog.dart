import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_client.dart';
import 'ai_config.dart';

Future<AiConfig?> showAiSettingsDialog(
  BuildContext context, {
  required AiConfig initialConfig,
}) {
  return showDialog<AiConfig>(
    context: context,
    builder: (context) => _AiSettingsDialog(initialConfig: initialConfig),
  );
}

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.initialConfig});

  final AiConfig initialConfig;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late AiEndpointType _endpoint;
  bool _loadingModels = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: widget.initialConfig.baseUrl,
    );
    _apiKeyController = TextEditingController(
      text: widget.initialConfig.apiKey,
    );
    _modelController = TextEditingController(text: widget.initialConfig.model);
    _endpoint = widget.initialConfig.endpoint;
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  AiConfig get _config => AiConfig(
    baseUrl: _baseUrlController.text.trim(),
    apiKey: _apiKeyController.text.trim(),
    model: _modelController.text.trim(),
    endpoint: _endpoint,
  );

  Future<void> _loadModels() async {
    if (_baseUrlController.text.trim().isEmpty) {
      _showMessage('请先填写 Base URL');
      return;
    }
    setState(() => _loadingModels = true);
    final client = AiClient();
    try {
      final models = await client.fetchModels(_config);
      if (!mounted) return;
      if (models.isEmpty) {
        _showMessage('接口没有返回可用模型');
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择模型'),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: models.length,
                itemBuilder: (context, index) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, models[index]),
                  child: Text(models[index]),
                ),
              ),
            ),
          ],
        ),
      );
      if (selected != null) _modelController.text = selected;
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _save() {
    final config = _config;
    if (!config.isReady) {
      _showMessage('Base URL 和模型不能为空');
      return;
    }
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 接口设置'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.example.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    icon: Icon(
                      _obscureKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AiEndpointType>(
                initialValue: _endpoint,
                decoration: const InputDecoration(labelText: '请求端点'),
                items: AiEndpointType.values
                    .map(
                      (endpoint) => DropdownMenuItem(
                        value: endpoint,
                        child: Text(endpoint.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _endpoint = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                decoration: InputDecoration(
                  labelText: '模型',
                  hintText: '可手动填写',
                  suffixIcon: IconButton(
                    tooltip: '查询 /v1/models',
                    onPressed: _loadingModels
                        ? null
                        : () => unawaited(_loadModels()),
                    icon: _loadingModels
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.list_alt_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
