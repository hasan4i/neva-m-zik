import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum NevaMode { off, sleeping, active }

class VoiceService {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool sttReady = false;
  NevaMode mode = NevaMode.off;
  String wakeWord = 'neva';
  String lastHeard = '';
  String? _resolvedLocaleId;
  String localeStatus = '';

  bool _isSpeaking = false;
  bool _wantsListening = false;

  Timer? _sleepTimer;
  Timer? _restartTimer;
  Timer? _watchdogTimer;
  DateTime _lastListenStart = DateTime.now();

  void Function(NevaMode mode)? onModeChanged;
  void Function(String heard)? onHeard;

  final Map<String, List<String>> commandWords = {
    'sonraki': ['degistir', 'değiştir', 'sonraki', 'gec', 'geç', 'atla', 'next'],
    'onceki': ['onceki', 'önceki', 'geri', 'previous'],
    'durdur': ['durdur', 'dur', 'bekle', 'stop'],
    'devam': ['devam', 'baslat', 'başlat', 'cal', 'çal', 'play'],
    'sesi_artir': ['sesi ac', 'sesi aç', 'yukselt', 'yükselt', 'arttir', 'artır'],
    'sesi_azalt': ['sesi kis', 'sesi kıs', 'kıs', 'azalt'],
    'karistir': ['karistir', 'karıştır', 'rastgele'],
    'tekrar': ['tekrar', 'yeniden', 'basa al', 'başa al'],
  };

