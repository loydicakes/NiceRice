// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Filipino Pilipino (`fil`).
class AppLocalizationsFil extends AppLocalizations {
  AppLocalizationsFil([String locale = 'fil']) : super(locale);

  @override
  String get appTitle => 'NiceRice';

  @override
  String get language => 'Wika';

  @override
  String get languageEnglish => 'Ingles';

  @override
  String get languageFilipino => 'Filipino';

  @override
  String get connect => 'Ikonekta';

  @override
  String get disconnect => 'Idiskonekta';

  @override
  String get selectDevice => 'Pumili ng device';

  @override
  String get unnamedDevice => '(Walang Pangalan)';

  @override
  String connectedLabel(String name) {
    return 'Nakakonekta: $name';
  }

  @override
  String get deviceBattery => 'Baterya ng Device';

  @override
  String get dryingChamber => 'Drying Chamber';

  @override
  String get storageChamber => 'Storage Chamber';

  @override
  String get temperatureShort => 'Temp';

  @override
  String get humidity => 'Halumigmig';

  @override
  String get moisture => 'Moisture';

  @override
  String get status => 'Status';

  @override
  String get disconnectTitle => 'Idiskonekta';

  @override
  String get disconnectBody => 'Ididiskonekta mo ang kasalukuyang device.';

  @override
  String get cancel => 'Kanselahin';

  @override
  String get confirm => 'Kumpirmahin';

  @override
  String get bluetoothAndroidOnly =>
      'Android lang ang suportado para sa Bluetooth sa build na ito.';

  @override
  String get bluetoothStillOff => 'Naka-OFF pa rin ang Bluetooth.';

  @override
  String get noDevicesFound => 'Walang nakitang device sa paligid.';

  @override
  String get deviceDisconnected => 'Nadiskonekta ang device';

  @override
  String get disconnected => 'Nadiskonekta';

  @override
  String connectedTo(String name, String addr) {
    return 'Nakakonekta sa $name ($addr)';
  }

  @override
  String failedToConnect(String name) {
    return 'Nabigong kumonekta sa $name';
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
    return 'Hindi inaasahang error: $error';
  }

  @override
  String get bracketIdeal => 'tamang ani';

  @override
  String get bracketLate => 'huling ani (masyadong tuyo)';

  @override
  String get bracketEarly => 'maagang ani (masyadong basa)';

  @override
  String get connectToHomeTitle => 'Kumonekta sa NiceRice sa Home';

  @override
  String get connectToHomeBody =>
      'Bago magsimula, i-on ang Bluetooth at kumonekta sa iyong NiceRice device mula sa Home page.';

  @override
  String get connectToHomeBodyAlt =>
      'Bago magsimula, buksan ang Bluetooth at ikonekta ang NiceRice device sa Home page.';

  @override
  String get goToHome => 'Pumunta sa Home';

  @override
  String get start => 'Simulan';

  @override
  String get startSame => 'Gamitin ang dati';

  @override
  String get sessionPlan => 'Plano ng Session';

  @override
  String get initialMoistureContent => 'Inisyal na Moisture Content';

  @override
  String get targetMoistureContent => 'Target na Moisture Content';

  @override
  String get targetLower => 'target';

  @override
  String get temperature => 'Temperatura';

  @override
  String get estimatedTime => 'Tinatayang oras';

  @override
  String get completeInputsToEstimate =>
      'Kumpletuhin ang inputs para makalkula ang oras';

  @override
  String get estimating => 'Kinukwenta…';

  @override
  String get atOrBelowTarget => 'Nasa o mas mababa sa target';

  @override
  String get minutesShort => 'min';

  @override
  String get hoursShort => 'h';

  @override
  String get initializing => 'Nagsisimula...';

  @override
  String get waitForChamber =>
      'Maghintay hanggang umabot sa 45–70°C ang chamber';

  @override
  String get targetTempRange =>
      'Target: temperatura sa pagitan ng 45°C at 70°C';

  @override
  String get putGrainsNow => 'Pwede mo nang ilagay ang palay';

  @override
  String get chamberReady => 'Handa na ang chamber.';

  @override
  String get startDrying => 'Simulan ang Pagpapatuyo';

  @override
  String get sessionAlreadyRunning => 'May tumatakbong session.';

  @override
  String get unableToComputeEta => 'Hindi makakalkula ang tinatayang oras.';

  @override
  String get dryingStarted => 'Nagsimula ang pagpapatuyo';

  @override
  String get targetReachedEnded => 'Naabot ang target • Tapos na ang session';

  @override
  String get noPreviousSettings => 'Walang nakaraang settings.';

  @override
  String get startNewSession => 'Mag-umpisa ng Panibagong Session';

  @override
  String get startNewSessionBody =>
      'Gamitin ang nakaraang settings para sa bagong session?';

  @override
  String get usePreviousSettings => 'Gamitin ang nakaraang settings';

  @override
  String get sessionTimer => 'Session Timer';

  @override
  String get paused => 'Nakahinto';

  @override
  String get running => 'Tumatakbo';

  @override
  String get idle => 'Idle';

  @override
  String toTarget(Object target) {
    return 'hanggang $target% MC';
  }

  @override
  String get play => 'Play';

  @override
  String get pause => 'I-pause';

  @override
  String get stop => 'Itigil';

  @override
  String get stopSession => 'Itigil ang Session';

