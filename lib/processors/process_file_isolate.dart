import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:isolate';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:objectbox/objectbox.dart';
import '../objectbox.g.dart';
import '../main.dart';  // For Document, DocumentSection, and ProcessFileArgs
import 'package:offline_engine/src/rust/frb_generated.dart';
import 'package:offline_engine/src/rust/api/pdf_text_extractor.dart' as pdf_api;
import 'package:offline_engine/src/rust/api/text_splitter.dart' as text_splitter;
import 'package:offline_engine/src/rust/api/rustpotion.dart' as rustpotion;
import 'package:offline_engine/src/rust/api/fast_html2md_functions.dart' as html2md;
import '../handlers/database_handler.dart';


// Add this at the top level, after imports and before any classes
class ProcessFileArgs {
  final String filePath;
  final int currentFileIndex;
  final int totalFiles;
  final String dbPath;
  final String filename;
  final List<int> fileBytes;
  final String fileType;
  final RootIsolateToken rootIsolateToken;
  final SendPort sendPort;

  ProcessFileArgs({
    required this.filePath,
    required this.currentFileIndex,
    required this.totalFiles,
    required this.dbPath,
    required this.filename,
    required this.fileBytes,
    required this.fileType,
    required this.rootIsolateToken,
    required this.sendPort,
  });
}

