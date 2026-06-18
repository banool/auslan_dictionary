import 'package:auslan_dictionary/entries_types.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:flutter_test/flutter_test.dart';

// Auslan has no per-video versioning. The shared word page's Current/Historical
// status pill is gated on MediaItem.hasStatus, so as long as Auslan's
// getMediaItems() never attaches a status, the pill can never appear. This
// guards that invariant directly (headless + deterministic), complementing the
// SLSL versioning test that covers the pill-shows path.

void main() {
  test('Auslan getMediaItems attaches no status, so the pill stays hidden', () {
    final sub = MySubEntry(
      keywords: const ['auslan test word'],
      videoLinksInner: const [
        '/mp4video/11/11450.mp4',
        '/mp4video/11/11451.mp4',
      ],
      definitions: const [],
      regions: const [Region.EVERYWHERE],
      index: 0,
    );

    final items = sub.getMediaItems();

    // Paths still come through unchanged (saved-video identity is preserved).
    expect(items.map((e) => e.path).toList(),
        ['/mp4video/11/11450.mp4', '/mp4video/11/11451.mp4']);
    expect(items.map((e) => e.path).toList(), sub.getMedia());

    // The key invariant: no status, no details -> no pill, no source sheet.
    for (final item in items) {
      expect(item.status, isNull);
      expect(item.hasStatus, isFalse);
      expect(item.hasDetails, isFalse);
    }
  });
}
