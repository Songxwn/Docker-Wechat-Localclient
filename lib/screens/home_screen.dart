import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/connection.dart';
import '../providers/connection_store.dart';
import '../services/platform_service.dart';
import 'connection_form_dialog.dart';
import 'webview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String _deployUrl = 'https://songxwn.com/cloud-wechat/';
  static const String _projectUrl = 'https://github.com/nickrunning/wechat-selkies';
  static const String _appVersion = '5.0.0';

  Future<void> _openConnection(BuildContext context, Connection conn) async {
    final platform = const PlatformService();
    final useExternal = conn.openExternal || !PlatformService.supportsInAppWebView;
    if (useExternal) {
      final ok = await platform.openExternal(conn.url);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接：${conn.url}')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(connection: conn),
      ),
    );
  }

  Future<void> _addOrEdit(BuildContext context, {Connection? existing}) async {
    final store = context.read<ConnectionStore>();
    final result = await ConnectionFormDialog.show(context, existing: existing);
    if (result != null) {
      await store.save(result);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Connection conn) async {
    final store = context.read<ConnectionStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('确定要删除「${conn.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await store.delete(conn.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WeChat Selkies'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(context),
        icon: const Icon(Icons.add),
        label: const Text('添加连接'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Consumer<ConnectionStore>(
            builder: (context, store, _) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text(
                    '管理连接并打开 wechat-selkies 网页版微信',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    context,
                    title: '已保存的连接',
                    child: store.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('暂无连接，点击「添加连接」保存一个。'),
                          )
                        : Column(
                            children: [
                              for (final c in store.connections)
                                _ConnectionTile(
                                  connection: c,
                                  isDefault: store.isDefault(c),
                                  onOpen: () => _openConnection(context, c),
                                  onEdit: () =>
                                      _addOrEdit(context, existing: c),
                                  onSetDefault: () => store.setDefault(c.id),
                                  onDelete: () => _confirmDelete(context, c),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  _tipsCard(context),
                  const SizedBox(height: 24),
                  _footer(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context,
      {required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _tipsCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    final platform = const PlatformService();
    Widget bullet(Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: muted)),
              Expanded(child: child),
            ],
          ),
        );
    final style = TextStyle(color: muted, fontSize: 13);
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontSize: 13,
    );
    return _sectionCard(
      context,
      title: '使用说明',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bullet(RichText(
            text: TextSpan(style: style, children: [
              const TextSpan(text: '请先在 Linux / Docker 中部署 wechat-selkies（'),
              _linkSpan(context, '部署说明', _deployUrl, linkStyle, platform),
              const TextSpan(text: '），并确保端口 3001 可访问。'),
            ]),
          )),
          bullet(Text(
            '若通过 WSL2 或远程 Linux 运行，请将 localhost 改为对应 IP（如 https://192.168.x.x:3001）。',
            style: style,
          )),
          bullet(Text(
            '剪贴板共享：本机复制的文字、图片可与 Docker 内微信共享，在网页版微信中可直接粘贴发送。',
            style: style,
          )),
          bullet(Text(
            '文件拖入 / 上传：将文件拖入或选择上传，可发送到 Docker 内微信聊天。',
            style: style,
          )),
        ],
      ),
    );
  }

  TextSpan _linkSpan(BuildContext context, String text, String url,
      TextStyle style, PlatformService platform) {
    return TextSpan(
      text: text,
      style: style,
      recognizer: TapGestureRecognizer()..onTap = () => platform.openExternal(url),
    );
  }

  Widget _footer(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    final platform = const PlatformService();
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text('v$_appVersion', style: TextStyle(color: muted, fontSize: 12)),
          TextButton(
            onPressed: () => platform.openExternal(_deployUrl),
            child: const Text('部署说明'),
          ),
          Text('·', style: TextStyle(color: muted)),
          TextButton(
            onPressed: () => platform.openExternal(_projectUrl),
            child: const Text('wechat-selkies 项目'),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final Connection connection;
  final bool isDefault;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;

  const _ConnectionTile({
    required this.connection,
    required this.isDefault,
    required this.onOpen,
    required this.onEdit,
    required this.onSetDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            connection.name,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '默认',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connection.url,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton(onPressed: onOpen, child: const Text('连接')),
              OutlinedButton(onPressed: onEdit, child: const Text('编辑')),
              if (!isDefault)
                OutlinedButton(
                  onPressed: onSetDefault,
                  child: const Text('设为默认'),
                ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('删除'),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
