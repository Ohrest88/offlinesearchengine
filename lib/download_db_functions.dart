import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:objectbox/objectbox.dart';
import 'main.dart';  // For MyApp and store references
import 'objectbox.g.dart';  // Add this import for openStore

class DialogState {
  final String message;
  final bool showProgress;
  final bool isComplete;

  DialogState({
    required this.message,
    required this.showProgress,
    required this.isComplete,
  });
}

Future<void> downloadAndImportDB(BuildContext context, String url) async {
  try {
    // Create a state holder for the dialog
    final dialogState = ValueNotifier<DialogState>(
      DialogState(
        message: 'Starting download...',
        showProgress: true,
        isComplete: false,
      ),
    );
    
    try {
      // Show a single dialog that we'll keep updating
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return WillPopScope(
            onWillPop: () async => false,
            child: ValueListenableBuilder<DialogState>(
              valueListenable: dialogState,
              builder: (context, state, _) {
                if (state.isComplete) {
                  return AlertDialog(
                    title: const Text('Success'),
                    content: const Text(
                      'Database has been successfully imported.\nThe app will now restart.'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Remove any app restart code here
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  );
                }
                
                return AlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.showProgress) 
                        const CircularProgressIndicator(),
                      if (state.showProgress)
                        const SizedBox(height: 16),
                      Text(state.message),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(appDir.path, 'objectbox');
      final tempPath = path.join(appDir.path, 'temp_db');

      debugPrint('Starting HTTPS request to: $url');
      final client = http.Client();
      final uri = Uri.https(
        'storage.googleapis.com',
        '/semantic_engine_1/1.1.0/data.mdb.zip'
      );
      final request = http.Request('GET', uri);
      
      try {
        final response = await client.send(request);
        debugPrint('Response status code: ${response.statusCode}');
        debugPrint('Response headers: ${response.headers}');

        if (response.statusCode != 200) {
          throw Exception('Failed to download database: ${response.statusCode}\nHeaders: ${response.headers}');
        }

        final contentLength = response.contentLength ?? 0;
        debugPrint('Total file size: ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB');

        List<int> bytes = [];
        int downloaded = 0;

        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          downloaded += chunk.length;
          
          final progress = contentLength > 0 ? downloaded / contentLength : 0.0;
          final downloadedMB = (downloaded / 1024 / 1024).toStringAsFixed(2);
          final totalMB = (contentLength / 1024 / 1024).toStringAsFixed(2);
          
          dialogState.value = DialogState(
            message: 'Downloading: $downloadedMB MB / $totalMB MB\n${(progress * 100).toStringAsFixed(1)}%',
            showProgress: true,
            isComplete: false,
          );
        }

        debugPrint('Download complete, saving file...');
        final tempFile = File(path.join(tempPath, 'db.zip'));
        await Directory(tempPath).create(recursive: true);
        await tempFile.writeAsBytes(bytes);

        dialogState.value = DialogState(
          message: 'Replacing database...',
          showProgress: true,
          isComplete: false,
        );
        
        debugPrint('Closing current store...');
        StoreManager.close();

        debugPrint('Deleting existing database...');
        if (await Directory(dbPath).exists()) {
          await Directory(dbPath).delete(recursive: true);
        }

        dialogState.value = DialogState(
          message: 'Extracting new database...',
          showProgress: true,
          isComplete: false,
        );
        
        debugPrint('Extracting new database...');
        await extractZipFile({
          'zipPath': tempFile.path,
          'extractPath': dbPath,
        });
        
        dialogState.value = DialogState(
          message: 'Opening new database...',
          showProgress: true,
          isComplete: false,
        );
        
        debugPrint('Opening new database...');
        await StoreManager.initialize();

        // Show success state
        dialogState.value = DialogState(
          message: 'Database successfully imported!',
          showProgress: false,
          isComplete: true,
        );

      } catch (e) {
        debugPrint('Error during HTTP request: $e');
        rethrow;
      } finally {
        client.close();
      }

    } catch (e) {
      debugPrint('Error in downloadAndImportDB: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      if (context.mounted) {
        Navigator.of(context).pop(); // Close the progress dialog
        
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to import database: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('Error in downloadAndImportDB: $e');
    debugPrint('Stack trace: ${StackTrace.current}');
    if (context.mounted) {
      Navigator.of(context).pop(); // Close the progress dialog
      
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to import database: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

Future<void> extractZipFile(Map<String, String> args) async {
  final bytes = File(args['zipPath']!).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  
  for (final file in archive) {
    final filename = file.name;
    if (file.isFile) {
      final data = file.content as List<int>;
      File(path.join(args['extractPath']!, filename))
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
    }
  }
}

/// Shows a confirmation dialog before starting the download.
/// Returns true if user confirms, false otherwise.
Future<bool> showDownloadConfirmationDialog(BuildContext context) async {
  // First, get the file size
  try {
    final uri = Uri.https(
      'storage.googleapis.com',
      '/semantic_engine_1/1.1.0/data.mdb.zip'
    );
    final response = await http.head(uri);
    
    if (!context.mounted) return false;
    
    final contentLength = int.parse(response.headers['content-length'] ?? '0');
    final sizeInMB = contentLength / (1024 * 1024);
    final sizeText = sizeInMB >= 1000 
        ? '${(sizeInMB / 1024).toStringAsFixed(2)} GB'
        : '${sizeInMB.toStringAsFixed(2)} MB';

    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Download Confirmation'),
          content: Text(
            '''
Disclaimer: Downloading the pre-populated database is optional and serves a demo purpose. It does not provide comprehensive information, and we do not guarantee the accuracy, completeness, or reliability of the included PDFs. Always verify the information independently before use.

This operation will download and automatically import a database that's already populated with publicly available information on topics such as First Aid, water purification, improvised shelters, and more.

If you proceed, the current database will be deleted and replaced with the downloaded one.\n

Current download size: $sizeText
            ''',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Download and Import'),
            ),
          ],
        );
      },
    );
    
    return shouldProceed ?? false;
  } catch (e) {
    if (!context.mounted) return false;
    
    // Show error dialog if we couldn't get the file size
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text('Could not get file size: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return false;
  }
}

/// Checks if the database is empty and shows a dialog offering to download pre-indexed content
Future<void> checkAndOfferPreIndexedDB(BuildContext context) async {
  // Check if database is empty by counting sections
  final sectionBox = StoreManager.sectionBox;
  final sectionCount = sectionBox.count();

  if (sectionCount == 0) {
    if (!context.mounted) return;
    
    final shouldDownload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Database is empty'),
          content: const Text(
            '''Your database is empty right now, meaning that there will be no search results until you either add your own PDFs or download a pre-populated database. Do you want to download a pre-populated database that comes with essential details on topics such as First Aid, water purification, improvised shelters, and more?

Note: If you decide not to download it, you can still do so later by navigating to the Settings and selecting "Download and import Pre-populated DB.\''''
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No, thanks'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, take me to the download dialog'),
            ),
          ],
        );
      },
    );

    if (shouldDownload == true && context.mounted) {
      final confirmed = await showDownloadConfirmationDialog(context);
      if (confirmed) {
        await downloadAndImportDB(
          context,
          'https://storage.googleapis.com/semantic_engine_1/1.1.0/data.mdb.zip',
        );
      }
    }
  }
} 