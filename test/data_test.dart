import 'package:auslan_dictionary/entries_loader.dart';
import 'package:dictionarylib/dictionarylib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  SharedPreferences.setMockInitialValues({});
  sharedPreferences = await SharedPreferences.getInstance();

  // Test that we can load the local data correctly.
  test('Data loads correctly', () async {
    // Read the data from disk.
    final file = File('assets/data/data.json');
    final data = await file.readAsString();

    // Confirm the loader can load it.
    MyEntryLoader myEntryLoader = MyEntryLoader();
    var entries = myEntryLoader.loadEntriesInner(data);

    // Confirm the loader can set the global entries.
    myEntryLoader.setEntriesGlobal(entries);

    // Confirm there are global entries and the community list manager is
    // populated.
    expect(keyedByEnglishEntriesGlobal.length, greaterThan(0));

    // Confirm the community list manager is populated.
    expect(communityEntryListManager.getEntryLists().length, greaterThan(0));
  });
}
