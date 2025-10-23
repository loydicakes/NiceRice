// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NiceRice';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFilipino => 'Filipino';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get selectDevice => 'Select a device';

  @override
  String get unnamedDevice => '(Unnamed)';

  @override
  String connectedLabel(String name) {
    return 'Connected: $name';
  }

  @override
  String get deviceBattery => 'Device Battery';

  @override
  String get dryingChamber => 'Drying Chamber';

  @override
  String get storageChamber => 'Storage Chamber';

  @override
  String get temperatureShort => 'Temp';

  @override
  String get humidity => 'Humidity';

  @override
  String get moisture => 'Moisture';

  @override
  String get status => 'Status';

  @override
  String get disconnectTitle => 'Disconnect';

  @override
  String get disconnectBody =>
      'You are about to disconnect from the current device.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get bluetoothAndroidOnly =>
      'Bluetooth flow is Android-only in this build.';

  @override
  String get bluetoothStillOff => 'Bluetooth is still OFF.';

  @override
  String get noDevicesFound => 'No devices found nearby.';

  @override
  String get deviceDisconnected => 'Device disconnected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String connectedTo(String name, String addr) {
    return 'Connected to $name ($addr)';
  }

  @override
  String failedToConnect(String name) {
    return 'Failed to connect to $name';
  }

  @override
  String bluetoothError(String error) {
    return 'Bluetooth error: $error';
  }

  @override
  String connectError(String error) {
    return 'Connect error: $error';
  }

  @override
  String unexpectedError(String error) {
    return 'Unexpected error: $error';
  }

  @override
  String get bracketIdeal => 'ideal harvest';

  @override
  String get bracketLate => 'late harvest (too dry)';

  @override
  String get bracketEarly => 'early harvest (too wet)';

  @override
  String get connectToHomeTitle => 'Connect to NiceRice on Home';

  @override
  String get connectToHomeBody =>
      'Before starting, please enable Bluetooth and connect to your NiceRice device from the Home page.';

  @override
  String get connectToHomeBodyAlt =>
      'Bago magsimula, buksan ang Bluetooth at ikonekta ang NiceRice device sa Home page.';

  @override
  String get goToHome => 'Go to Home';

  @override
  String get start => 'Start';

  @override
  String get startSame => 'Start same';

  @override
  String get sessionPlan => 'Session Plan';

  @override
  String get initialMoistureContent => 'Initial Moisture Content';

  @override
  String get targetMoistureContent => 'Target Moisture Content';

  @override
  String get targetLower => 'target';

  @override
  String get temperature => 'Temperature';

  @override
  String get estimatedTime => 'Estimated time';

  @override
  String get completeInputsToEstimate => 'Complete inputs to estimate time';

  @override
  String get estimating => 'Estimating…';

  @override
  String get atOrBelowTarget => 'At/Below target';

  @override
  String get minutesShort => 'min';

  @override
  String get hoursShort => 'h';

  @override
  String get initializing => 'Initializing...';

  @override
  String get waitForChamber => 'Please wait for chamber to reach 45–70°C';

  @override
  String get targetTempRange => 'Target: temperature between 45°C and 70°C';

  @override
  String get putGrainsNow => 'You may now put your grains';

  @override
  String get chamberReady => 'Chamber is ready.';

  @override
  String get startDrying => 'Start Drying';

  @override
  String get sessionAlreadyRunning => 'A session is already running.';

  @override
  String get unableToComputeEta => 'Unable to compute estimated time.';

  @override
  String get dryingStarted => 'Drying started';

  @override
  String get targetReachedEnded => 'Target reached • Session ended';

  @override
  String get noPreviousSettings => 'No previous settings found.';

  @override
  String get startNewSession => 'Start New Session';

  @override
  String get startNewSessionBody =>
      'Start a new session using the previous settings?';

  @override
  String get usePreviousSettings => 'Use previous settings';

  @override
  String get sessionTimer => 'Session Timer';

  @override
  String get paused => 'Paused';

  @override
  String get running => 'Running';

  @override
  String get idle => 'Idle';

  @override
  String toTarget(Object target) {
    return 'to $target% MC';
  }

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get stop => 'Stop';

  @override
  String get stopSession => 'Stop Session';

  @override
  String get stopSessionBody => 'You are about to stop the current session.';

  @override
  String get safetyStop => 'Safety stop triggered by device';

  @override
  String get tip_9_9_5 => '9–9.5% • good for long-term seed preservation';

  @override
  String get tip_10_11_5 => '10–11.5% • good for short-term seed preservation';

  @override
  String get tip_12_12_5 => '12–12.5% • for storage beyond 3 months';

  @override
  String get tip_13_14 =>
      '13–14% • for storage within 2–3 months (recommended for milling)';

  @override
  String get tip_selectTarget => 'Select a target moisture content (9–14%)';

  @override
  String get analytics_exportPdf => 'Export PDF';

  @override
  String get analytics_exportAnalyticsPdf => 'Export Analytics PDF';

  @override
  String get analytics_chooseSessions => 'Choose which sessions to include.';

  @override
  String get analytics_currentSessionOnly => 'Current session only';

  @override
  String get analytics_selectSessions => 'Select sessions…';

  @override
  String get analytics_generatePdf => 'Generate PDF';

  @override
  String get analytics_renameSession => 'Rename session';

  @override
  String get analytics_sessionName => 'Session name';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_save => 'Save';

  @override
  String get analytics_reportTitle => 'NiceRice Session Report';

  @override
  String get analytics_environmentIfAvailable => 'Environment (if available)';

  @override
  String get analytics_notes => 'Notes';

  @override
  String get analytics_notesBody =>
      'Generated by NiceRice Analytics. This summary includes target, preset, intended use, duration, and basic statistics.';

  @override
  String get analytics_targetMoistureContent => 'Target Moisture Content';

  @override
  String get analytics_presetSelected => 'Preset Selected';

  @override
  String get analytics_intendedUse => 'Intended Use';

  @override
  String get analytics_estimatedMoistureLoss => 'Estimated Moisture Loss';

  @override
  String get analytics_started => 'Started';

  @override
  String get analytics_ended => 'Ended';

  @override
  String get analytics_durationInitCooldown =>
      'Duration (incl. init & cooldown)';

  @override
  String get analytics_estDefault => '~3–5% (est.)';

  @override
  String get analytics_estAbbrev => '(est.)';

  @override
  String get analytics_temperatureAvgRange => 'Temperature (avg / range)';

  @override
  String get analytics_humidityAvgRange => 'Humidity (avg / range)';

  @override
  String get analytics_environment => 'Environment';

  @override
  String get analytics_noEnvData => 'No temperature/humidity data';

  @override
  String get analytics_noEnvDataForSession =>
      'No temperature/humidity data for this session.';

  @override
  String get analytics_emptyHistory =>
      'No completed operations yet.\nRun one in Automation to build history.';

  @override
  String get analytics_noSessionsForFilter =>
      'No sessions for selected filter.';

  @override
  String get analytics_tempHumOverview => 'Temperature & Humidity Overview';

  @override
  String get analytics_interpretation => 'Interpretation';

  @override
  String get analytics_initialMoisture => 'Initial Moisture';

  @override
  String get analytics_targetMoisture => 'Target Moisture';

  @override
  String get analytics_notEnoughData => 'Not enough data for interpretation.';

  @override
  String analytics_mcDropped(String from, String to, String duration) {
    return 'Moisture content dropped from $from% to $to% in $duration.';
  }

  @override
  String analytics_mcRose(String from, String to, String duration) {
    return 'Moisture content rose from $from% to $to% in $duration.';
  }

  @override
  String analytics_mcStayed(String value, String duration) {
    return 'Moisture content stayed at $value% for $duration.';
  }

  @override
  String get analytics_sessionSummary => 'Drying Speed';

  @override
  String get analytics_start => 'Start';

  @override
  String get analytics_end => 'End';

  @override
  String get analytics_duration => 'Duration';

  @override
  String get analytics_points => 'Points';

  @override
  String get analytics_average => 'Average';

  @override
  String get analytics_min => 'Min';

  @override
  String get analytics_max => 'Max';

  @override
  String get filters_today => 'Today';

  @override
  String get filters_yesterday => 'Yesterday';

  @override
  String get filters_last3 => 'Last 3 days';

  @override
  String get filters_last7 => 'Last 7 days';

  @override
  String get tooltip_renameSession => 'Rename session';

  @override
  String get analytics_renameSaved => 'Session name updated.';

  @override
  String get analytics_renameFailed =>
      'Couldn\'t save name to the database. Keeping the name locally on this device.';
}
