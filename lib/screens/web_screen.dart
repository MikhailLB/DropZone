import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

class WebScreen extends StatefulWidget {
  final String title;
  final String url;
  const WebScreen({super.key, required this.title, required this.url});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(DZColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _loading = true; _error = false; });
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          // Only flag as error for main-frame failures.
          if (err.isForMainFrame == true && mounted) {
            setState(() { _loading = false; _error = true; });
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<bool> _onPopInvoked() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false; // stay on WebScreen
    }
    return true; // allow pop to previous Flutter screen
  }

  void _reload() {
    setState(() { _loading = true; _error = false; });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onPopInvoked();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: DZColors.bg,
        appBar: AppBar(
          backgroundColor: DZColors.bgPanel,
          title: Text(widget.title,
              style: neonText(size: 18, color: DZColors.cyan)),
          iconTheme: const IconThemeData(color: DZColors.cyan),
          elevation: 0,
          actions: [
            if (_error)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: DZColors.cyan),
                onPressed: _reload,
              ),
          ],
        ),
        body: Stack(
          children: [
            // Always keep WebView in tree so it doesn't reload on every build.
            Opacity(
              opacity: _error ? 0 : 1,
              child: WebViewWidget(controller: _controller),
            ),
            if (_error)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: DZColors.textDim, size: 52),
                      const SizedBox(height: 20),
                      Text('No internet connection',
                          style: neonText(size: 17, color: DZColors.textDim),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: _reload,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          decoration:
                              neonBox(DZColors.cyan, radius: 14, glow: 10),
                          child: Text('RETRY',
                              style: neonText(size: 16, color: DZColors.cyan)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading && !_error)
              const Center(
                child: CircularProgressIndicator(color: DZColors.cyan),
              ),
          ],
        ),
      ),
    );
  }
}
