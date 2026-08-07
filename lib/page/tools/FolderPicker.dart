import 'package:flutter/material.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/model/FileItemModel.dart';

/// 移动/复制选择结果
class MovePickResult {
  final bool copy;
  final String uri;
  const MovePickResult({required this.copy, required this.uri});
}

/// 移动 / 复制目标文件夹选择器
/// 从 [startUri] 开始浏览文件夹树，返回用户选定的目标目录
/// [title] / [confirmLabel] 在 allowCopy 为 false 时生效（如压缩到 / 解压到）
class FolderPicker {
  static Future<MovePickResult?> pick(
    BuildContext context, {
    required String startUri,
    bool allowCopy = true,
    String title = '移动到',
    String confirmLabel = '移动到此',
  }) {
    return showDialog<MovePickResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FolderPickerDialog(
        startUri: startUri,
        allowCopy: allowCopy,
        title: title,
        confirmLabel: confirmLabel,
      ),
    );
  }
}

class _FolderPickerDialog extends StatefulWidget {
  final String startUri;
  final bool allowCopy;
  final String title;
  final String confirmLabel;

  const _FolderPickerDialog({
    required this.startUri,
    required this.allowCopy,
    required this.title,
    required this.confirmLabel,
  });

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  /// 从根目录到当前目录的面包屑名称（不含根「我的存储」）
  final List<String> _crumbs = [];
  late String _currentUri = widget.startUri;
  List<FileItemModel> _folders = [];
  bool _loading = true;
  bool _copy = false;

  @override
  void initState() {
    super.initState();
    // 起点非根目录时，把起点名称压入面包屑，支持逐级返回上级直至根目录
    if (_currentUri != FileApi.myRootUri) {
      _crumbs.add(_displayNameOf(_currentUri));
    }
    _load();
  }

  /// 是否还能继续返回上级
  bool get _canGoUp => _currentUri != FileApi.myRootUri;

  /// 取 URI 最后一段的展示名（URL 解码）
  String _displayNameOf(String uri) {
    final idx = uri.lastIndexOf('/');
    return Uri.decodeComponent(idx < 0 ? uri : uri.substring(idx + 1));
  }

  /// 取父目录 URI
  String _parentOf(String uri) {
    final idx = uri.lastIndexOf('/');
    return idx <= 0 ? uri : uri.substring(0, idx);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await FileApi.listFiles(_currentUri);
      final files = (data['files'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FileItemModel.fromJson)
          .where((f) => f.isDir)
          .toList();
      if (!mounted) return;
      setState(() {
        _folders = files;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _enter(FileItemModel folder) {
    setState(() {
      _crumbs.add(folder.name);
      _currentUri = folder.path;
    });
    _load();
  }

  void _goUp() {
    if (!_canGoUp) return;
    setState(() {
      _currentUri = _parentOf(_currentUri);
      if (_crumbs.isNotEmpty) _crumbs.removeLast();
    });
    _load();
  }

  String get _pathText {
    if (_crumbs.isEmpty) return '我的存储';
    return '我的存储 ▸ ${_crumbs.join(' ▸ ')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.allowCopy
                      ? (_copy ? '复制到' : widget.title)
                      : widget.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, size: 22, color: AppColors.ink3),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.allowCopy) ...[
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    _modeBtn('移动', false),
                    _modeBtn('复制', true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              _pathText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _folders.isEmpty
                      ? Center(
                          child: Text(
                            '该文件夹下没有子文件夹',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.ink3),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _folders.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: AppColors.line),
                          itemBuilder: (context, index) {
                            final folder = _folders[index];
                            return InkWell(
                              onTap: () => _enter(folder),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_rounded,
                                        size: 22, color: AppColors.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        folder.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: AppColors.ink),
                                      ),
                                    ),
                                    Icon(Icons.chevron_right,
                                        size: 20, color: AppColors.ink3),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_canGoUp)
                  TextButton.icon(
                    onPressed: _goUp,
                    icon: Icon(Icons.arrow_upward,
                        size: 17, color: AppColors.ink2),
                    label: const Text('上一级'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.ink2,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        MovePickResult(copy: _copy, uri: _currentUri),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: Text(
                        widget.allowCopy
                            ? (_copy ? '复制到此' : widget.confirmLabel)
                            : widget.confirmLabel,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(String label, bool copy) {
    final active = _copy == copy;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _copy = copy),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: active ? AppColors.primary : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }
}
