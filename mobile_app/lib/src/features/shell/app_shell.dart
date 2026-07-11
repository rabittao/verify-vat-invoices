import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_layout.dart';
import '../../core/theme/app_palette.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.location,
    required this.child,
    super.key,
  });

  static const double _floatingNavHeight = 112;

  final String location;
  final Widget child;

  int get currentIndex {
    if (location.startsWith('/ledger')) {
      return 1;
    }
    if (location.startsWith('/settings')) {
      return 2;
    }
    return 0;
  }

  bool get showBottomNavigation {
    final path = Uri.tryParse(location)?.path ?? location;
    return path == '/tasks' || path == '/ledger' || path == '/settings';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showNav = showBottomNavigation;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppPalette.pageGradient,
        ),
        child: Stack(
          children: [
            Positioned(
              top: -72,
              right: -32,
              child: _ShellAccentOrb(
                size: 182,
                color: AppPalette.sky.withValues(alpha: 0.35),
              ),
            ),
            Positioned(
              top: 148,
              left: -56,
              child: _ShellAccentOrb(
                size: 138,
                color: AppPalette.primarySoft.withValues(alpha: 0.72),
              ),
            ),
            Positioned.fill(
              bottom: showNav ? _floatingNavHeight : 0,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = constraints.maxWidth.clamp(
                    0.0,
                    AppLayout.desktopContentMaxWidth,
                  );
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: contentWidth,
                      height: constraints.maxHeight,
                      child: child,
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: showNav
                    ? Center(
                        key: const ValueKey('root-nav'),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 560,
                          ),
                          child: SafeArea(
                            top: false,
                            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                            child: SizedBox(
                              height: 78,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.shadow.withValues(
                                        alpha: 0.08,
                                      ),
                                      blurRadius: 30,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(26),
                                  child: NavigationBar(
                                    height: 78,
                                    backgroundColor: Colors.transparent,
                                    selectedIndex: currentIndex,
                                    onDestinationSelected: (index) {
                                      switch (index) {
                                        case 0:
                                          context.go('/tasks');
                                          break;
                                        case 1:
                                          context.go('/ledger');
                                          break;
                                        case 2:
                                          context.go('/settings');
                                          break;
                                      }
                                    },
                                    destinations: const [
                                      NavigationDestination(
                                        icon: Icon(Icons.dashboard_outlined),
                                        selectedIcon:
                                            Icon(Icons.dashboard_rounded),
                                        label: '任务',
                                      ),
                                      NavigationDestination(
                                        icon: Icon(Icons.receipt_long_outlined),
                                        selectedIcon:
                                            Icon(Icons.receipt_long_rounded),
                                        label: '台账',
                                      ),
                                      NavigationDestination(
                                        icon: Icon(Icons.settings_outlined),
                                        selectedIcon:
                                            Icon(Icons.settings_rounded),
                                        label: '设置',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-nav')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellAccentOrb extends StatelessWidget {
  const _ShellAccentOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
