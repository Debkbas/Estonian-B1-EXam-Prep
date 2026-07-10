import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Minimal local-file audio player (listening tests, spec §7).
class AudioPlayerWidget extends StatefulWidget {
  final String filePath;
  final String title;
  const AudioPlayerWidget(
      {super.key, required this.filePath, required this.title});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final _player = AudioPlayer();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setFilePath(widget.filePath);
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text('Audio error: $_error');
    if (!_ready) return const LinearProgressIndicator();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        Row(
          children: [
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  iconSize: 36,
                  icon: Icon(playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill),
                  onPressed: () =>
                      playing ? _player.pause() : _player.play(),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (_, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final total = _player.duration ?? Duration.zero;
                  return Row(
                    children: [
                      Text(_fmt(pos)),
                      Expanded(
                        child: Slider(
                          value: total.inMilliseconds == 0
                              ? 0
                              : (pos.inMilliseconds / total.inMilliseconds)
                                  .clamp(0.0, 1.0),
                          onChanged: (v) => _player.seek(Duration(
                              milliseconds:
                                  (total.inMilliseconds * v).round())),
                        ),
                      ),
                      Text(_fmt(total)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