// Move this outside of any class, at the top level
Future<String?> processFileInIsolate(ProcessFileArgs args) async {
  Store? store;
  try {
    debugPrint('Starting file processing in isolate...');
    debugPrint('File type: ${args.fileType}');
    debugPrint('Filename: ${args.filename}');
    
    BackgroundIsolateBinaryMessenger.ensureInitialized(args.rootIsolateToken);
    await RustLib.init();
    
    void updateStatus(String status) {
      if (args.totalFiles > 1) {
        // Include both file count and filename
        args.sendPort.send('Processing file ${args.currentFileIndex}/${args.totalFiles}\n${args.filename}\n$status');
      } else {
        // For single file, show filename and status
        args.sendPort.send('${args.filename}\n$status');
      }
    }

    updateStatus('Opening database...');
    try {
      // Instead of directly creating a store, try to initialize StoreManager
      // Note: In the isolate context, we need to create a local instance
      store = Store.attach(getObjectBoxModel(), args.dbPath);
      // This is an isolate, so we create a local StoreManager-compatible implementation
      final documentBox = store.box<Document>();
      final sectionBox = store.box<DocumentSection>();
      
      debugPrint('Successfully attached to existing store');
    } catch (e) {
      debugPrint('Creating new store: $e');
      store = await openStore(
        directory: args.dbPath,
        maxDBSizeInKB: 15 * 1024 * 1024,
      );
    }

    try {
      // Get boxes directly from the local store since StoreManager isn't shared between isolates
      final documentBox = store.box<Document>();
      final sectionBox = store.box<DocumentSection>();

      updateStatus('Checking for duplicates...');
      final hash = sha256.convert(args.fileBytes).toString();
      debugPrint('File hash: $hash');
      
      final query = documentBox.query(Document_.hash.equals(hash)).build();
      final existing = query.findFirst();
      query.close();

      if (existing != null) {
        debugPrint('Duplicate file found with hash: $hash');
        return 'File already exists in database';
      }

      debugPrint('Processing file content...');
      if (args.fileType == 'zip' || args.fileType == 'html_zip') {
        debugPrint('Processing ZIP file...');
        final archive = ZipDecoder().decodeBytes(args.fileBytes);
        
        // Find the main HTML file
        final htmlFile = archive.files.firstWhere(
          (file) => file.name.toLowerCase().endsWith('.html'),
          orElse: () => throw Exception('No HTML file found in zip archive'),
        );
        debugPrint('Found HTML file in ZIP: ${htmlFile.name}');

        // Create a temporary directory to extract the ZIP contents
        final tempDir = await Directory.systemTemp.createTemp('html_process');
        debugPrint('Created temp directory: ${tempDir.path}');

        try {
          // Extract all files to maintain resources (CSS, images, etc.)
          for (final file in archive.files) {
            if (file.isFile) {
              final filePath = path.join(tempDir.path, file.name);
              debugPrint('Extracting: ${file.name}');
              await Directory(path.dirname(filePath)).create(recursive: true);
              await File(filePath).writeAsBytes(file.content as List<int>);
            }
          }

          // Get the path to the extracted HTML file
          final htmlPath = path.join(tempDir.path, htmlFile.name);
          debugPrint('Processing HTML from: $htmlPath');

          // Process the HTML file with its resources
          updateStatus('Converting HTML to text...');
          final extractedText = await html2md.htmlToTextReadability(
            htmlContent: String.fromCharCodes(htmlFile.content as List<int>),
            outputPath: htmlPath,
            width: BigInt.from(80),
          );

          debugPrint('Extracted text length: ${extractedText.length}');
          if (extractedText.isEmpty) {
            return 'No text could be extracted from "${args.filename}"';
          }

          updateStatus('Processing text...');
          final sections = await text_splitter.splitText(
            text: extractedText,
            maxChars: 2000,
          );

          debugPrint('Created ${sections.length} sections');
          if (sections.isEmpty) {
            return 'No sections could be created from "${args.filename}"';
          }

          updateStatus('Computing embeddings for all sections...');
          final embeddings = await rustpotion.getEmbeddingsFromRustpotion(texts: sections);

          if (embeddings.isEmpty) {
            return 'No embeddings could be generated from "${args.filename}"';
          }

          // Create document entry
          updateStatus('Creating document entry...');
          final document = Document(
            filename: args.filename,
            fileType: args.fileType,  // Keep as 'html_zip' to distinguish it
            hash: hash,
            base64Content: Document.bytesToBase64(args.fileBytes),  // Store the complete ZIP
          );

          // Create sections with their embeddings
          final processedSections = <DocumentSection>[];
          for (var i = 0; i < sections.length; i++) {
            processedSections.add(DocumentSection(
              content: sections[i],
              embedding: embeddings[i],
              pageNumber: 1,
            ));
          }

          updateStatus('Saving to database...');
          store.runInTransaction(TxMode.write, () {
            final docId = documentBox.put(document);
            debugPrint('Saved ZIP document with ID: $docId');
            for (var section in processedSections) {
              section.document.target = document;
              final sectionId = sectionBox.put(section);
              debugPrint('Saved section with ID: $sectionId');
            }
          });
          
          debugPrint('Successfully processed and saved ZIP file');
          return 'success:${processedSections.length}';
        } finally {
          // Clean up temporary directory
          debugPrint('Cleaning up temp directory: ${tempDir.path}');
          await tempDir.delete(recursive: true);
        }
      } else if (args.fileType == 'pdf') {
        // Original PDF processing
        updateStatus('Extracting text from PDF...');
        final extractedText = await pdf_api.extractTextFromPdfExtractMultithreaded(pdfBytes: args.fileBytes);
        if (extractedText == null || extractedText.isEmpty) {
          return 'No text could be extracted from "${args.filename}"';
        }

        updateStatus('Processing text by pages...');
        final allSections = <String>[];
        final pageNumbers = <int>[];

        for (var pageData in extractedText) {
          updateStatus('Processing page ${pageData.pageNumber}...');
          final pageSections = await text_splitter.splitText(
            text: pageData.text,
            maxChars: 2000,
          );
          
          allSections.addAll(pageSections);
          pageNumbers.addAll(List.filled(pageSections.length, pageData.pageNumber));
        }

        if (allSections.isEmpty) {
          return 'No sections could be created from "${args.filename}"';
        }

        updateStatus('Computing embeddings for all sections...');
        final embeddings = await rustpotion.getEmbeddingsFromRustpotion(texts: allSections);
        
        if (embeddings.isEmpty) {
          return 'No embeddings could be generated from "${args.filename}"';
        }

        // Create document entry after we know we have valid sections and embeddings
        updateStatus('Creating document entry...');
        final document = Document(
          filename: args.filename,
          fileType: 'pdf',
          hash: hash,
          base64Content: Document.bytesToBase64(args.fileBytes),
        );

        // Create sections with their embeddings
        final processedSections = <DocumentSection>[];
        for (var i = 0; i < allSections.length; i++) {
          processedSections.add(DocumentSection(
            content: allSections[i],
            embedding: embeddings[i],
            pageNumber: pageNumbers[i],
          ));
        }

        updateStatus('Saving to database...');
        store.runInTransaction(TxMode.write, () {
          documentBox.put(document);
          for (var section in processedSections) {
            section.document.target = document;
            sectionBox.put(section);
          }
        });
        return 'success:${processedSections.length}';
      } else if (args.fileType == 'html') {
        // HTML processing
        updateStatus('Converting HTML to text...');
        final extractedText = await html2md.htmlToTextReadability(
          htmlContent: String.fromCharCodes(args.fileBytes),
          outputPath: args.filePath,
          width: BigInt.from(80),
        );

        updateStatus('Processing text...');
        final sections = await text_splitter.splitText(
          text: extractedText,
          maxChars: 2000,
        );

        if (sections.isEmpty) {
          return 'No sections could be created from "${args.filename}"';
        }

        updateStatus('Computing embeddings for all sections...');
        final embeddings = await rustpotion.getEmbeddingsFromRustpotion(texts: sections);

        if (embeddings.isEmpty) {
          return 'No embeddings could be generated from "${args.filename}"';
        }

        // Create document entry
        updateStatus('Creating document entry...');
        final document = Document(
          filename: args.filename,
          fileType: 'html',
          hash: hash,
          base64Content: Document.bytesToBase64(args.fileBytes),
        );

        // Create sections with their embeddings
        final processedSections = <DocumentSection>[];
        for (var i = 0; i < sections.length; i++) {
          processedSections.add(DocumentSection(
            content: sections[i],
            embedding: embeddings[i],
            pageNumber: 1,  // All HTML content is considered page 1
          ));
        }

        updateStatus('Saving to database...');
        store.runInTransaction(TxMode.write, () {
          documentBox.put(document);
          for (var section in processedSections) {
            section.document.target = document;
            sectionBox.put(section);
          }
        });


        

        return 'success:${processedSections.length}';
      }

      return null;
    } finally {
      store.close();
      debugPrint('Store closed');
      // Signal completion to main thread
      args.sendPort.send('__COMPLETE__');
    }
  } catch (e, stackTrace) {
    debugPrint('Error in processFileInIsolate: $e');
    debugPrint('Stack trace: $stackTrace');
    return e.toString();
  }
}