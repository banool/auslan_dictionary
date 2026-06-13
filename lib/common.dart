import 'package:dictionarylib/entry_list.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/saved_video.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'word_page.dart';

const String APP_NAME = "Auslan Dictionary";

const MaterialColor MAIN_COLOR = Colors.blue;

const String IOS_APP_ID = "1531368368";
const String ANDROID_APP_ID = "com.banool.auslan_dictionary";

/// Route path for an entry page. The entry's key (its English phrase) is the
/// `:key` path segment; `?variation=N&video=M` optionally deep-link to a
/// specific sub-entry / video within it.
const String WORD_ROUTE = "/word";

/// Non-URL-serialisable args carried to the [WORD_ROUTE] page by an in-app
/// navigation (the entry object is re-resolved from the URL key, but these
/// can't be). Absent on a cold deep link, where the route falls back to
/// sensible defaults (full UI, no focused video, no save-to-list target).
class EntryPageArgs {
  const EntryPageArgs({
    this.showFavouritesButton = true,
    this.focusVideo,
    this.saveToList,
  });

  final bool showFavouritesButton;
  final SavedVideo? focusVideo;
  final EntryList? saveToList;
}

/// Open an entry. Pushes a real `/word/<key>` route so the URL reflects the
/// entry and it's deep-linkable on web (a pasted link resolves the entry from
/// the key). Mobile is unaffected — URLs are simply invisible there. The
/// non-serialisable bits ride along as `extra`.
Future<void> navigateToEntryPage(
    BuildContext context, Entry entry, bool showFavouritesButton,
    {SavedVideo? focusVideo, EntryList? saveToList}) async {
  // Web: push a real /word/<key> go_router route so the URL reflects the entry
  // and it's deep-linkable. Native: keep the proven imperative push — URLs are
  // invisible there anyway, and going through go_router would clobber a
  // raw-pushed parent (e.g. the list view) and break its back button.
  if (kIsWeb) {
    await context.push(
      "$WORD_ROUTE/${Uri.encodeComponent(entry.getKey())}",
      extra: EntryPageArgs(
        showFavouritesButton: showFavouritesButton,
        focusVideo: focusVideo,
        saveToList: saveToList,
      ),
    );
  } else {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntryPage(
            entry: entry,
            showFavouritesButton: showFavouritesButton,
            focusVideo: focusVideo,
            saveToList: saveToList),
      ),
    );
  }
}
