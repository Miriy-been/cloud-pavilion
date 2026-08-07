import 'package:flutter/material.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/page/index/account.dart';
import 'package:flutter_application_2/page/index/category.dart';
import 'package:flutter_application_2/page/index/download.dart';
import 'package:flutter_application_2/page/index/index.dart';
import 'package:flutter_application_2/util/UpdateChecker.dart';

/// 底部通栏导航：纯白底色，选中态柔和浅蓝圆角按钮
class Bottom extends StatefulWidget {
  Bottom({super.key});

  @override
  State<Bottom> createState() => _BottomState();
}

class _BottomState extends State<Bottom> {
  // 页面控制器
  PageController _pageController = PageController();
  var _selectedIndex = 0;
  // 多选模式下隐藏底部导航，避免双层底栏
  bool _hideNav = false;
  // 进入「用户」页次数（用于重播容量卡入场动画）
  int _accountTick = 0;

  @override
  void initState() {
    super.initState();
    // 启动后静默检查更新（24h 冷却，失败不打扰）
    UpdateChecker.check(context: context);
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建底部导航与三个 Tab
    Theme.of(context);
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: [
          Index(onSelectionChanged: _onSelectionChanged),
          const CategoryPage(),
          Download(),
          Account(replayTick: _accountTick),
        ],
      ),
      bottomNavigationBar: _hideNav
          ? null
          : Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 24,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      _NavItem(
                        icon: Icons.cloud_outlined,
                        label: '存储',
                        active: _selectedIndex == 0,
                        onTap: () => _switch(0),
                      ),
                      _NavItem(
                        icon: Icons.category_outlined,
                        label: '分类',
                        active: _selectedIndex == 1,
                        onTap: () => _switch(1),
                      ),
                      _NavItem(
                        icon: Icons.import_export,
                        label: '传输',
                        active: _selectedIndex == 2,
                        onTap: () => _switch(2),
                      ),
                      _NavItem(
                        icon: Icons.account_circle_outlined,
                        label: '用户',
                        active: _selectedIndex == 3,
                        onTap: () => _switch(3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// 存储页多选状态变化时隐藏/显示底部导航
  void _onSelectionChanged(bool selected) {
    if (mounted) setState(() => _hideNav = selected);
  }

  /// 页面切换回调：同步选中态，并在进入「用户」页时递增重播计数
  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 3) _accountTick++;
    });
  }

  void _switch(int index) {
    setState(() => _selectedIndex = index);
    // 直接跳转到目标页，跳过中间页面遍历，避免逐页滑动卡顿
    _pageController.jumpToPage(index);
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? _activeIcon : icon,
                size: 22,
                color: active ? AppColors.primary : const Color(0xFF868686),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: active ? AppColors.primary : const Color(0xFF868686),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _activeIcon {
    switch (icon) {
      case Icons.cloud_outlined:
        return Icons.cloud;
      case Icons.category_outlined:
        return Icons.category;
      case Icons.import_export:
        return Icons.import_export;
      default:
        return Icons.account_circle;
    }
  }
}
