import 'package:flutter/material.dart';

import '../models/connection.dart';
import '../services/platform_service.dart';

/// 添加 / 编辑连接的弹窗。返回保存后的 Connection，取消返回 null。
class ConnectionFormDialog extends StatefulWidget {
  final Connection? existing;

  const ConnectionFormDialog({super.key, this.existing});

  static Future<Connection?> show(BuildContext context, {Connection? existing}) {
    return showDialog<Connection>(
      context: context,
      builder: (_) => ConnectionFormDialog(existing: existing),
    );
  }

  @override
  State<ConnectionFormDialog> createState() => _ConnectionFormDialogState();
}

class _ConnectionFormDialogState extends State<ConnectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late bool _ignoreSsl;
  late bool _openExternal;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _url = TextEditingController(text: c?.url ?? kDefaultUrl);
    _username = TextEditingController(text: c?.username ?? '');
    _password = TextEditingController(text: c?.password ?? '');
    _ignoreSsl = c?.ignoreSsl ?? true;
    _openExternal = c?.openExternal ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base = widget.existing ?? Connection.create();
    final result = base.copyWith(
      name: _name.text.trim().isEmpty ? '未命名' : _name.text.trim(),
      url: normalizeUrl(_url.text).isEmpty ? kDefaultUrl : normalizeUrl(_url.text),
      username: _username.text.trim(),
      password: _password.text,
      ignoreSsl: _ignoreSsl,
      openExternal: _openExternal,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑连接' : '添加连接'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：本地微信、公司服务器',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: '服务地址',
                    hintText: 'https://localhost:3001',
                    helperText: '本地一般为 https://localhost:3001，远程填写服务器地址',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入服务地址' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: '登录用户名（可选）',
                    hintText: '未填写则不进行账号密码认证',
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '登录密码（可选）',
                    hintText: '与用户名同时填写时生效',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('忽略 SSL 证书错误'),
                  value: _ignoreSsl,
                  onChanged: (v) => setState(() => _ignoreSsl = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用系统默认浏览器打开'),
                  subtitle: PlatformService.supportsInAppWebView
                      ? null
                      : const Text('当前平台不支持应用内浏览，将始终使用系统浏览器'),
                  value: _openExternal || !PlatformService.supportsInAppWebView,
                  onChanged: PlatformService.supportsInAppWebView
                      ? (v) => setState(() => _openExternal = v)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
