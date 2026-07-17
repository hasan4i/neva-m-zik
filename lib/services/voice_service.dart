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

  Timer? _sleepTimer;
  Timer? _restartTimer;

  void Function(NevaMode mode)? onModeChanged;
  void Function(String heard)? onHeard;

  final Map<String, List<String>> commandWords = {
    'sonraki': ['degistir', 'değiştir', 'sonraki', 'gec', 'geç', 'atla'],
    'onceki': ['onceki', 'önceki', 'geri'],
    'durdur': ['durdur', 'dur', 'bekle'],
    'devam': ['devam', 'baslat', 'başlat', 'cal', 'çal'],
    'sesi_artir': ['sesi ac', 'sesi aç', 'yukselt', 'yükselt', 'arttir', 'artır'],
    'sesi_azalt': ['sesi kis', 'sesi kıs', 'kıs', 'azalt'],
    'karistir': ['karistir', 'karıştır', 'rastgele'],
    'tekrar': ['tekrar', 'yeniden', 'basa al', 'başa al'],
  };

  Future<bool> init() async {
    sttReady = await _stt.initialize(
      onStatus: (status) {
        if (status == 'notListening' && mode != NevaMode.off) {
          _restartTimer?.cancel();
          _restartTimer = Timer(const Duration(milliseconds: 400), _listenOnce);
        }
      },
      onError: (e) {
        _restartTimer?.cancel();
        _restartTimer = Timer(const Duration(milliseconds: 800), _listenOnce);
      },
    );
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(0.85);
    await _tts.setVolume(1.0);
    return sttReady;
  }

  void start({required Function(String command) onCommand}) {
    if (!sttReady) return;
    mode = NevaMode.sleeping;
    onModeChanged?.call(mode);
    _onCommand = onCommand;
    _listenOnce();
  }

  Function(String command)? _onCommand;

  void _listenOnce() {
    if (mode == NevaMode.off || !sttReady) return;
    if (_stt.isListening) return;

    _stt.listen(
      localeId: 'tr_TR',
      listenFor: const Duration(seconds: 25),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          final heard = result.recognizedWords.toLowerCase().trim();
          lastHeard = heard;
          onHeard?.call(heard);
          _process(heard);
        }
      },
    );
  }

  void _process(String input) {
    if (mode == NevaMode.sleeping) {
      if (_fuzzyContains(input, wakeWord)) {
        _wakeUp();
      }
      return;
    }

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
    final words = input.split(' ');
    for (final w in words) {
      if (_levenshtein(w, target) <= 1 && target.length > 2) return true;
    }
    return false;
  }

  String? _matchCommand(String input) {
    for (final entry in commandWords.entries) {
      for (final variant in entry.value) {
        if (input.contains(variant)) return entry.key;
      }
    }
    // Bulanık eşleşme - tek kelimelik girişlerde
    for (final entry in commandWords.entries) {
      for (final variant in entry.value) {
        final words = input.split(' ');
        for (final w in words) {
          if (w.length > 3 && _levenshtein(w, variant) <= 2) return entry.key;
        }
      }
    }
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

  int _min3(int a, int b, int c) { int m = a < b ? a : b; return m < c ? m : c; }

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
    await _tts.speak(text);
  }

  void stop() {
    _sleepTimer?.cancel();
    _restartTimer?.cancel();
    mode = NevaMode.off;
    onModeChanged?.call(mode);
    _stt.stop();
  }

  void setWakeWord(String word) {
    wakeWord = word.toLowerCase().trim();
  }

  void dispose() {
    _sleepTimer?.cancel();
    _restartTimer?.cancel();
    _stt.stop();
  }
}
