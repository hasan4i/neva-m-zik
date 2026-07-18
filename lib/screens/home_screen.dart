import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/music_service.dart';
import '../services/voice_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicService _music = MusicService();
  final VoiceService _voice = VoiceService();

  bool _voiceOn = false;
  bool _isPlaying = false;
  int _currentIndex = 0;
  String _statusText = 'Kapali';
  String _lastHeard = '';
  final TextEditingController _wakeWordCtrl = TextEditingController(text: 'neva');

  @override
  void initState() {
    super.initState();
    _music.onTrackChanged = (i) => setState(() => _currentIndex = i);
    _music.onPlayStateChanged = (p) => setState(() => _isPlaying = p);
    _voice.onModeChanged = (mode) => setState(() => _statusText = _textForMode(mode));
    _voice.onHeard = (h) => setState(() => _lastHeard = h);
    _loadWakeWord();
    _requestPermissions();
  }

  Future<void> _loadWakeWord() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('wake_word') ?? 'neva';
    _wakeWordCtrl.text = saved;
    _voice.setWakeWord(saved);
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.notification.request();
    await Permission.audio.request();
    await Permission.storage.request();
  }

  String _textForMode(NevaMode mode) {
    switch (mode) {
      case NevaMode.off:
        return 'Kapali';
      case NevaMode.sleeping:
        return 'Uyku modunda — "${_voice.wakeWord}" de uyandir';
      case NevaMode.active:
        return 'Dinliyorum...';
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null) return;

    final newTracks = result.files
        .where((f) => f.path != null)
        .map((f) => Track(
              path: f.path!,
              name: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
            ))
        .toList();

    setState(() {
      _music.addTracks(newTracks);
    });
  }

  Future<void> _pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

    setState(() => _statusText = 'Klasor taraniyor...');

    final found = await _music.scanDeviceMusic(customFolders: [dirPath]);

    if (found.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu klasorde muzik dosyasi bulunamadi.')),
        );
      }
      setState(() => _statusText = _textForMode(_voice.mode));
      return;
    }

    setState(() {
      _music.addTracks(found);
      _statusText = _textForMode(_voice.mode);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${found.length} sarki eklendi.')),
      );
    }
  }

  void _removeTrack(int index) {
    setState(() {
      _music.removeAt(index);
    });
  }

  void _clearAllTracks() {
    setState(() {
      _music.clearAll();
    });
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2744),
        title: const Text('Emin misiniz?', style: TextStyle(color: Colors.white)),
        content: const Text('Tum sarkilar listeden kaldirilacak.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgec'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _clearAllTracks();
    }
  }

  Future<void> _toggleVoice() async {
    if (_voiceOn) {
      _voice.stop();
      setState(() {
        _voiceOn = false;
        _statusText = 'Kapali';
      });
    } else {
      final ok = await _voice.init();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ses tanima baslatilamadi. Mikrofon iznini kontrol edin.')),
          );
        }
        return;
      }
      if (mounted && _voice.localeStatus.contains('bulunamadi')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uyari: ${_voice.localeStatus}. Telefon ayarlarindan Turkce ses tanima dil paketini indirmeniz gerekebilir.'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      setState(() => _voiceOn = true);
      _voice.start(onCommand: _handleCommand);
    }
  }

  void _handleCommand(String command) {
    if (command.startsWith('sarki_ara:')) {
      final query = command.substring('sarki_ara:'.length);
      final match = _music.findBestMatch(query);
      if (match != null) {
        final idx = _music.indexOfName(match);
        _music.playAt(idx);
        _voice.speak('$match calıniyor.');
      } else {
        _voice.speak('Sarki bulunamadi.');
      }
      return;
    }

    switch (command) {
      case 'sonraki':
        _music.next();
        break;
      case 'onceki':
        _music.previous();
        break;
      case 'durdur':
        _music.pause();
        break;
      case 'devam':
        _music.play();
        break;
      case 'sesi_artir':
        _music.volumeUp();
        break;
      case 'sesi_azalt':
        _music.volumeDown();
        break;
      case 'karistir':
        _music.toggleShuffle();
        break;
      case 'tekrar':
        _music.restart();
        break;
    }
  }

  Future<void> _saveWakeWord() async {
    final word = _wakeWordCtrl.text.trim().toLowerCase();
    if (word.isEmpty) return;
    _voice.setWakeWord(word);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wake_word', word);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$word" uyandirma kelimesi olarak kaydedildi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTrack = _music.tracks.isNotEmpty;
    final currentName = hasTrack ? _music.tracks[_currentIndex].name : '—';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('🎵', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 8),
                  const Text('Neva',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF00BCD4))),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white54),
                    onPressed: _showSettings,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickFiles,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24, width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: Colors.white70),
                            SizedBox(height: 4),
                            Text('Muzik ekle', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: _pickFolder,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24, width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open, color: Colors.white70),
                            SizedBox(height: 4),
                            Text('Klasor sec', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (hasTrack) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_music.tracks.length} sarki', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    InkWell(
                      onTap: _confirmClearAll,
                      child: const Text('Tumunu temizle', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2744),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListView.builder(
                    itemCount: _music.tracks.length,
                    itemBuilder: (context, i) {
                      final active = i == _currentIndex;
                      return ListTile(
                        dense: true,
                        title: Text(
                          _music.tracks[i].name,
                          style: TextStyle(
                            color: active ? const Color(0xFF00BCD4) : Colors.white70,
                            fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _music.playAt(i),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white24, size: 18),
                          onPressed: () => _removeTrack(i),
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 20),

              Text(currentName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous, color: Colors.white70),
                    onPressed: hasTrack ? _music.previous : null,
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    iconSize: 56,
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: const Color(0xFF00BCD4)),
                    onPressed: hasTrack ? _music.togglePlay : null,
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next, color: Colors.white70),
                    onPressed: hasTrack ? _music.next : null,
                  ),
                ],
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2744),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_statusText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              if (_lastHeard.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Duyulan: "$_lastHeard"',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _toggleVoice,
                  icon: Icon(_voiceOn ? Icons.mic : Icons.mic_off),
                  label: Text(_voiceOn ? 'Sesli Kontrolu Kapat' : 'Sesli Kontrolu Baslat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _voiceOn ? Colors.redAccent.withOpacity(0.8) : const Color(0xFF00BCD4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2744),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ayarlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            const Text('Uyandirma kelimesi', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wakeWordCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0D2137),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _saveWakeWord();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BCD4)),
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _music.dispose();
    _voice.dispose();
    _wakeWordCtrl.dispose();
    super.dispose();
  }
}
