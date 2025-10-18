import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../main.dart';  // For ProcessingDialog
import 'process_file_isolate.dart';  // For ProcessFileArgs and processFileInIsolate

// Add ProcessingDialog here
class ProcessingDialog extends StatefulWidget {
  final String initialStatus;
  final double? progress;
  final ReceivePort receivePort;

  const ProcessingDialog({
    super.key,
    required this.initialStatus,
    this.progress,
    required this.receivePort,
  });

  @override
  State<ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<ProcessingDialog> {
  String _status = '';
  String _fileProgress = '';
  String _filename = '';

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _fileProgress = widget.initialStatus;
    
    widget.receivePort.listen((message) {
      if (message is String && mounted) {
        if (message == '__COMPLETE__') {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        } else {
          setState(() {
            // Split the message into parts
            final parts = message.split('\n');
            if (parts.length >= 3) {
              // For multiple files
              _fileProgress = parts[0];  // "Processing file X/Y"
              _filename = parts[1];      // Filename
              _status = parts[2];        // Operation status
            } else if (parts.length == 2) {
              // For single file
              _filename = parts[0];      // Filename
              _status = parts[1];        // Operation status
            } else {
              _status = message;         // Fallback for simple messages
            }
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.progress != null)
            CircularProgressIndicator(value: widget.progress)
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 16),
          if (_fileProgress.isNotEmpty && _fileProgress != _filename)
            Text(
              _fileProgress,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          if (_fileProgress.isNotEmpty && _fileProgress != _filename)
            const SizedBox(height: 8),
          Text(
            _filename,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _status,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

Future<void> processDocumentFile(BuildContext context, {
  required String filePath,
  required String filename,
  required List<int> fileBytes,
  required String fileType,
  int currentFileIndex = 1,
  int totalFiles = 1,
}) async {
  final receivePort = ReceivePort();

  try {
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ProcessingDialog(
          initialStatus: totalFiles > 1 
              ? 'Processing file $currentFileIndex of $totalFiles...'
              : filename,
          receivePort: receivePort,
        ),
      );
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = '${appDir.path}/objectbox';

    final args = ProcessFileArgs(
      filePath: filePath,
      currentFileIndex: currentFileIndex,
      totalFiles: totalFiles,
      dbPath: dbPath,
      filename: filename,
      fileBytes: fileBytes,
      fileType: fileType,
      rootIsolateToken: RootIsolateToken.instance!,
      sendPort: receivePort.sendPort,
    );

    final result = await compute(processFileInIsolate, args);

    if (result != null) {
      if (result.startsWith('success:')) {
        final sectionCount = int.parse(result.split(':')[1]);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..removeCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Added "${args.filename}" with $sectionCount sections'),
                backgroundColor: Colors.green,
              ),
            );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Error processing file: $result'),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  } catch (e) {
    debugPrint('Error processing file: $e');
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    receivePort.close();
  }
}
