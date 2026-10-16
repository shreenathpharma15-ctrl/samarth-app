import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

void main() {
  runApp(const SamarthApp());
}

class SamarthApp extends StatelessWidget {
  const SamarthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAMARTH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B8ED0),
          secondary: Color(0xFF00E5FF),
        ),
      ),
      home: const SamarthSplashScreen(),
    );
  }
}

// ============================================================================
// 1. ANIMATED "SAMARTH" SPLASH SCREEN
// ============================================================================
class SamarthSplashScreen extends StatefulWidget {
  const SamarthSplashScreen({super.key});

  @override
  State<SamarthSplashScreen> createState() => _SamarthSplashScreenState();
}

class _SamarthSplashScreenState extends State<SamarthSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _spacingAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _spacingAnimation = Tween<double>(begin: 2.0, end: 14.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
    );

    _controller.forward();

    Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 800),
            pageBuilder: (_, __, ___) => const MinimalPlayerScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SAMARTH',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: _spacingAnimation.value,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF00E5FF)
                                .withOpacity(0.6 * _fadeAnimation.value),
                            blurRadius: 24 * _controller.value,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'STUDIO • PLAYER • KARAOKE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 4.0,
                        color: Colors.white54.withOpacity(_fadeAnimation.value),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// 2. MINIMAL PLAYER, YOUTUBE DOWNLOADER, PITCH SHIFTER & KARAOKE RECORDER
// ============================================================================
class MinimalPlayerScreen extends StatefulWidget {
  const MinimalPlayerScreen({super.key});

  @override
  State<MinimalPlayerScreen> createState() => _MinimalPlayerScreenState();
}

class _MinimalPlayerScreenState extends State<MinimalPlayerScreen> {
  final TextEditingController _urlController = TextEditingController();
  late final AudioPlayer _audioPlayer;
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final YoutubeExplode _yt = YoutubeExplode();
  final AudioRecorder _micRecorder = AudioRecorder();

  String _trackTitle = 'No Track Loaded';
  String _statusText = 'Paste a YouTube link or open a local audio file';
  String _activeLyric = '♪   ♪   ♪';
  String _nextLyric = '';

  bool _isDownloading = false;
  bool _isKaraoke = false;
  bool _isRecording = false;
  String? _lastRecordedPath;

  // Pitch Shifter state in semitones (-6 to +6 semitones)
  double _semitones = 0.0;

