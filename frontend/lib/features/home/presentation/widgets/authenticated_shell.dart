import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:peerpass/app/router.dart';

class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({
    required this.child,
    required this.selectedIndex,
    super.key,
  });

  final Widget child;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final destinations = [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Sessions',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ];
        return Scaffold(
          body: Row(
            children: [
              if (wide) ...[
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => _navigate(context, index),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: child),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => _navigate(context, index),
                  destinations: destinations,
                ),
        );
      },
    );
  }

  void _navigate(BuildContext context, int index) {
    final route = switch (index) {
      0 => AppRoutes.home,
      1 => AppRoutes.sessions,
      _ => AppRoutes.profile,
    };
    context.go(route);
  }
}
