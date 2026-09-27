import 'package:flutter_test/flutter_test.dart';
import 'package:ulearn/core/models/paginated.dart';

void main() {
  group('Paginated.hasMore', () {
    test('is true while further pages remain', () {
      const page = Paginated<String>(
        items: ['a', 'b'],
        page: 1,
        pageSize: 2,
        total: 5,
      );

      expect(page.hasMore, isTrue);
    });

    test('is false once the last item is on the page', () {
      const page = Paginated<String>(
        items: ['a', 'b'],
        page: 3,
        pageSize: 2,
        total: 6,
      );

      expect(page.hasMore, isFalse);
    });

    test('is false for an empty result set', () {
      const page = Paginated<String>.empty();

      expect(page.hasMore, isFalse);
      expect(page.isEmpty, isTrue);
    });
  });

  group('Paginated.empty', () {
    test('starts at the first page with no records', () {
      const page = Paginated<int>.empty();

      expect(page.page, 1);
      expect(page.pageSize, 0);
      expect(page.total, 0);
    });
  });

  test('compares by value, so a rebuilt page does not appear changed', () {
    const first = Paginated<String>(
      items: ['a'],
      page: 1,
      pageSize: 1,
      total: 1,
    );
    const second = Paginated<String>(
      items: ['a'],
      page: 1,
      pageSize: 1,
      total: 1,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('differs when the total differs', () {
    const first = Paginated<String>(
      items: ['a'],
      page: 1,
      pageSize: 1,
      total: 1,
    );
    const second = Paginated<String>(
      items: ['a'],
      page: 1,
      pageSize: 1,
      total: 2,
    );

    expect(first, isNot(second));
  });
}
