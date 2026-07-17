import 'dart:math';
import 'package:just_audio/just_audio.dart';

class Track {
  final String path;
  final String name;
  Track({required this.path, required this.name});
}

class MusicService {
  final AudioPlayer player = AudioPlayer();
  final List<Track> tracks = [];
  int currentIndex = 0;
  bool shuffleMode = false;
  final Random _random = Random();

  void Function(int index)? onTrackChanged;
  void Function(bool playing)? onPlayStateChanged;

  MusicService() {
    player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);
      if (state.processingState == ProcessingState.completed) {
        next();
      }
    });
  }

  void addTracks(List<Track> newTracks) {
    tracks.addAll(newTracks);
    if (tracks.length == newTracks.length && tracks.isNotEmpty) {
      _load(0);
    }
  }

  Future<void> _load(int index) async {
    if (tracks.isEmpty) return;
    currentIndex = index;
    await player.setFilePath(tracks[index].path);
    onTrackChanged?.call(currentIndex);
  }

  Future<void> play() async {
    if (tracks.isEmpty) return;
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> togglePlay() async {
    if (player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (tracks.isEmpty) return;
    int i;
    if (shuffleMode && tracks.length > 1) {
      do {
        i = _random.nextInt(tracks.length);
      } while (i == currentIndex);
    } else {
      i = (currentIndex + 1) % tracks.length;
    }
    await _load(i);
    await play();
  }

  Future<void> previous() async {
    if (tracks.isEmpty) return;
    final i = (currentIndex - 1 + tracks.length) % tracks.length;
    await _load(i);
    await play();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= tracks.length) return;
    await _load(index);
    await play();
  }

  Future<void> restart() async {
    await player.seek(Duration.zero);
    await play();
  }

  void toggleShuffle() {
    shuffleMode = !shuffleMode;
  }

  Future<void> volumeUp() async {
    final v = player.volume;
    await player.setVolume((v + 0.15).clamp(0.0, 1.0));
  }

  Future<void> volumeDown() async {
    final v = player.volume;
    await player.setVolume((v - 0.15).clamp(0.0, 1.0));
  }

  String? findBestMatch(String query) {
    if (tracks.isEmpty) return null;
    String? bestName;
    double bestScore = 0;
    for (final t in tracks) {
      final score = _similarity(query.toLowerCase(), t.name.toLowerCase());
      if (score > bestScore) {
        bestScore = score;
        bestName = t.name;
      }
    }
    return bestScore > 0.35 ? bestName : null;
  }

  int indexOfName(String name) {
    return tracks.indexWhere((t) => t.name == name);
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (b.contains(a) || a.contains(b)) return 0.9;
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0 : intersection / union;
  }

  void dispose() {
    player.dispose();
  }
}