  List<ClosedCaption> _captions = [];

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [_equalizer],
      ),
    );

    _audioPlayer.positionStream.listen((position) {
      if (_captions.isNotEmpty && mounted) {
        String current = '♪   ♪   ♪';
        String upcoming = '';
        for (int i = 0; i < _captions.length; i++) {
          if (position >= _captions[i].offset) {
            current = _captions[i].text;
            if (i + 1 < _captions.length) {
              upcoming = _captions[i + 1].text;
            }
          } else {
            break;
          }
        }
        if (current != _activeLyric) {
          setState(() {
            _activeLyric = current;
            _nextLyric = upcoming;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _audioPlayer.dispose();
    _micRecorder.dispose();
    _yt.close();
    super.dispose();
  }

  // Convert semitones (-6 to +6) to pitch multiplier: 2^(semitones/12)
  Future<void> _updatePitch(double semitones) async {
    setState(() => _semitones = semitones);
    final double pitchFactor = pow(2.0, semitones / 12.0).toDouble();
    await _audioPlayer.setPitch(pitchFactor);
  }

  // Toggle Microphone Voice Recording for Karaoke
  Future<void> _toggleMicRecording() async {
    try {
      if (_isRecording) {
        final path = await _micRecorder.stop();
        setState(() {
          _isRecording = false;
          _lastRecordedPath = path;
          _statusText = 'Karaoke session saved! Tap the Mic-Play icon to listen.';
        });
      } else {
        if (await _micRecorder.hasPermission()) {
          final dir = await getApplicationDocumentsDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final recPath = '${dir.path}/samarth_karaoke_$timestamp.m4a';

          await _micRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
            path: recPath,
          );

          // Automatically start playing backing track if loaded and paused
          if (!_audioPlayer.playing && _audioPlayer.duration != null) {
            _audioPlayer.play();
          }

          setState(() {
            _isRecording = true;
            _statusText = '🔴 Recording your voice with backing track...';
          });
        } else {
          setState(() {
            _statusText = 'Microphone permission is required to record karaoke.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusText = 'Recording error: $e';
      });
    }
  }

  // Play back the user's recorded karaoke vocal track
  Future<void> _playRecordedSession() async {
    if (_lastRecordedPath == null) return;
    await _updatePitch(0.0); // Reset pitch to normal for voice playback
    await _audioPlayer.setFilePath(_lastRecordedPath!);
    _audioPlayer.play();
    setState(() {
      _trackTitle = '🎤 My Recorded Karaoke Session';
      _activeLyric = 'Playing Back Your Recording';
      _nextLyric = _lastRecordedPath!.split('/').last;
      _statusText = 'Listening to recorded session';
    });
  }

  // Fetch YouTube Audio + Closed Captions for Karaoke
  Future<void> _fetchYouTube() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isDownloading = true;
      _statusText = 'Fetching stream & karaoke lyrics from YouTube...';
    });

    try {
      final video = await _yt.videos.get(url);
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      final dir = await getApplicationDocumentsDirectory();
      final cleanTitle = video.title.replaceAll(RegExp(r'[^\w\s-]'), '');
      final filePath = '${dir.path}/$cleanTitle.${audioStreamInfo.container.name}';
      final file = File(filePath);

      final stream = _yt.videos.streamsClient.get(audioStreamInfo);
      final fileStream = file.openWrite();
      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();

      final trackManifest = await _yt.videos.closedCaptions.getManifest(video.id);
      final trackInfo = trackManifest.getByLanguage('en');
      if (trackInfo.isNotEmpty) {
        final captionTrack = await _yt.videos.closedCaptions.get(trackInfo.first);
        _captions = captionTrack.captions;
      } else {
        _captions = [];
      }

      await _audioPlayer.setFilePath(filePath);
      await _updatePitch(_semitones);
      _audioPlayer.play();

      setState(() {
        _trackTitle = video.title;
        _statusText = 'Saved & Playing (${audioStreamInfo.container.name.toUpperCase()})';
        if (_captions.isEmpty) {
          _activeLyric = '🎤 Instrumental / Audio Ready';
          _nextLyric = 'No timed captions available on this YouTube video';
        }
      });
    } catch (e) {
      setState(() {
        _statusText = 'Download error: Check URL or connection';
      });
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  // Open Local Universal Audio Formats
  Future<void> _pickLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _captions = [];
      await _audioPlayer.setFilePath(path);
      await _updatePitch(_semitones);
      _audioPlayer.play();
      setState(() {
        _trackTitle = result.files.single.name;
        _statusText = 'Playing Local Track';
        _activeLyric = _isKaraoke ? '🎤 KARAOKE VOCAL CUT ACTIVE' : '🎵 PLAYING LOCAL AUDIO';
        _nextLyric = '';
      });
    }
  }

  // Toggle Karaoke Vocal-Cut DSP
  Future<void> _toggleKaraoke(bool enabled) async {
    setState(() {
      _isKaraoke = enabled;
      _statusText = enabled
          ? 'Karaoke Mode Active (Mid-Vocal Band Attenuated)'
          : 'Original Studio Audio';
      if (_captions.isEmpty && _trackTitle != 'No Track Loaded') {
        _activeLyric = enabled ? '🎤 KARAOKE VOCAL CUT ACTIVE' : '🎵 PLAYING AUDIO';
      }
    });
    await _equalizer.setEnabled(enabled);
    if (enabled) {
      final params = await _equalizer.parameters;
      for (var band in params.bands) {
        if (band.centerFrequency >= 300 && band.centerFrequency <= 3200) {
          await band.setGain(params.minDecibels);
        } else {
          await band.setGain(0.0);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String pitchLabel = _semitones == 0
        ? 'Original Key (0 ST)'
        : '${_semitones > 0 ? '+' : ''}${_semitones.toStringAsFixed(0)} Semitones';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 12.0),
          child: Column(
            children: [
              // Minimal Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SAMARTH',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  Row(
                    children: [
                      if (_lastRecordedPath != null)
                        IconButton(
                          icon: const Icon(Icons.record_voice_over_rounded,
                              color: Color(0xFF00E5FF)),
                          tooltip: 'Play Last Karaoke Recording',
                          onPressed: _playRecordedSession,
                        ),
                      IconButton(
                        icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
                        tooltip: 'Open Local Music File',
                        onPressed: _pickLocalFile,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 1. Minimal URL Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Paste YouTube link...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF16161A),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isDownloading ? null : _fetchYouTube,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8ED0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Fetch',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _statusText,
                style: TextStyle(
                  color: _isRecording ? Colors.redAccent : Colors.white38,
                  fontSize: 11,
                  fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // 2. Center Interactive Stage (Karaoke Lyrics & Track Focus)
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121216),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isRecording
                          ? Colors.redAccent.withOpacity(0.6)
                          : (_isKaraoke
                              ? const Color(0xFF00E5FF).withOpacity(0.35)
                              : Colors.white10),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _trackTitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _activeLyric,
                          key: ValueKey<String>(_activeLyric),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00E5FF),
                            height: 1.35,
                          ),
                        ),
                      ),
                      Text(
                        _nextLyric.isNotEmpty ? 'Next: $_nextLyric' : '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Minimal Pitch-Shifter Bar (-6 to +6 Semitones)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 18, color: Colors.white54),
                    const SizedBox(width: 8),
                    Text(
                      pitchLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 2,
                        ),
                        child: Slider(
                          min: -6.0,
                          max: 6.0,
                          divisions: 12,
                          value: _semitones,
                          activeColor: const Color(0xFF00E5FF),
                          onChanged: _updatePitch,
                        ),
                      ),
                    ),
                    if (_semitones != 0)
                      GestureDetector(
                        onTap: () => _updatePitch(0.0),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // 4. Seek Slider
              StreamBuilder<Duration>(
                stream: _audioPlayer.positionStream,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final total = _audioPlayer.duration ?? Duration.zero;
                  final maxMs = total.inMilliseconds.toDouble() > 0
                      ? total.inMilliseconds.toDouble()
                      : 1.0;
                  return SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs,
                      value: pos.inMilliseconds.toDouble().clamp(0.0, maxMs),
                      onChanged: (val) {
                        _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  );
                },
              ),

              // 5. Bottom Transport: Play/Pause, Mic Record, & Karaoke Switch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      StreamBuilder<bool>(
                        stream: _audioPlayer.playingStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data ?? false;
                          return FloatingActionButton.small(
                            heroTag: 'play_btn',
                            onPressed: () {
                              playing ? _audioPlayer.pause() : _audioPlayer.play();
                            },
                            backgroundColor: const Color(0xFF3B8ED0),
                            child: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      // Karaoke Microphone Record Button
                      FloatingActionButton.small(
                        heroTag: 'rec_btn',
                        onPressed: _toggleMicRecording,
                        backgroundColor:
                            _isRecording ? Colors.redAccent : const Color(0xFF222228),
                        tooltip: _isRecording ? 'Stop Recording' : 'Record Karaoke',
                        child: Icon(
                          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Karaoke',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: _isKaraoke,
                        activeColor: const Color(0xFF00E5FF),
                        onChanged: _toggleKaraoke,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
