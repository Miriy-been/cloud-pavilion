import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../api/FileApi.dart';
import '../enums/FileType.dart';
import '../model/FileItemModel.dart';
import '../util/ErrorText.dart';
import 'AppTheme.dart';

/// 页面水平留白
const double pagePad = 18;

/// 全局统一 SnackBar：浅蓝底（主题）+ 短时长，约 2.5s 自动消失
SnackBar appSnack(String message) => SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 2500),
    );

/// 字节数格式化
String formatBytes(int fileSize) {
  if (fileSize <= 0) return '0 B';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;
  if (fileSize < kb) return '$fileSize B';
  if (fileSize < mb) return '${(fileSize / kb).toStringAsFixed(1)} KB';
  if (fileSize < gb) return '${(fileSize / mb).toStringAsFixed(1)} MB';
  if (fileSize < tb) return '${(fileSize / gb).toStringAsFixed(1)} GB';
  return '${(fileSize / tb).toStringAsFixed(1)} TB';
}

/// 页面大标题 + 副标题 + 右侧操作
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;

  /// 二级页面标题样式：字号更小、字重更轻、取消加粗
  final bool secondary;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 12,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: secondary ? 17 : 22,
                    fontWeight:
                        secondary ? FontWeight.w600 : FontWeight.w700,
                    letterSpacing: secondary ? -0.2 : -0.3,
                    color: AppColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.ink3),
                    ),
                  ),
              ],
            ),
          ),
          if (actions != null)
            ...actions!.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: e,
                )),
        ],
      ),
    );
  }
}

/// 无边框图标按钮（AppBar 风格），支持自定义 child
class IconTile extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final Widget? child;

  /// 紧凑模式（返回箭头用）：更窄、图标左靠，减少向内缩进
  final bool compact;

  const IconTile({
    super.key,
    required this.icon,
    this.onTap,
    this.filled = true,
    this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: compact ? 32 : 40,
        height: 40,
        alignment: compact ? Alignment.centerLeft : null,
        decoration: filled
            ? BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(13),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              )
            : null,
        child: child ??
            Icon(icon, size: compact ? 20 : 22, color: AppColors.ink),
      ),
    );
  }
}

/// 底部弹窗顶部拖拽指示条
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.ink3.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 圆角文件图标瓦片
class FileTile extends StatelessWidget {
  final int type; // 0=文件 1=文件夹
  final String name;
  final double size;

  const FileTile({
    super.key,
    required this.type,
    required this.name,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: FileType.getBgColorByValue(type, name),
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(
        FileType.getIconByTypeAndName(type, name),
        size: size * 0.5,
        color: FileType.getColorByValue(type, name),
      ),
    );
  }
}

/// 磁盘缓存网络图片（flutter_cache_manager，与通知栏封面共用同一缓存实例）。
/// 换 URL 时保留旧图直到新图就绪，避免空白/占位闪烁。
class CachedImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  /// 加载中 / 加载失败（无 errorBuilder 时）显示的占位
  final Widget placeholder;
  final Widget Function(BuildContext, Object)? errorBuilder;

  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder = const SizedBox.shrink(),
    this.errorBuilder,
  });

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  static final BaseCacheManager _cache = DefaultCacheManager();
  File? _file;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    try {
      // 内存缓存优先，未命中再走磁盘/网络下载（同一缓存实例，取到即本地文件）
      final memory = await _cache.getFileFromMemory(url);
      final file = memory?.file ?? await _cache.getSingleFile(url);
      if (!mounted || url != widget.url) return;
      setState(() {
        _file = file;
        _error = null;
      });
    } catch (e) {
      if (!mounted || url != widget.url) return;
      // 失败时保留旧图（若有），否则显示占位
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null && file.existsSync()) {
      return Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        // 懒解码：按显示尺寸 × 像素比 降采样解码，
        // 避免缩略图/封面按原图全尺寸解码导致的内存峰值
        cacheWidth: widget.width != null
            ? (widget.width! * MediaQuery.devicePixelRatioOf(context)).round()
            : null,
        errorBuilder: (_, __, ___) => widget.errorBuilder?.call(context, '')
            ?? widget.placeholder,
      );
    }
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ?? widget.placeholder;
    }
    return widget.placeholder;
  }
}

