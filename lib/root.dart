import 'package:dictionarylib/common.dart';
import 'package:dictionarylib/entry_types.dart';
import 'package:dictionarylib/page_entry_list.dart';
import 'package:dictionarylib/page_entry_list_overview.dart';
import 'package:dictionarylib/page_flashcards_landing.dart';
import 'package:dictionarylib/page_search.dart';
import 'package:dictionarylib/page_settings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dictionarylib/dictionarylib.dart' show DictLibLocalizations;

import 'common.dart';
import 'flashcards_landing_page.dart';
import 'legal_information.dart';

const SEARCH_ROUTE = "/search";
const LISTS_ROUTE = "/lists";
const REVISION_ROUTE = "/revision";
const SETTINGS_ROUTE = "/settings";

late Locale systemLocale;

class RootApp extends StatefulWidget {
  const RootApp({super.key, required this.startingLocale});

  final Locale startingLocale;

  @override
  _RootAppState createState() => _RootAppState(locale: startingLocale);

  static void applyLocaleOverride(BuildContext context, Locale newLocale) {
    _RootAppState state = context.findAncestorStateOfType<_RootAppState>()!;

    state.setState(() {
      state.locale = newLocale;
    });
  }

  static void clearLocaleOverride(BuildContext context) {
    _RootAppState state = context.findAncestorStateOfType<_RootAppState>()!;

    state.setState(() {
      state.locale = systemLocale;
    });
  }
}

class _RootAppState extends State<RootApp> {
  _RootAppState({required this.locale});

  Locale locale;

  final GoRouter router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: SEARCH_ROUTE,
      routes: [
        GoRoute(
          path: "/",
          redirect: (context, state) => SEARCH_ROUTE,
        ),
        GoRoute(
            path: SEARCH_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              String? initialQuery = state.queryParams["query"];
              bool navigateToFirstMatch =
                  state.queryParams["navigate_to_first_match"] == "true";
              return NoTransitionPage(
                  // https://stackoverflow.com/a/73458529/3846032
                  key: UniqueKey(),
                  child: SearchPage(
                    mainColor: MAIN_COLOR,
                    appBarDisabledColor: APP_BAR_DISABLED_COLOR,
                    navigateToEntryPage: navigateToEntryPage,
                    initialQuery: initialQuery,
                    navigateToFirstMatch: navigateToFirstMatch,
                    includeEntryTypeButton: false,
                  ));
            }),
        GoRoute(
            path: LISTS_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return NoTransitionPage(
                child: EntryListsOverviewPage(
                  mainColor: MAIN_COLOR,
                  appBarDisabledColor: APP_BAR_DISABLED_COLOR,
                  buildEntryListWidgetCallback: (entryList) => EntryListPage(
                    entryList: entryList,
                    mainColor: MAIN_COLOR,
                    appBarDisabledColor: APP_BAR_DISABLED_COLOR,
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
                mainColor: MAIN_COLOR,
                appBarDisabledColor: APP_BAR_DISABLED_COLOR,
              ));
            }),
        GoRoute(
            path: SETTINGS_ROUTE,
            pageBuilder: (BuildContext context, GoRouterState state) {
              return const NoTransitionPage(
                  child: SettingsPage(
                appName: APP_NAME,
                mainColor: MAIN_COLOR,
                appBarDisabledColor: APP_BAR_DISABLED_COLOR,
                additionalTopWidgets: [],
                buildLegalInformationChildren: buildLegalInformationChildren,
                reportDataProblemUrl: 'https://www.auslan.org.au/feedback/',
                reportAppProblemUrl:
                    'https://github.com/banool/auslan_dictionary/issues',
                iOSAppId: "1531368368",
                androidAppId: "com.banool.auslan_dictionary",
              ));
            }),
      ]);

  @override
  Widget build(BuildContext context) {
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
          localizationsDelegates: DictLibLocalizations.localizationsDelegates,
          supportedLocales: LANGUAGE_CODE_TO_LOCALE.values,
          locale: locale,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              appBarTheme: const AppBarTheme(
                backgroundColor: MAIN_COLOR,
                foregroundColor: Colors.white,
                actionsIconTheme: IconThemeData(color: Colors.white),
                iconTheme: IconThemeData(color: Colors.white),
              ),
              visualDensity: VisualDensity.adaptivePlatformDensity,
              // Make swiping to pop back the navigation work.
              pageTransitionsTheme: const PageTransitionsTheme(builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              })),
          routerConfig: router,
        ));
  }
}
