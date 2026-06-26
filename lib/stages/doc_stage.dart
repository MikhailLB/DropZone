import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

/// Lightweight WebView used to render the privacy and support pages from
/// inside the arcade flow. Distinct from PortalStage — no immersive mode,
/// no cookie tweaks, no error routing.
class DocStage extends StatefulWidget {
  final String title;
  final String url;

  const DocStage({super.key, required this.title, required this.url});

  @override
  State<DocStage> createState() => _DocStageState();
}

class _DocStageState extends State<DocStage> {
  late final WebViewController _ctrl;
  bool _busy = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(DZColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              _busy = true;
              _failed = false;
            });
          }
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _busy = false);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _busy = false;
              _failed = true;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  void _reload() {
    setState(() {
      _busy = true;
      _failed = false;
    });
    _ctrl.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DZColors.bg,
      appBar: AppBar(
        backgroundColor: DZColors.bgPanel,
        title: Text(widget.title,
            style: neonText(size: 18, color: DZColors.cyan)),
        iconTheme: const IconThemeData(color: DZColors.cyan),
        elevation: 0,
        actions: [
          if (_failed)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: DZColors.cyan),
              onPressed: _reload,
            ),
        ],
      ),
      body: Stack(
        children: [
          Opacity(
            opacity: _failed ? 0 : 1,
            child: WebViewWidget(controller: _ctrl),
          ),
          if (_failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: DZColors.textDim, size: 52),
                    const SizedBox(height: 16),
                    Text('No connection',
                        style: neonText(
                            size: 16, color: DZColors.textDim),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 22),
                    GestureDetector(
                      onTap: _reload,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 12),
                        decoration:
                            neonBox(DZColors.cyan, radius: 12, glow: 10),
                        child: Text('RELOAD',
                            style: neonText(size: 14, color: DZColors.cyan)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_busy && !_failed)
            const Center(
              child: CircularProgressIndicator(color: DZColors.cyan),
            ),
        ],
      ),
    );
  }
}