/// 网格缩略图：图片文件加载网络缩略图，其余回退为类型图标
class GridThumb extends StatefulWidget {
  final FileItemModel file;
  final double size;

  const GridThumb({super.key, required this.file, required this.size});

  @override
  State<GridThumb> createState() => _GridThumbState();
}

class _GridThumbState extends State<GridThumb> {
  // 会话级缓存：避免同一文件反复请求缩略图
  static final Map<String, String> _cache = {};
  static final Map<String, Future<String?>> _inflight = {};
  String? _url;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant GridThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表滚动复用 State 时，换文件则重新加载，避免残留上一个文件的图片
    if (oldWidget.file.path != widget.file.path) _maybeLoad();
  }

  void _maybeLoad() {
    // 图片与音频（封面缩略图）均尝试加载缩略图
    if (FileType.isImage(widget.file.type, widget.file.name) ||
        FileType.isAudio(widget.file.type, widget.file.name)) {
      _load();
    }
  }

  Future<void> _load() async {
    final uri = widget.file.path;
    final cached = _cache[uri];
    if (cached != null) {
      if (mounted && cached.isNotEmpty) setState(() => _url = cached);
      return;
    }
    final future = _inflight.putIfAbsent(
      uri,
      () => FileApi.getThumbnailUrl(uri).then((u) {
        _inflight.remove(uri);
        if (u != null && u.isNotEmpty) _cache[uri] = u;
        return u;
      }).catchError((_) {
        // 取缩略图失败（无缩略图 / 网络错误），移除占位避免永久复用失败的 Future
        _inflight.remove(uri);
        return null;
      }),
    );
    final url = await future;
    if (mounted && url != null && url.isNotEmpty) {
      setState(() => _url = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = FileTile(
        type: widget.file.type, name: widget.file.name, size: widget.size);
    final url = _url;
    if (url == null || url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedImage(
        url: url,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        placeholder: fallback,
        errorBuilder: (_, __) => fallback,
      ),
    );
  }
}

/// 容量卡（白色底 + 浅蓝环形进度 + 入场绘制动效，百分比置于环内）
class CapacityCard extends StatefulWidget {
  final int usedBytes;
  final int totalBytes;
  final String? updatedAt;

  const CapacityCard({
    super.key,
    required this.usedBytes,
    required this.totalBytes,
    this.updatedAt,
  });

  @override
  State<CapacityCard> createState() => _CapacityCardState();
}

class _CapacityCardState extends State<CapacityCard>
    with SingleTickerProviderStateMixin {
  /// 入场绘制动画：进度弧从 0 平滑转到实际占用百分比，仅执行一次
  late final AnimationController _draw;
  late final Animation<double> _drawProgress;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _drawProgress =
        CurvedAnimation(parent: _draw, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.totalBytes <= 0 ? 1 : widget.totalBytes;
    final percent = (widget.usedBytes / total).clamp(0.0, 1.0);
    final remaining = (widget.totalBytes - widget.usedBytes)
        .clamp(0, widget.totalBytes > 0 ? widget.totalBytes : 0);
    final updatedAt = widget.updatedAt ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左侧：浅蓝环形进度（入场绘制动效），百分比文字置于环内
          SizedBox(
            width: 84,
            height: 84,
            child: AnimatedBuilder(
              animation: _drawProgress,
              builder: (context, child) => CustomPaint(
                painter: _RingPainter(
                  percent: percent * _drawProgress.value,
                  trackColor: AppColors.primarySoft,
                  arcColor: AppColors.primary,
                ),
                child: child,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(percent * 100).floor()}%',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1,
                        color: AppColors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已使用',
                      style: TextStyle(fontSize: 10, color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 右侧：容量信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '存储空间',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                _StatRow(label: '已用空间', value: formatBytes(widget.usedBytes)),
                _StatRow(label: '总容量', value: formatBytes(widget.totalBytes)),
                _StatRow(label: '剩余空间', value: formatBytes(remaining)),
                if (updatedAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '更新于 $updatedAt',
                    style: TextStyle(fontSize: 10.5, color: AppColors.ink3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 环形进度画笔
class _RingPainter extends CustomPainter {
  final double percent;
  final Color trackColor;
  final Color arcColor;

  _RingPainter({
    required this.percent,
    required this.trackColor,
    required this.arcColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    // 轨道（浅蓝柔底）
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    // 进度弧（品牌蓝，自 12 点方向顺时针）
    if (percent > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arcColor;
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * percent, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.percent != percent ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor;
}

/// 容量信息行（左标签右数值）
class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.ink3),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 胶囊主按钮（全宽）
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// 幽灵按钮（描边胶囊）
class GhostButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const GhostButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: AppColors.ink2),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink2,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: AppColors.line),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

/// 分区标签（灰色小标题 + 右侧内容）
class SectionHeader extends StatelessWidget {
  final String title;
  final String? count;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(
              text: title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.ink3,
                letterSpacing: 0.3,
              ),
              children: [
                if (count != null)
                  TextSpan(
                    text: ' · $count',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w400),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 列表行（瓦片 + 标题 + 元信息 + 尾部）
class FileRow extends StatelessWidget {
  final int type;
  final String name;
  final String meta;
  final bool selected;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPress;
  final Widget? trailing;
  final Widget? leading;

  const FileRow({
    super.key,
    required this.type,
    required this.name,
    required this.meta,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: onLongPress,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (leading != null)
              leading!
            else
              FileTile(type: type, name: name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(fontSize: 12, color: AppColors.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// 圆形多选/单选项
class RoundCheck extends StatelessWidget {
  final bool on;

  const RoundCheck({super.key, required this.on});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppColors.primary : AppColors.surface,
        border: Border.all(
          color: on ? AppColors.primary : AppColors.line,
          width: 1.8,
        ),
      ),
      child: on
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// 空状态（柔和品牌光环 + 可选的行动按钮）
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 柔和品牌光环
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: AppColors.primary),
                      const SizedBox(width: 5),
                      Text(
                        actionLabel!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 排序选项（value 空串表示默认排序）
class SortOption {
  final String value;
  final String label;

  const SortOption(this.value, this.label);
}

/// 排序胶囊（复用存储页样式：胶囊 + 底部弹层选择 + 升降序切换）
class SortChip extends StatelessWidget {
  final List<SortOption> options;

  /// 当前选中值
  final String value;

  /// 当前升降序：'asc' / 'desc' / 空
  final String direction;

  /// 是否展示升降序切换项（如「按是否过期」等无方向概念时置 false）
  final bool enableDirection;

  /// 选择新排序方式（外部负责刷新）
  final ValueChanged<String> onChanged;

  /// 切换升降序（外部负责翻转与刷新）
  final VoidCallback? onToggleDirection;

  const SortChip({
    super.key,
    required this.options,
    required this.value,
    this.direction = '',
    this.enableDirection = true,
    required this.onChanged,
    this.onToggleDirection,
  });

  String get _label {
    final label = options
        .firstWhere((o) => o.value == value,
            orElse: () => options.first)
        .label;
    if (!enableDirection || direction.isEmpty) return label;
    return '$label ${direction == 'asc' ? '↑' : '↓'}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (sheetCtx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const SheetHandle(),
                const SizedBox(height: 16),
                Text('排序方式',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 8),
                ...options.map((o) {
                  final selected = o.value == value;
                  return ListTile(
                    title: Text(o.label, style: const TextStyle(fontSize: 14)),
                    trailing: selected
                        ? Icon(Icons.check,
                            size: 18, color: AppColors.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      onChanged(o.value);
                    },
                  );
                }),
                if (enableDirection && value.isNotEmpty)
                  ListTile(
                    title: Text(
                        direction == 'desc' ? '切换为升序' : '切换为降序',
                        style: const TextStyle(fontSize: 14)),
                    trailing: Text(
                        direction == 'desc' ? '↓' : '↑',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.ink3)),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      onToggleDirection?.call();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert, size: 14, color: AppColors.ink2),
            const SizedBox(width: 4),
            Text(_label,
                style: TextStyle(fontSize: 12, color: AppColors.ink2)),
          ],
        ),
      ),
    );
  }
}

/// 列表 / 网格项入场动效：一次性 8px 上浮淡入（首帧执行，不做持续动画）
class ItemEnter extends StatelessWidget {
  final Widget child;

  const ItemEnter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// 分组卡片（设置项容器）
class GroupCard extends StatelessWidget {
  final List<Widget> children;

  const GroupCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// 设置行（彩色小图标 + 标签 + 尾部值 + 箭头）
class SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  const SettingRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.value,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: danger ? AppColors.danger : AppColors.ink,
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
                ),
              ),
            ],
            Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// 文件详情底部弹窗（数据来自 /file/info，extended 模式）
Future<void> showFileDetailSheet(
    BuildContext context, String uri, String name) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _FileDetailSheet(uri: uri, name: name),
  );
}

/// 文件详情内容
class _FileDetailSheet extends StatefulWidget {
  final String uri;
  final String name;

  const _FileDetailSheet({required this.uri, required this.name});

  @override
  State<_FileDetailSheet> createState() => _FileDetailSheetState();
}

class _FileDetailSheetState extends State<_FileDetailSheet> {
  Map<String, dynamic>? _info;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await FileApi.getFileInfo(widget.uri, extended: true);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e, '获取详情失败');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 高度受限 + 可滚动：任何类型 / 长路径 / 多元数据都不会溢出边界
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(pagePad, 12, pagePad, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      (_info?['type'] ?? 0) == 1
                          ? Icons.folder_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 3)),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(_error!,
                        style: TextStyle(fontSize: 13, color: AppColors.ink3)),
                  ),
                )
              else
                _buildDetails(_info!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(Map<String, dynamic> info) {
    final isDir = info['type'] == 1;
    final ext = widget.name.contains('.')
        ? widget.name.split('.').last.toUpperCase()
        : '';
    final rows = <(String, String)>[
      ('类型', isDir ? '文件夹' : (ext.isNotEmpty ? '$ext 文件' : '文件')),
      ('大小', formatBytes((info['size'] ?? 0) as int)),
      ('创建时间', _formatTime(info['created_at'])),
      ('修改时间', _formatTime(info['updated_at'])),
      ('路径', info['path']?.toString() ?? widget.uri),
      ('共享状态', info['shared'] == true ? '已分享' : '未分享'),
    ];
    // 扩展信息：上传者 / 存储策略（若有）
    final extInfo = info['extended_info'];
    if (extInfo is Map) {
      final entities = extInfo['entities'];
      if (entities is List && entities.isNotEmpty) {
        final first = entities.first;
        if (first is Map) {
          final cb = first['created_by'];
          if (cb is Map && cb['nickname'] != null) {
            rows.add(('上传者', cb['nickname'].toString()));
          }
        }
      }
      final sp = extInfo['storage_policy'];
      if (sp is Map && sp['name'] != null) {
        rows.add(('存储策略', sp['name'].toString()));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, value) in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(label,
                      style: TextStyle(fontSize: 13, color: AppColors.ink3)),
                ),
                Expanded(
                  child: Text(value,
                      style:
                          TextStyle(fontSize: 13.5, color: AppColors.ink)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// ISO8601 → 本地可读时间
  String _formatTime(Object? time) {
    if (time == null) return '-';
    final dt = DateTime.tryParse(time.toString());
    if (dt == null) return time.toString();
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}
