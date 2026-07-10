import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/repo.dart';

/// Course embed (spec §5.1). Session cookies persist across restarts via the
/// platform webview store, so login survives. Time on screen is logged to
/// activity_log on exit (focus-time ≈ study time, minimum 1 minute).
class CourseWebviewScreen extends StatefulWidget {
  final Repo repo;
  final String title;
  final String url;
  final String courseSlug;

  const CourseWebviewScreen({
    super.key,
    required this.repo,
    required this.title,
    required this.url,
    required this.courseSlug,
  });

  @override
  State<CourseWebviewScreen> createState() => _CourseWebviewScreenState();
}

class _CourseWebviewScreenState extends State<CourseWebviewScreen> {
  final _watch = Stopwatch()..start();

  @override
  void dispose() {
    _watch.stop();
    final minutes = (_watch.elapsed.inSeconds / 60).round();
    if (_watch.elapsed.inSeconds >= 45) {
      // fire-and-forget; repo guards minutes<=0
      widget.repo.logActivity(minutes < 1 ? 1 : minutes, 'course',
          detail: {'course': widget.courseSlug});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
      ),
    );
  }
}
