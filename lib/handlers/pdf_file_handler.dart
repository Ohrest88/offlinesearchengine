import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../processors/document_processor.dart';
import '../handlers/database_handler.dart';  // Add this import

// Update ProcessingDialog to handle status updates
class ProcessingDialog extends StatefulWidget {
  final String initialStatus;
  final double? progress;

  const ProcessingDialog({
    super.key,
    required this.initialStatus,
    this.progress,
  });

  @override
  State<ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<ProcessingDialog> {
  String _status = '';

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
  }

  void updateStatus(String newStatus) {
    if (mounted) {
      setState(() {
        _status = newStatus;
      });
    }
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
          Text(
            _status,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

Future<void> handlePdfFileSelection(BuildContext context) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        final bytes = await File(file.path!).readAsBytes();
        await processDocumentFile(
          context,
          filePath: file.path!,
          filename: file.name,
          fileBytes: bytes,
          fileType: 'pdf',
        );
        
        // Add this line to clean up cache after processing
        await clearCache();
      }
    }
  } catch (e) {
    debugPrint("Error picking PDF file: $e");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing file: $e')),
      );
    }
  }
}

Future<void> handleMultiplePdfFiles(BuildContext context) async {
  try {
    if (Platform.isAndroid) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      if (result != null) {
        for (var i = 0; i < result.files.length; i++) {
          var file = result.files[i];
          if (file.path != null && context.mounted) {
            final bytes = await File(file.path!).readAsBytes();
            await processDocumentFile(
              context,
              filePath: file.path!,
              filename: file.name,
              fileBytes: bytes,
              fileType: 'pdf',
              currentFileIndex: i + 1,
              totalFiles: result.files.length,
            );
          }
        }
      }
    } else if (Platform.isLinux) {
      // Use FilePicker to select a directory on Linux
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      // Process all PDF files in the directory
      final dir = Directory(result);
      final List<FileSystemEntity> entities = await dir.list().toList();
      final List<File> pdfFiles = entities
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList();

      if (pdfFiles.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No PDF files found in selected directory')),
          );
        }
        return;
      }

      // Process each PDF file with progress
      for (var i = 0; i < pdfFiles.length; i++) {
        if (context.mounted) {
          final bytes = await pdfFiles[i].readAsBytes();
          await processDocumentFile(
            context,
            filePath: pdfFiles[i].path,
            filename: pdfFiles[i].path.split(Platform.pathSeparator).last,
            fileBytes: bytes,
            fileType: 'pdf',
            currentFileIndex: i + 1,
            totalFiles: pdfFiles.length,
          );
        }
      }
    }
    await clearCache();
  } catch (e) {
    debugPrint("Error picking PDF files: $e");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing files: $e')),
      );
    }
  }
} 