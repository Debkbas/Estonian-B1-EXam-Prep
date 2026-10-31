import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Course embed (spec §5.1). Session cookies persist across restarts via the
/// platform webview store, so login survives. On exit the screen *returns*
/// elapsed seconds (B7 fix) and the caller logs the activity, so the Trail
/// refreshes with the new minutes immediately.
class CourseWebviewScreen extends StatefulWidget {
  final String title;
  final String url;

  const CourseWebviewScreen({super.key, required this.title, required this.url});

  @override
  State<CourseWebviewScreen> createState() => _CourseWebviewScreenState();
}

class _CourseWebviewScreenState extends State<CourseWebviewScreen> {
  final _watch = Stopwatch()..start();

  @override
  Widget build(BuildContext context) {
    return PopScope<int>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _watch.stop();
        Navigator.of(context).pop(_watch.elapsed.inSeconds);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
          ),
        ),
      ),
    );
  }
}
