import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peerpass/app/widgets/splash_morph.dart';
import 'package:peerpass/core/constants/app_dimens.dart';
import 'package:peerpass/core/error/failures.dart';
import 'package:peerpass/core/state/session.dart';
import 'package:peerpass/features/auth/presentation/providers/auth_providers.dart';

/// Shown while stored tokens are checked on cold start.
///
/// The router holds the app here until the auth status resolves, so this appears
/// on every launch. It exists to avoid a flash of the wrong screen: a returning
/// tutor would otherwise see sign-in for a frame before landing on home, which
/// reads as being logged out. On the pilot's metered connections a brief blank
/// screen is indistinguishable from a broken app.
///
/// It is also the one place a failed cold-start check can be acted on. A dropped
/// connection leaves the status unknown, which keeps the router here, so without a
/// retry here a student on a bad connection would have no way forward but
/// force-quitting the app.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(sessionControllerProvider).restoreFailure;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PeerPass', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppDimens.xl),
            if (failure == null) ...[
              const SplashMorph(),
              const SizedBox(height: AppDimens.lg),
              const CircularProgressIndicator.adaptive(),
            ] else ...[
              // The mark stops and the failure is stated. Running the animation
              // here would imply progress that is not being made.
              const Icon(Icons.cloud_off_outlined, size: 44),
              const SizedBox(height: AppDimens.lg),
              Text(
                _messageFor(failure),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppDimens.xl),
              FilledButton(
                onPressed: () => ref.read(authControllerProvider).retryRestore(),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What to say, by cause.
///
/// Deliberately says nothing about the exception behind the failure. The student
/// is told what is wrong and what to do; a socket error string or a stack
/// fragment on a cold-start screen tells them nothing actionable and leaks
/// infrastructure detail.
String _messageFor(Failure failure) => switch (failure) {
  NetworkFailure() =>
    'Could not reach PeerPass. Check your connection and try again.',
  _ => 'Something went wrong. Try again.',
};
