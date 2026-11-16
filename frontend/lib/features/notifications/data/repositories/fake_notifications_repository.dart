import 'package:clock/clock.dart';
import 'package:peerpass/features/notifications/data/models/notification_model.dart';
import 'package:peerpass/features/notifications/data/repositories/notifications_repository.dart';

/// In-memory stand-in for the notification endpoints.
///
/// What widget tests resolve, because a widget test has no server to talk to. It
/// implements the repository's shape rather than the datasource's, because that
/// is the seam a test cares about: overriding the repository is the only
/// composition the app supports.
///
/// It is a fake and not a stub: reading a notification really clears its unread
/// state, read-all really clears every row, and paging really slices the list.
/// A fake that returned whatever it was given would let a screen that never
/// clears a badge -- or clears the wrong rows -- pass.
class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository({List<AppNotification> notifications = const []})
    : _items = List<AppNotification>.of(notifications);

  final List<AppNotification> _items;

  /// Every id passed to [markRead], in order, so a test can assert the tap read
  /// the row it opened rather than a neighbour.
  final List<String> readIds = <String>[];

  /// How many times [markAllRead] was called.
  int markAllReadCalls = 0;

  /// The offset of every inbox page requested, in order.
  final List<int> inboxOffsets = <int>[];

  /// The notifications the fake currently holds, newest first.
  List<AppNotification> get notifications =>
      List<AppNotification>.unmodifiable(_items);

  /// Drops a new row at the top, the way the server would.
  ///
  /// Tests use it to represent something arriving while the app is already
  /// running, which is the case a cached list has to be asked about again.
  void arrive(AppNotification item) => _items.insert(0, item);

  @override
  Future<NotificationPage> inbox({int limit = 20, int offset = 0}) async {
    inboxOffsets.add(offset);
    final start = offset.clamp(0, _items.length);
    final end = (offset + limit).clamp(start, _items.length);
    return NotificationPage(
      items: List<AppNotification>.unmodifiable(_items.sublist(start, end)),
      total: _items.length,
      limit: limit,
      offset: offset,
      hasMore: end < _items.length,
    );
  }

  @override
  Future<int> unreadCount() async =>
      _items.where((item) => item.isUnread).length;

  @override
  Future<AppNotification> markRead(String notificationId) async {
    readIds.add(notificationId);
    final index = _items.indexWhere((item) => item.id == notificationId);
    if (index == -1) {
      throw StateError('No notification with id $notificationId.');
    }
    final updated = _items[index].markedRead(clock.now());
    _items[index] = updated;
    return updated;
  }

  @override
  Future<int> markAllRead() async {
    markAllReadCalls++;
    final now = clock.now();
    var marked = 0;
    for (var index = 0; index < _items.length; index++) {
      if (!_items[index].isUnread) continue;
      _items[index] = _items[index].markedRead(now);
      marked++;
    }
    return marked;
  }
}
