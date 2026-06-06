import 'dart:async';

import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/globals.dart';
import 'package:dictionarylib/page_entry_list.dart';
import 'package:dictionarylib/page_entry_list_overview.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/page_search.dart';
import 'package:dictionarylib/page_settings.dart';
import 'package:dictionarylib/sharing/deep_link_handler.dart';
import 'package:dictionarylib/sharing/shared_list_landing_page.dart';
import 'package:dictionarylib/theme.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'common.dart';
import 'entries_types.dart';
import 'flashcards_landing_page.dart';
import 'legal_information.dart';

/// Short plain-text preview of an entry's first definition, for the
/// "sign of the day" card on the search screen.
String? auslanDefinitionPreview(Entry entry) {
  if (entry is! MyEntry) return null;
  if (entry.subEntries.isEmpty) return null;
  final defs = entry.subEntries.first.definitions;
  if (defs.isEmpty) return null;
  final subdefs = defs.first.subdefinitions;
  if (subdefs == null || subdefs.isEmpty) return null;
  return subdefs.first;
}

const SEARCH_ROUTE = "/search";
const LISTS_ROUTE = "/lists";
const REVISION_ROUTE = "/revision";
const SETTINGS_ROUTE = "/settings";

// Debug-only launch overrides for testing a specific screen / theme without
// hand-editing this file (and risking leaving the edit in). They're set via
// --dart-define, default to empty when absent, and are ignored entirely
// outside debug builds — so the shipped app always boots to SEARCH_ROUTE with
// the user's persisted theme. Examples:
//   flutter run --dart-define=DEBUG_INITIAL_LOCATION='/search?query=dog&navigate_to_first_match=true'
//   flutter run --dart-define=DEBUG_THEME_VARIANT=classic --dart-define=DEBUG_THEME_MODE=dark
const String _kDebugInitialLocation =
    String.fromEnvironment('DEBUG_INITIAL_LOCATION');
const String _kDebugThemeVariant = String.fromEnvironment('DEBUG_THEME_VARIANT');
const String _kDebugThemeMode = String.fromEnvironment('DEBUG_THEME_MODE');

late Locale systemLocale;

class RootApp extends StatefulWidget {
  const RootApp({super.key, required this.startingLocale});

  final Locale startingLocale;

  @override
  State<RootApp> createState() => _RootAppState();

  static void applyLocaleOverride(BuildContext context, Locale newLocale) {
    _RootAppState state = context.findAncestorStateOfType<_RootAppState>()!;
    state._setLocale(newLocale);
  }

  static void clearLocaleOverride(BuildContext context) {
    _RootAppState state = context.findAncestorStateOfType<_RootAppState>()!;
    state._setLocale(systemLocale);
  }
}

class _RootAppState extends State<RootApp> {
  late Locale locale;

  void _setLocale(Locale newLocale) {
    setState(() {
      locale = newLocale;
    });
  }

