import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:math' show min;
import '../handlers/html_file_handler.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'dart:io' as path;
import 'dart:convert';

class HtmlViewerScreen extends StatefulWidget {
  final List<int> fileBytes;
  final String filename;
  final bool isZip;
  final String? searchText;

  const HtmlViewerScreen({
    super.key,
    required this.fileBytes,
    required this.filename,
    this.isZip = false,
    this.searchText,
  });

  @override
  State<HtmlViewerScreen> createState() => _HtmlViewerScreenState();
}

class _HtmlViewerScreenState extends State<HtmlViewerScreen> {
  late Directory _htmlDir;
  String? _htmlPath;

  @override
  void initState() {
    super.initState();
    _setupFiles();
  }

  Future<void> _setupFiles() async {
    try {
      // Get the HTML directory
      _htmlDir = await getHtmlDirectory();
      debugPrint('HTML directory: ${_htmlDir.path}');

      if (widget.isZip) {
        // Handle ZIP file
        debugPrint('Extracting ZIP file...');
        final archive = ZipDecoder().decodeBytes(widget.fileBytes);
        
        // Create a subdirectory for this ZIP's contents
        final zipDir = Directory(p.join(_htmlDir.path, p.basenameWithoutExtension(widget.filename)));
        await zipDir.create(recursive: true);
        debugPrint('Created directory for ZIP: ${zipDir.path}');
        
        // Find the main HTML file
        final htmlFile = archive.files.firstWhere(
          (file) => file.name.toLowerCase().endsWith('.html'),
          orElse: () => throw Exception('No HTML file found in ZIP'),
        );
        
        // Extract all files to maintain resources
        for (final file in archive.files) {
          if (file.isFile) {
            final filePath = p.join(zipDir.path, file.name);
            debugPrint('Extracting: ${file.name}');
            await Directory(p.dirname(filePath)).create(recursive: true);
            await File(filePath).writeAsBytes(file.content as List<int>);
          }
        }
        
        setState(() => _htmlPath = p.join(zipDir.path, htmlFile.name));
      } else {
        // Handle single HTML file
        final filePath = p.join(_htmlDir.path, widget.filename);
        await File(filePath).writeAsBytes(widget.fileBytes);
        setState(() => _htmlPath = filePath);
      }
    } catch (e) {
      debugPrint('Error setting up files: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading HTML: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    // For ZIP files, clean up the extracted directory
    if (widget.isZip && _htmlPath != null) {
      final zipDir = Directory(p.dirname(_htmlPath!));
      zipDir.delete(recursive: true).catchError((e) => 
        debugPrint('Error cleaning up ZIP directory: $e')
      );
    }
    super.dispose();
  }

  Future<void> _openInSystemBrowser() async {
    try {
      if (_htmlPath == null) {
        throw 'HTML file not ready';
      }

      await Process.run('chmod', ['644', _htmlPath!]);
      
      // Try to detect default browser and launch with appropriate flags
      final xdgResult = await Process.run('xdg-mime', ['query', 'default', 'text/html']);
      final defaultBrowser = xdgResult.stdout.toString().trim();
      
      debugPrint('Default browser: $defaultBrowser');
      
      final uri = Uri.file(_htmlPath!);
      bool launched = false;
      
      if (defaultBrowser.contains('firefox')) {
        launched = await Process.run('firefox', [
          '--offline',
          '--new-window',
          uri.toString(),
        ]).then((result) => result.exitCode == 0);
      } else if (defaultBrowser.contains('chromium') || defaultBrowser.contains('chrome')) {
        launched = await Process.run('chromium', [
          '--allow-local-file-access',
          '--disable-network-access',
          '--disable-web-security',
          uri.toString(),
        ]).then((result) => result.exitCode == 0);
      }
      
      if (!launched && !await launchUrl(uri, mode: LaunchMode.platformDefault)) {
        throw 'Could not launch $uri';
      }
      
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error opening in system browser: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  String _getSearchScript() {
    if (widget.searchText == null || widget.searchText!.isEmpty) return '';
    
    // Split into words and find first sequence of 5 words containing only letters and numbers
    final allWords = widget.searchText!.split(' ');
    String? searchSequence;
    
    for (var i = 0; i <= allWords.length - 5; i++) {
      final sequence = allWords.skip(i).take(5);
      if (sequence.every((word) => RegExp(r'^[a-zA-Z0-9]+$').hasMatch(word))) {
        searchSequence = sequence.map((word) => word.toLowerCase()).join(' ');
        break;
      }
    }
    
    if (searchSequence == null) {
      debugPrint('No sequence of 5 words containing only alphanumeric characters found');
      return '';
    }
    
    debugPrint('Searching for text: "$searchSequence"');
    final escapedText = searchSequence.replaceAll("'", "\\'").replaceAll('"', '\\"');
    
    return '''
      function findText(searchText) {
        console.log('Starting search for: "' + searchText + '"');
        
        // Use the browser's find functionality
        if (window.find(searchText, false, false, true)) {
          // If found, scroll the selection into view
          const selection = window.getSelection();
          if (selection.rangeCount > 0) {
            selection.getRangeAt(0).startContainer.parentElement.scrollIntoView({
              behavior: 'smooth',
              block: 'center'
            });
          }
        } else {
          console.log('Text not found');
        }
      }
      
      findText('$escapedText');
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filename),
      ),
      body: FutureBuilder<void>(
        future: _htmlPath == null ? Future.value() : Future.value(_htmlPath),
        builder: (context, snapshot) {
          if (_htmlPath == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (Platform.isLinux) {
            _openInSystemBrowser();
            return const Center(child: Text('Opening in system browser...'));
          }

          return InAppWebView(
            initialOptions: InAppWebViewGroupOptions(
              crossPlatform: InAppWebViewOptions(
                useShouldOverrideUrlLoading: true,
                javaScriptEnabled: true,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                resourceCustomSchemes: ['file'],
                javaScriptCanOpenWindowsAutomatically: false,
              ),
              android: AndroidInAppWebViewOptions(
                allowFileAccess: true,
                allowContentAccess: true,
                useHybridComposition: true,
                blockNetworkLoads: true,
                networkAvailable: false,
              ),
            ),
            initialUrlRequest: URLRequest(
              url: WebUri(Uri.file(_htmlPath!).toString()),
            ),
            onLoadStop: (controller, url) async {
              if (widget.searchText != null && widget.searchText!.isNotEmpty) {
                controller.addJavaScriptHandler(
                  handlerName: 'consoleLog',
                  callback: (args) {
                    debugPrint('JS Console: ${args.join(' ')}');
                  },
                );
                
                // Add console.log override to see logs
                await controller.evaluateJavascript(source: '''
                  console.log = function() {
                    window.flutter_inappwebview.callHandler('consoleLog', ...arguments);
                  };
                ''');
                
                await controller.evaluateJavascript(
                  source: _getSearchScript(),
                );
              }
            },
            onLoadError: (controller, url, code, message) {
              debugPrint('Failed to load: $url - Error: $message');
            },
          );
        },
      ),
    );
  }
} 