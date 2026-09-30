import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// Placeholder for a screen whose content has not arrived yet.
///
/// Centred and shrink-wrapped so it can be dropped in as a direct child of a
/// [Scaffold] body.
class LoadingView extends StatelessWidget {
  const LoadingView({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator.adaptive(),
            if (message case final text?) ...[
              const SizedBox(height: AppDimens.md),
              Text(text, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