  @override
  String get stopSessionBody => 'Ititigil mo ang kasalukuyang session.';

  @override
  String get safetyStop => 'Nagana ang safety stop ng device';

  @override
  String get tip_9_9_5 => '9–9.5% • para sa pangmatagalang pag-iimbak ng binhi';

  @override
  String get tip_10_11_5 =>
      '10–11.5% • para sa panandaliang pag-iimbak ng binhi';

  @override
  String get tip_12_12_5 => '12–12.5% • para sa imbakan na lampas 3 buwan';

  @override
  String get tip_13_14 =>
      '13–14% • para sa imbakan sa loob ng 2–3 buwan (inirerekomenda para sa paggiling)';

  @override
  String get tip_selectTarget => 'Pumili ng target na moisture content (9–14%)';

  @override
  String get analytics_exportPdf => 'I-export ang PDF';

  @override
  String get analytics_exportAnalyticsPdf => 'I-export ang Analytics PDF';

  @override
  String get analytics_chooseSessions => 'Pumili ng mga session na isasama.';

  @override
  String get analytics_currentSessionOnly => 'Kasalukuyang session lang';

  @override
  String get analytics_selectSessions => 'Pumili ng mga session…';

  @override
  String get analytics_generatePdf => 'Gumawa ng PDF';

  @override
  String get analytics_renameSession => 'Palitan ang pangalan ng session';

  @override
  String get analytics_sessionName => 'Pangalan ng session';

  @override
  String get common_cancel => 'Kanselahin';

  @override
  String get common_save => 'I-save';

  @override
  String get analytics_reportTitle => 'Ulat sa Session ng NiceRice';

  @override
  String get analytics_environmentIfAvailable => 'Kapaligiran (kung mayroon)';

  @override
  String get analytics_notes => 'Mga Tala';

  @override
  String get analytics_notesBody =>
      'Inihanda ng NiceRice Analytics. Kasama sa buod ang target, preset, layunin, tagal, at mga batayang estadistika.';

  @override
  String get analytics_targetMoistureContent => 'Target na Moisture Content';

  @override
  String get analytics_presetSelected => 'Napiling Preset';

  @override
  String get analytics_intendedUse => 'Layunin';

  @override
  String get analytics_estimatedMoistureLoss => 'Tinatayang Bawas sa Moisture';

  @override
  String get analytics_started => 'Nagsimula';

  @override
  String get analytics_ended => 'Natapos';

  @override
  String get analytics_durationInitCooldown =>
      'Tagal (kasama ang pagsisimula at paglamig)';

  @override
  String get analytics_estDefault => '~3–5% (tantya)';

  @override
  String get analytics_estAbbrev => '(tantya)';

  @override
  String get analytics_temperatureAvgRange => 'Temperatura (avg / saklaw)';

  @override
  String get analytics_humidityAvgRange => 'Halumigmig (avg / saklaw)';

  @override
  String get analytics_environment => 'Kapaligiran';

  @override
  String get analytics_noEnvData => 'Walang datos ng temperatura/halumigmig';

  @override
  String get analytics_noEnvDataForSession =>
      'Walang datos ng temperatura/halumigmig para sa session na ito.';

  @override
  String get analytics_emptyHistory =>
      'Wala pang natapos na operasyon.\nMagpatakbo muna sa Automation para makabuo ng history.';

  @override
  String get analytics_noSessionsForFilter =>
      'Walang session para sa napiling filter.';

  @override
  String get analytics_tempHumOverview => 'Buod ng Temperatura at Halumigmig';

  @override
  String get analytics_interpretation => 'Pagsusuri';

  @override
  String get analytics_initialMoisture => 'Inisyal na Moisture';

  @override
  String get analytics_targetMoisture => 'Target na Moisture';

  @override
  String get analytics_notEnoughData => 'Kulang ang datos para sa pagsusuri.';

  @override
  String analytics_mcDropped(String from, String to, String duration) {
    return 'Bumaba ang moisture mula $from% hanggang $to% sa loob ng $duration.';
  }

  @override
  String analytics_mcRose(String from, String to, String duration) {
    return 'Tumaas ang moisture mula $from% hanggang $to% sa loob ng $duration.';
  }

  @override
  String analytics_mcStayed(String value, String duration) {
    return 'Nanatili ang moisture sa $value% sa loob ng $duration.';
  }

  @override
  String get analytics_sessionSummary => 'Buod ng Session';

  @override
  String get analytics_start => 'Simula';

  @override
  String get analytics_end => 'Wakas';

  @override
  String get analytics_duration => 'Tagal';

  @override
  String get analytics_points => 'Mga Punto';

  @override
  String get analytics_average => 'Average';

  @override
  String get analytics_min => 'Min';

  @override
  String get analytics_max => 'Max';

  @override
  String get filters_today => 'Ngayon';

  @override
  String get filters_yesterday => 'Kahapon';

  @override
  String get filters_last3 => 'Huling 3 araw';

  @override
  String get filters_last7 => 'Huling 7 araw';

  @override
  String get tooltip_renameSession => 'Palitan ang pangalan';

  @override
  String get analytics_renameSaved => 'Na-update ang pangalan ng session.';

  @override
  String get analytics_renameFailed =>
      'Hindi na-save ang pangalan sa database. Itatago muna namin ito nang lokal sa device na ito.';
}
