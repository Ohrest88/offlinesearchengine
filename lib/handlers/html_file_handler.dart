import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../objectbox.g.dart';
import '../main.dart';
import 'package:path_provider/path_provider.dart';
import 'package:offline_engine/src/rust/api/fast_html2md_functions.dart' as html2md;
import 'package:flutter/foundation.dart';
import 'dart:isolate';
import 'package:flutter/services.dart';
import '../processors/document_processor.dart';  // Add this import
import '../handlers/database_handler.dart';  // Add this import

// Add this utility function
Future<Directory> getHtmlDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final htmlDir = Directory('${appDir.path}/html_viewer');
  await htmlDir.create(recursive: true);
  return htmlDir;
}

Future<void> handleHtmlFileSelection(BuildContext context) async {
  try {
    // Pick HTML or ZIP file
    final pickerResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      //allowedExtensions: ['html', 'zip'],  // Allow both HTML and ZIP
      allowedExtensions: ['html'],
      allowMultiple: false,
    );

    if (pickerResult == null || pickerResult.files.isEmpty) return;
    
    final file = pickerResult.files.first;
    if (file.path == null) return;

    // Read the file
    final bytes = await File(file.path!).readAsBytes();
    final filename = file.name;
    final isZip = filename.toLowerCase().endsWith('.zip');
    
    if (isZip) {
      // For ZIP files, just store them directly
      debugPrint('Processing ZIP file: $filename');
      await processDocumentFile(
        context,
        filePath: file.path!,
        filename: filename,
        fileBytes: bytes,
        fileType: 'html_zip',
      );
    } else {
      // Regular HTML file handling
      debugPrint('Processing HTML file: $filename');
      final htmlDir = await getHtmlDirectory();
      final htmlFilePath = '${htmlDir.path}/$filename';
      
      // Write HTML file first
      await File(htmlFilePath).writeAsBytes(bytes);

      // Process the file using the common function
      await processDocumentFile(
        context,
        filePath: htmlFilePath,
        filename: filename,
        fileBytes: bytes,
        fileType: 'html',
      );
    }
    await clearCache();
  } catch (e) {
    debugPrint('Error handling file: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
