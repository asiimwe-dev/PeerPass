import 'package:flutter/foundation.dart';

/// One page of a larger result set.
///
/// Every list endpoint returns this shape, including the tutor matches screen.
/// [hasMore] is derived rather than requested so that a screen cannot disagree
/// with the pager about whether a next page exists.
@immutable
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  const Paginated.empty() : items = const [], page = 1, pageSize = 0, total = 0;

  final List<T> items;

  /// One-based page number, matching the API's own numbering.
  final int page;

  final int pageSize;

  /// The total number of matching records, which may exceed `items.length`.
  final int total;

  /// Whether a further page can be requested.
  bool get hasMore => page * pageSize < total;

  /// Whether this page carries no records.
  bool get isEmpty => items.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Paginated<T> &&
          other.page == page &&
          other.pageSize == pageSize &&
          other.total == total &&
          listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(page, pageSize, total, Object.hashAll(items));

  @override
  String toString() => 'Paginated(page $page, ${items.length} of $total)';
}
