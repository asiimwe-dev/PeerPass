import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// Constrains a page's content to a readable width.
///
/// Applied by the app shell rather than per screen. The pilot is mobile-first,
/// so on a phone this is a no-op; on the web target and on tablets it stops a
/// form or a list from stretching into unreadable line lengths. The background
/// still fills the viewport so the layout does not look broken when wide.
class ContentWidthLimiter extends StatelessWidget {
  const ContentWidthLimiter({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDimens.maxContentWidth),
        child: child,
      ),
    );
  }
}