  StreamSubscription<SharePayload>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    locale = widget.startingLocale;
    themeNotifier.value = ThemeMode.values[
        sharedPreferences.getInt(KEY_THEME_MODE) ?? ThemeMode.light.index];
    themeVariantNotifier.value =
        appThemeVariantFromName(sharedPreferences.getString(KEY_THEME_VARIANT));
    // Debug-only theme overrides (see _kDebug* consts above). No-ops in release
    // and when the corresponding --dart-define isn't set.
    if (kDebugMode && _kDebugThemeMode.isNotEmpty) {
      themeNotifier.value =
          _kDebugThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
    }
    if (kDebugMode && _kDebugThemeVariant.isNotEmpty) {
      themeVariantNotifier.value = appThemeVariantFromName(_kDebugThemeVariant);
    }
    // Forward incoming share deep-links to the share landing route. The
    // invite token (when present) is carried through as a query parameter
    // so the landing page can drive the accept-invite flow instead of the
    // anonymous subscribe.
    _deepLinkSub = sharing.deepLinks.payloads.listen((payload) {
      final loc = payload.isInvite
          ? '/share/${payload.listId}?invite=${Uri.encodeQueryComponent(payload.inviteToken!)}'
          : '/share/${payload.listId}';
      router.go(loc);
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  final GoRouter router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: kDebugMode && _kDebugInitialLocation.isNotEmpty
          ? _kDebugInitialLocation
          : SEARCH_ROUTE,
      routes: [
        GoRoute(
          path: "/",
          redirect: (context, state) => SEARCH_ROUTE,
        ),
        GoRoute(
            path: SEARCH_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              String? initialQuery = state.uri.queryParameters["query"];
              bool navigateToFirstMatch =
                  state.uri.queryParameters["navigate_to_first_match"] ==
                      "true";
              return NoTransitionPage(
                key: UniqueKey(),
                child: SearchPage(
                  navigateToEntryPage: navigateToEntryPage,
                  initialQuery: initialQuery,
                  navigateToFirstMatch: navigateToFirstMatch,
                  includeEntryTypeButton: false,
                  entryDefinitionPreview: auslanDefinitionPreview,
                ),
              );
            }),
        GoRoute(
            path: LISTS_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return NoTransitionPage(
                child: EntryListsOverviewPage(
                  buildEntryListWidgetCallback: (entryList) => EntryListPage(
                    entryList: entryList,
                    navigateToEntryPage: navigateToEntryPage,
                  ),
                ),
              );
            }),
        GoRoute(
            path: REVISION_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              var controller = MyFlashcardsLandingPageController();
              return NoTransitionPage(
                  child: FlashcardsLandingPage(
                controller: controller,
              ));
            }),
        GoRoute(
            path: '/share/:listId',
            pageBuilder: (BuildContext context, GoRouterState state) {
              final id = state.pathParameters['listId']!;
              final invite = state.uri.queryParameters['invite'];
              // Stable key per (listId, inviteToken) so re-tapping the
              // same share link doesn't tear down + rebuild the page
              // (which would re-trigger subscribe / sign-in). Different
              // links still get distinct keys so navigation between
              // shares mounts a fresh page.
              return NoTransitionPage(
                key: ValueKey('share-$id-${invite ?? ''}'),
                child: SharedListLandingPage(
                  listId: id,
                  inviteToken:
                      invite != null && invite.isNotEmpty ? invite : null,
                  navigateToEntryPage: navigateToEntryPage,
                ),
              );
            }),
        GoRoute(
            path: SETTINGS_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return const NoTransitionPage(
                  child: SettingsPage(
                appName: APP_NAME,
                additionalTopWidgets: [],
                buildLegalInformationChildren: buildLegalInformationChildren,
                reportDataProblemUrl: 'https://www.auslan.org.au/feedback/',
                reportAppProblemUrl:
                    'https://github.com/banool/auslan_dictionary/issues',
                iOSAppId: IOS_APP_ID,
                androidAppId: ANDROID_APP_ID,
                showPrivacyPolicy: false,
              ));
            }),
      ]);

  @override
  Widget build(BuildContext context) {
    // Outer listener: the light/dark mode. Inner listener: which visual style
    // ("theme variant") to build, e.g. Hearth or Classic. Both themes are
    // built by the shared library so all the theming lives in one place.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return ValueListenableBuilder<AppThemeVariant>(
          valueListenable: themeVariantNotifier,
          builder: (context, themeVariant, child) {
            return GestureDetector(
                onTap: () {
                  FocusScopeNode currentFocus = FocusScope.of(context);
                  if (!currentFocus.hasPrimaryFocus &&
                      currentFocus.focusedChild != null) {
                    FocusManager.instance.primaryFocus!.unfocus();
                  }
                },
                child: MaterialApp.router(
                  title: APP_NAME,
                  onGenerateTitle: (context) => APP_NAME,
                  localizationsDelegates:
                      DictLibLocalizations.localizationsDelegates,
                  supportedLocales: LANGUAGE_CODE_TO_LOCALE.values,
                  locale: locale,
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode,
                  theme: buildAppTheme(
                    variant: themeVariant,
                    brightness: Brightness.light,
                    classicSeed: MAIN_COLOR,
                  ),
                  darkTheme: buildAppTheme(
                    variant: themeVariant,
                    brightness: Brightness.dark,
                    classicSeed: MAIN_COLOR,
                  ),
                  routerConfig: router,
                ));
          },
        );
      },
    );
  }
}
