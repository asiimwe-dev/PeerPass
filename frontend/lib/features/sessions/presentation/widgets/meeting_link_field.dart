import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerpass/core/constants/app_dimens.dart';

/// The meeting link, as a value the student can take away with them.
///
/// Copyable rather than tappable because the app ships nothing that opens a
/// browser, and adding a dependency for it is not worth it in a release whose
/// agreed substitute for in-app chat is handing the value over by hand. The
/// select-and-copy fallback is not a consolation prize: it works on a device with
/// no browser at all, which is the case a student in a lecture theatre is in.
///
/// Confirmation is deliberate. Copying silently leaves a student who taps the
/// button unable to tell whether it worked, and the only way they find out is
/// pasting the wrong thing into the meeting they are trying to join.
class MeetingLinkField extends StatelessWidget {
  const MeetingLinkField({required this.link, super.key});

  final String link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Meeting link', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppDimens.xs),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                link,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: 'Copy meeting link',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => _copy(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meeting link copied')),
    );
  }
}
