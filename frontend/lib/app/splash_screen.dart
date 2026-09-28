import 'package:flutter/material.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// Shown while stored tokens are checked on cold start.
///
/// The router holds the app here until the auth status resolves, so this appears
/// on every launch. It exists to avoid a flash of the wrong screen: a returning
/// tutor would otherwise see sign-in for a frame before landing on home, which
/// reads as being logged out. On the pilot's metered connections a brief blank
/// screen is indistinguishable from a broken app.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PeerPass', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppDimens.xl),
            const CircularProgressIndicator.adaptive(),
          ],
        ),
      ),
    );
  }
}