  Future<bool> init() async {
    sttReady = await _stt.initialize(
      onStatus: _handleStatus,
      onError: (dynamic e) {
        _scheduleRestart(const Duration(milliseconds: 500));
      },
      debugLogging: false,
    );

    if (sttReady) {
      await _resolveTurkishLocale();
    }

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _scheduleRestart(const Duration(milliseconds: 300));
    });
    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      _scheduleRestart(const Duration(milliseconds: 300));
    });

    try {
      await _tts.setLanguage(_resolvedLocaleId?.replaceAll('_', '-') ?? 'tr-TR');
    } catch (_) {
      await _tts.setLanguage('tr-TR');
    }
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    return sttReady;
  }

  Future<void> _resolveTurkishLocale() async {
    try {
      final locales = await _stt.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase() == 'tr_tr') {
          _resolvedLocaleId = l.localeId;
          localeStatus = 'tr_TR bulundu';
          return;
        }
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('tr')) {
          _resolvedLocaleId = l.localeId;
          localeStatus = '${l.localeId} bulundu';
          return;
        }
      }
      final systemLocale = await _stt.systemLocale();
      _resolvedLocaleId = systemLocale?.localeId;
      localeStatus = 'Turkce bulunamadi, cihaz varsayilani kullaniliyor: ${_resolvedLocaleId ?? "bilinmiyor"}';
    } catch (e) {
      _resolvedLocaleId = null;
      localeStatus = 'Locale tespiti basarisiz: $e';
    }
  }

  void _handleStatus(String status) {
    if (status == 'notListening' || status == 'done') {
      if (_wantsListening && !_isSpeaking) {
        _scheduleRestart(const Duration(milliseconds: 200));
      }
    }
  }

  void _scheduleRestart(Duration delay) {
    if (!_wantsListening) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, _listenOnce);
  }

  void start({required Function(String command) onCommand}) {
    if (!sttReady) return;
    mode = NevaMode.sleeping;
    _wantsListening = true;
    onModeChanged?.call(mode);
    _onCommand = onCommand;
    _listenOnce();
    _startWatchdog();
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_wantsListening) return;
      if (_isSpeaking) return;
      final elapsed = DateTime.now().difference(_lastListenStart);
      if (!_stt.isListening && elapsed.inSeconds > 3) {
        _listenOnce();
      }
    });
  }

  Function(String command)? _onCommand;

  void _listenOnce() {
    if (!_wantsListening || !sttReady || _isSpeaking) return;
    if (_stt.isListening) return;

    _lastListenStart = DateTime.now();

    _stt.listen(
      localeId: _resolvedLocaleId,
      listenFor: const Duration(seconds: 55),
      pauseFor: const Duration(seconds: 4),
      partialResults: true,
      onResult: (result) {
        final heard = result.recognizedWords.toLowerCase().trim();
        if (heard.isEmpty) return;
        lastHeard = heard;
        onHeard?.call(heard);

        if (mode == NevaMode.sleeping) {
          if (_fuzzyContains(heard, wakeWord)) {
            _wakeUp();
          }
          return;
        }

        if (result.finalResult) {
          _process(heard);
        }
      },
    );
  }

  void _process(String input) {
    if (mode == NevaMode.active) {
      _resetSleepTimer();
      final cmd = _matchCommand(input);
      if (cmd != null) {
        _onCommand?.call(cmd);
        _speak(_responseFor(cmd));
      } else if (input.contains('sarki') || input.contains('şarkı')) {
        _onCommand?.call('sarki_ara:$input');
      }
    }
  }

  void _wakeUp() {
    mode = NevaMode.active;
    onModeChanged?.call(mode);
    _speak('Buyrun.');
    _resetSleepTimer();
  }

  void _resetSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(const Duration(minutes: 2), () {
      mode = NevaMode.sleeping;
      onModeChanged?.call(mode);
    });
  }

  bool _fuzzyContains(String input, String target) {
    if (input.contains(target)) return true;
    final words = input.split(RegExp(r'\s+'));
    for (final w in words) {
      if (w.isEmpty) continue;
      final dist = _levenshtein(w, target);
      final threshold = target.length <= 4 ? 2 : 3;
      if (dist <= threshold) return true;
    }
    return false;
  }

  String? _matchCommand(String input) {
    for (final entry in commandWords.entries) {
      for (final variant in entry.value) {
        if (input.contains(variant)) return entry.key;
      }
    }
    String? bestCmd;
    int bestDist = 999;
    for (final entry in commandWords.entries) {
      for (final variant in entry.value) {
        final words = input.split(RegExp(r'\s+'));
        for (final w in words) {
          if (w.length < 3) continue;
          final dist = _levenshtein(w, variant);
          if (dist < bestDist) {
            bestDist = dist;
            bestCmd = entry.key;
          }
        }
      }
    }
    if (bestCmd != null && bestDist <= 2) return bestCmd;
    return null;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    List<int> prev = List.generate(b.length + 1, (i) => i);
    for (int i = 0; i < a.length; i++) {
      List<int> curr = [i + 1];
      for (int j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        curr.add(_min3(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost));
      }
      prev = curr;
    }
    return prev.last;
  }

  int _min3(int a, int b, int c) {
    int m = a < b ? a : b;
    return m < c ? m : c;
  }

  String _responseFor(String cmd) {
    switch (cmd) {
      case 'sonraki': return 'Sonraki sarkiya geciyorum.';
      case 'onceki': return 'Onceki sarkiya geciyorum.';
      case 'durdur': return 'Durduruldu.';
      case 'devam': return 'Devam ediyorum.';
      case 'sesi_artir': return 'Ses artirildi.';
      case 'sesi_azalt': return 'Ses kisildi.';
      case 'karistir': return 'Karisik mod acildi.';
      case 'tekrar': return 'Basa alindi.';
      default: return 'Tamam.';
    }
  }

  Future<void> speak(String text) => _speak(text);

  Future<void> _speak(String text) async {
    await _stt.stop();
    await _tts.speak(text);
  }

  void stop() {
    _wantsListening = false;
    _sleepTimer?.cancel();
    _restartTimer?.cancel();
    _watchdogTimer?.cancel();
    mode = NevaMode.off;
    onModeChanged?.call(mode);
    _stt.stop();
    _tts.stop();
  }

  void setWakeWord(String word) {
    wakeWord = word.toLowerCase().trim();
  }

  void dispose() {
    _wantsListening = false;
    _sleepTimer?.cancel();
    _restartTimer?.cancel();
    _watchdogTimer?.cancel();
    _stt.stop();
    _tts.stop();
  }
}
