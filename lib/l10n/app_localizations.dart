import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'NiceRice'**
  String get appTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFilipino.
  ///
  /// In en, this message translates to:
  /// **'Filipino'**
  String get languageFilipino;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @selectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select a device'**
  String get selectDevice;

  /// No description provided for @unnamedDevice.
  ///
  /// In en, this message translates to:
  /// **'(Unnamed)'**
  String get unnamedDevice;

  /// No description provided for @connectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Connected: {name}'**
  String connectedLabel(String name);

  /// No description provided for @deviceBattery.
  ///
  /// In en, this message translates to:
  /// **'Device Battery'**
  String get deviceBattery;

  /// No description provided for @dryingChamber.
  ///
  /// In en, this message translates to:
  /// **'Drying Chamber'**
  String get dryingChamber;

  /// No description provided for @storageChamber.
  ///
  /// In en, this message translates to:
  /// **'Storage Chamber'**
  String get storageChamber;

  /// No description provided for @temperatureShort.
  ///
  /// In en, this message translates to:
  /// **'Temp'**
  String get temperatureShort;

  /// No description provided for @humidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get humidity;

  /// No description provided for @moisture.
  ///
  /// In en, this message translates to:
  /// **'Moisture'**
  String get moisture;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @disconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectTitle;

  /// No description provided for @disconnectBody.
  ///
  /// In en, this message translates to:
  /// **'You are about to disconnect from the current device.'**
  String get disconnectBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @bluetoothAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth flow is Android-only in this build.'**
  String get bluetoothAndroidOnly;

  /// No description provided for @bluetoothStillOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is still OFF.'**
  String get bluetoothStillOff;

  /// No description provided for @noDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No devices found nearby.'**
  String get noDevicesFound;

  /// No description provided for @deviceDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Device disconnected'**
  String get deviceDisconnected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name} ({addr})'**
  String connectedTo(String name, String addr);

  /// No description provided for @failedToConnect.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to {name}'**
  String failedToConnect(String name);

  /// No description provided for @bluetoothError.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth error: {error}'**
  String bluetoothError(String error);

  /// No description provided for @connectError.
  ///
  /// In en, this message translates to:
  /// **'Connect error: {error}'**
  String connectError(String error);

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {error}'**
  String unexpectedError(String error);

  /// No description provided for @bracketIdeal.
  ///
  /// In en, this message translates to:
  /// **'ideal harvest'**
  String get bracketIdeal;

  /// No description provided for @bracketLate.
  ///
  /// In en, this message translates to:
  /// **'late harvest (too dry)'**
  String get bracketLate;

  /// No description provided for @bracketEarly.
  ///
  /// In en, this message translates to:
  /// **'early harvest (too wet)'**
  String get bracketEarly;

  /// No description provided for @connectToHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to NiceRice on Home'**
  String get connectToHomeTitle;

  /// No description provided for @connectToHomeBody.
  ///
  /// In en, this message translates to:
  /// **'Before starting, please enable Bluetooth and connect to your NiceRice device from the Home page.'**
  String get connectToHomeBody;

  /// No description provided for @connectToHomeBodyAlt.
  ///
  /// In en, this message translates to:
  /// **'Bago magsimula, buksan ang Bluetooth at ikonekta ang NiceRice device sa Home page.'**
  String get connectToHomeBodyAlt;

  /// No description provided for @goToHome.
  ///
  /// In en, this message translates to:
  /// **'Go to Home'**
  String get goToHome;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @startSame.
  ///
  /// In en, this message translates to:
  /// **'Start same'**
  String get startSame;

  /// No description provided for @sessionPlan.
  ///
  /// In en, this message translates to:
  /// **'Session Plan'**
  String get sessionPlan;

  /// No description provided for @initialMoistureContent.
  ///
  /// In en, this message translates to:
  /// **'Initial Moisture Content'**
  String get initialMoistureContent;

  /// No description provided for @targetMoistureContent.
  ///
  /// In en, this message translates to:
  /// **'Target Moisture Content'**
  String get targetMoistureContent;

  /// No description provided for @targetLower.
  ///
  /// In en, this message translates to:
  /// **'target'**
  String get targetLower;

  /// No description provided for @temperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// No description provided for @estimatedTime.
  ///
  /// In en, this message translates to:
  /// **'Estimated time'**
  String get estimatedTime;

  /// No description provided for @completeInputsToEstimate.
  ///
  /// In en, this message translates to:
  /// **'Complete inputs to estimate time'**
  String get completeInputsToEstimate;

  /// No description provided for @estimating.
  ///
  /// In en, this message translates to:
  /// **'Estimating…'**
  String get estimating;

  /// No description provided for @atOrBelowTarget.
  ///
  /// In en, this message translates to:
  /// **'At/Below target'**
  String get atOrBelowTarget;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minutesShort;

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get hoursShort;

  /// No description provided for @initializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get initializing;

  /// No description provided for @waitForChamber.
  ///
  /// In en, this message translates to:
  /// **'Please wait for chamber to reach 45–70°C'**
  String get waitForChamber;

  /// No description provided for @targetTempRange.
  ///
  /// In en, this message translates to:
  /// **'Target: temperature between 45°C and 70°C'**
  String get targetTempRange;

  /// No description provided for @putGrainsNow.
  ///
  /// In en, this message translates to:
  /// **'You may now put your grains'**
  String get putGrainsNow;

  /// No description provided for @chamberReady.
  ///
  /// In en, this message translates to:
  /// **'Chamber is ready.'**
  String get chamberReady;

  /// No description provided for @startDrying.
  ///
  /// In en, this message translates to:
  /// **'Start Drying'**
  String get startDrying;

  /// No description provided for @sessionAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'A session is already running.'**
  String get sessionAlreadyRunning;

  /// No description provided for @unableToComputeEta.
  ///
  /// In en, this message translates to:
  /// **'Unable to compute estimated time.'**
  String get unableToComputeEta;

  /// No description provided for @dryingStarted.
  ///
  /// In en, this message translates to:
  /// **'Drying started'**
  String get dryingStarted;

  /// No description provided for @targetReachedEnded.
  ///
  /// In en, this message translates to:
  /// **'Target reached • Session ended'**
  String get targetReachedEnded;

  /// No description provided for @noPreviousSettings.
  ///
  /// In en, this message translates to:
  /// **'No previous settings found.'**
  String get noPreviousSettings;

  /// No description provided for @startNewSession.
  ///
  /// In en, this message translates to:
  /// **'Start New Session'**
  String get startNewSession;

  /// No description provided for @startNewSessionBody.
  ///
  /// In en, this message translates to:
  /// **'Start a new session using the previous settings?'**
  String get startNewSessionBody;

  /// No description provided for @usePreviousSettings.
  ///
  /// In en, this message translates to:
  /// **'Use previous settings'**
  String get usePreviousSettings;

  /// No description provided for @sessionTimer.
  ///
  /// In en, this message translates to:
  /// **'Session Timer'**
  String get sessionTimer;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get running;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get idle;

  /// No description provided for @toTarget.
  ///
  /// In en, this message translates to:
  /// **'to {target}% MC'**
  String toTarget(Object target);

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @stopSession.
  ///
  /// In en, this message translates to:
  /// **'Stop Session'**
  String get stopSession;

  /// No description provided for @stopSessionBody.
  ///
  /// In en, this message translates to:
  /// **'You are about to stop the current session.'**
  String get stopSessionBody;

  /// No description provided for @safetyStop.
  ///
  /// In en, this message translates to:
  /// **'Safety stop triggered by device'**
  String get safetyStop;

  /// No description provided for @tip_9_9_5.
  ///
  /// In en, this message translates to:
  /// **'9–9.5% • good for long-term seed preservation'**
  String get tip_9_9_5;

  /// No description provided for @tip_10_11_5.
  ///
  /// In en, this message translates to:
  /// **'10–11.5% • good for short-term seed preservation'**
  String get tip_10_11_5;

  /// No description provided for @tip_12_12_5.
  ///
  /// In en, this message translates to:
  /// **'12–12.5% • for storage beyond 3 months'**
  String get tip_12_12_5;

  /// No description provided for @tip_13_14.
  ///
  /// In en, this message translates to:
  /// **'13–14% • for storage within 2–3 months (recommended for milling)'**
  String get tip_13_14;

  /// No description provided for @tip_selectTarget.
  ///
  /// In en, this message translates to:
  /// **'Select a target moisture content (9–14%)'**
  String get tip_selectTarget;

  /// No description provided for @analytics_exportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get analytics_exportPdf;

  /// No description provided for @analytics_exportAnalyticsPdf.
  ///
  /// In en, this message translates to:
  /// **'Export Analytics PDF'**
  String get analytics_exportAnalyticsPdf;

  /// No description provided for @analytics_chooseSessions.
  ///
  /// In en, this message translates to:
  /// **'Choose which sessions to include.'**
  String get analytics_chooseSessions;

  /// No description provided for @analytics_currentSessionOnly.
  ///
  /// In en, this message translates to:
  /// **'Current session only'**
  String get analytics_currentSessionOnly;

  /// No description provided for @analytics_selectSessions.
  ///
  /// In en, this message translates to:
  /// **'Select sessions…'**
  String get analytics_selectSessions;

  /// No description provided for @analytics_generatePdf.
  ///
  /// In en, this message translates to:
  /// **'Generate PDF'**
  String get analytics_generatePdf;

  /// No description provided for @analytics_renameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get analytics_renameSession;

  /// No description provided for @analytics_sessionName.
  ///
  /// In en, this message translates to:
  /// **'Session name'**
  String get analytics_sessionName;

  /// No description provided for @common_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get common_cancel;

  /// No description provided for @common_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get common_save;

  /// No description provided for @analytics_reportTitle.
  ///
  /// In en, this message translates to:
  /// **'NiceRice Session Report'**
  String get analytics_reportTitle;

  /// No description provided for @analytics_environmentIfAvailable.
  ///
  /// In en, this message translates to:
  /// **'Environment (if available)'**
  String get analytics_environmentIfAvailable;

  /// No description provided for @analytics_notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get analytics_notes;

  /// No description provided for @analytics_notesBody.
  ///
  /// In en, this message translates to:
  /// **'Generated by NiceRice Analytics. This summary includes target, preset, intended use, duration, and basic statistics.'**
  String get analytics_notesBody;

  /// No description provided for @analytics_targetMoistureContent.
  ///
  /// In en, this message translates to:
  /// **'Target Moisture Content'**
  String get analytics_targetMoistureContent;

  /// No description provided for @analytics_presetSelected.
  ///
  /// In en, this message translates to:
  /// **'Preset Selected'**
  String get analytics_presetSelected;

  /// No description provided for @analytics_intendedUse.
  ///
  /// In en, this message translates to:
  /// **'Intended Use'**
  String get analytics_intendedUse;

  /// No description provided for @analytics_estimatedMoistureLoss.
  ///
  /// In en, this message translates to:
  /// **'Estimated Moisture Loss'**
  String get analytics_estimatedMoistureLoss;

  /// No description provided for @analytics_started.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get analytics_started;

  /// No description provided for @analytics_ended.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get analytics_ended;

  /// No description provided for @analytics_durationInitCooldown.
  ///
  /// In en, this message translates to:
  /// **'Duration (incl. init & cooldown)'**
  String get analytics_durationInitCooldown;

  /// No description provided for @analytics_estDefault.
  ///
  /// In en, this message translates to:
  /// **'~3–5% (est.)'**
  String get analytics_estDefault;

  /// No description provided for @analytics_estAbbrev.
  ///
  /// In en, this message translates to:
  /// **'(est.)'**
  String get analytics_estAbbrev;

  /// No description provided for @analytics_temperatureAvgRange.
  ///
  /// In en, this message translates to:
  /// **'Temperature (avg / range)'**
  String get analytics_temperatureAvgRange;

  /// No description provided for @analytics_humidityAvgRange.
  ///
  /// In en, this message translates to:
  /// **'Humidity (avg / range)'**
  String get analytics_humidityAvgRange;

  /// No description provided for @analytics_environment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get analytics_environment;

  /// No description provided for @analytics_noEnvData.
  ///
  /// In en, this message translates to:
  /// **'No temperature/humidity data'**
  String get analytics_noEnvData;

  /// No description provided for @analytics_noEnvDataForSession.
  ///
  /// In en, this message translates to:
  /// **'No temperature/humidity data for this session.'**
  String get analytics_noEnvDataForSession;

  /// No description provided for @analytics_emptyHistory.
  ///
  /// In en, this message translates to:
  /// **'No completed operations yet.\nRun one in Automation to build history.'**
  String get analytics_emptyHistory;

  /// No description provided for @analytics_noSessionsForFilter.
  ///
  /// In en, this message translates to:
  /// **'No sessions for selected filter.'**
  String get analytics_noSessionsForFilter;

  /// No description provided for @analytics_tempHumOverview.
  ///
  /// In en, this message translates to:
  /// **'Temperature & Humidity Overview'**
  String get analytics_tempHumOverview;

  /// No description provided for @analytics_interpretation.
  ///
  /// In en, this message translates to:
  /// **'Interpretation'**
  String get analytics_interpretation;

  /// No description provided for @analytics_initialMoisture.
  ///
  /// In en, this message translates to:
  /// **'Initial Moisture'**
  String get analytics_initialMoisture;

  /// No description provided for @analytics_targetMoisture.
  ///
  /// In en, this message translates to:
  /// **'Target Moisture'**
  String get analytics_targetMoisture;

  /// No description provided for @analytics_notEnoughData.
  ///
  /// In en, this message translates to:
  /// **'Not enough data for interpretation.'**
  String get analytics_notEnoughData;

  /// No description provided for @analytics_mcDropped.
  ///
  /// In en, this message translates to:
  /// **'Moisture content dropped from {from}% to {to}% in {duration}.'**
  String analytics_mcDropped(String from, String to, String duration);

  /// No description provided for @analytics_mcRose.
  ///
  /// In en, this message translates to:
  /// **'Moisture content rose from {from}% to {to}% in {duration}.'**
  String analytics_mcRose(String from, String to, String duration);

  /// No description provided for @analytics_mcStayed.
  ///
  /// In en, this message translates to:
  /// **'Moisture content stayed at {value}% for {duration}.'**
  String analytics_mcStayed(String value, String duration);

  /// No description provided for @analytics_sessionSummary.
  ///
  /// In en, this message translates to:
  /// **'Drying Speed'**
  String get analytics_sessionSummary;

  /// No description provided for @analytics_start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get analytics_start;

  /// No description provided for @analytics_end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get analytics_end;

  /// No description provided for @analytics_duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get analytics_duration;

  /// No description provided for @analytics_points.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get analytics_points;

  /// No description provided for @analytics_average.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get analytics_average;

  /// No description provided for @analytics_min.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get analytics_min;

  /// No description provided for @analytics_max.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get analytics_max;

  /// No description provided for @filters_today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get filters_today;

  /// No description provided for @filters_yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get filters_yesterday;

  /// No description provided for @filters_last3.
  ///
  /// In en, this message translates to:
  /// **'Last 3 days'**
  String get filters_last3;

  /// No description provided for @filters_last7.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get filters_last7;

  /// No description provided for @tooltip_renameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get tooltip_renameSession;

  /// No description provided for @analytics_renameSaved.
  ///
  /// In en, this message translates to:
  /// **'Session name updated.'**
  String get analytics_renameSaved;

  /// No description provided for @analytics_renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save name to the database. Keeping the name locally on this device.'**
  String get analytics_renameFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fil':
      return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
