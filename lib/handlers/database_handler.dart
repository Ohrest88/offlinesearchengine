import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../main.dart';
import '../objectbox.g.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

Future<void> exportDatabase(BuildContext context) async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(appDir.path, 'objectbox/data.mdb');

    // Check if database exists and get its size
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No database found to export')),
        );
      }
      return;
    }

    final dbSize = await dbFile.length();
    debugPrint('Database size: ${(dbSize / (1024 * 1024)).toStringAsFixed(2)} MB');

    // Close the database to ensure the file isn't locked
    StoreManager.close();

    try {
      if (Platform.isAndroid) {
        // For Android, use a streaming method channel approach
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Database'),
            content: const Text(
              'You will be prompted to choose a location to save the database file.\n\n'
              'After selecting a location, the export will begin.'
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('Continue'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );
        
        if (proceed != true) {
          await StoreManager.initialize();
          return;
        }

        // Before making the method channel call, show a progress dialog
        debugPrint('Showing export progress dialog...');
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Exporting database...\nThis may take a while for large files.'),
                ],
              ),
            ),
          );
        }

        // Use the native platform channel with file path instead of bytes
        debugPrint('Starting export via method channel...');
        
        // Create a timeout to ensure the dialog is closed
        bool methodCompleted = false;
        Timer? exportTimer;
        
        exportTimer = Timer(Duration(minutes: 2), () {
          if (!methodCompleted && context.mounted) {
            debugPrint('Export timeout triggered - closing dialog');
            Navigator.of(context).pop(); // Close dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Export is taking longer than expected but may still be in progress. '
                    'Check your download location when complete.'),
                duration: Duration(seconds: 8),
                backgroundColor: Colors.orange,
              ),
            );
          }
        });

        try {
          final result = await MethodChannel('com.pocketsearchengine.app/file_export').invokeMethod<bool>(
            'saveFileStream',
            {
              'filePath': dbPath,
              'fileName': 'pocket_search_engine_${DateTime.now().millisecondsSinceEpoch}.mdb',
              'mimeType': 'application/octet-stream',
            },
          );
          
          methodCompleted = true;
          exportTimer?.cancel();
          
          debugPrint('Export method channel returned: $result');

          // Close the progress dialog after the method call
          debugPrint('Closing export progress dialog...');
          if (context.mounted) {
            Navigator.of(context).pop();
          }

          if (result != true) {
            throw Exception('Failed to save file on Android');
          }
        } catch (e) {
          methodCompleted = true;
          exportTimer?.cancel();
          
          // Close progress dialog on error
          debugPrint('Export method error: $e');
          if (context.mounted) {
            Navigator.of(context).pop();
          }
          rethrow;
        }
      } else {
        // For other platforms, use FilePicker with streams
        final saveLocation = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Database File',
          fileName: 'pocket_search_engine.mdb',
          allowedExtensions: ['mdb'],
          type: FileType.custom,
        );

        if (saveLocation == null) {
          await StoreManager.initialize();
          return;
        }

        // Show progress dialog
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Exporting database...\nThis may take a moment.'),
                ],
              ),
            ),
          );
        }

        // Copy file using streams
        final sourceFile = File(dbPath);
        final targetFile = File(saveLocation);
        
        final sourceStream = sourceFile.openRead();
        final sinkStream = targetFile.openWrite();
        await sourceStream.pipe(sinkStream);
        await sinkStream.flush();
        await sinkStream.close();
        
        // Close progress dialog
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      }

      // Reopen the database
      debugPrint('Reopening database after export...');
      await StoreManager.initialize();

      // Show success dialog
      debugPrint('Showing success dialog...');
      if (context.mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Export Successful'),
            content: const Text('Database exported successfully'),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error in export process: $e');
      await StoreManager.initialize();
      
      // Close progress dialog if open
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      rethrow;
    }
  } catch (e) {
    debugPrint('Error exporting database: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting database: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    if (!StoreManager.isInitialized) {
      await StoreManager.initialize();
    }
  }
}

Future<void> importDatabase(BuildContext context) async {
  try {
    // Let user confirm before proceeding
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Warning'),
        content: const Text(
          'This will replace your current database with the imported one. '
          'All existing data will be lost. Are you sure you want to continue?'
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Import'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    // First show the progress dialog
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => const AlertDialog(
          title: Text('Please Wait'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Import in progress...'),
            ],
          ),
        ),
      );
    }

    // Then pick the file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mdb'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty || !context.mounted) {
      Navigator.of(context).pop(); // Close progress dialog
      return;
    }

    final file = result.files.first;
    if (file.path == null) {
      Navigator.of(context).pop(); // Close progress dialog
      return;
    }

    // Create temporary file path to track it for cleanup
    String? tempFilePath;
    
    try {
      // Continue with database operations
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(appDir.path, 'objectbox');

      // If on Android and the file is in cache/temporary storage, make a note of it for cleanup
      if (Platform.isAndroid && file.path!.contains('cache')) {
        tempFilePath = file.path;
        debugPrint('Temporary file path: $tempFilePath');
      }
      
      // Close current store
      StoreManager.close();

      // Delete existing database
      if (await Directory(dbPath).exists()) {
        await Directory(dbPath).delete(recursive: true);
      }

      // Create database directory
      await Directory(dbPath).create(recursive: true);

      // Copy new database file
      await File(file.path!).copy(path.join(dbPath, 'data.mdb'));

      // Reopen store
      await StoreManager.initialize();

      // Clean up the temporary file if needed
      if (tempFilePath != null && await File(tempFilePath).exists()) {
        try {
          await File(tempFilePath).delete();
          debugPrint('Deleted temporary file: $tempFilePath');
        } catch (e) {
          debugPrint('Failed to delete temporary file: $e');
        }
      }

      if (context.mounted) {
        // Close the "Import in progress" dialog
        Navigator.of(context).pop();
        
        // Show completion dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Import Successful'),
            content: const Text('Database has been imported successfully.'),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                  // No restart needed
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // If any error occurs, make sure to clean up the temporary file
      if (tempFilePath != null && await File(tempFilePath).exists()) {
        try {
          await File(tempFilePath).delete();
          debugPrint('Deleted temporary file after error: $tempFilePath');
        } catch (cleanupError) {
          debugPrint('Failed to delete temporary file after error: $cleanupError');
        }
      }
      
      rethrow; // Re-throw the original error
    }
  } catch (e) {
    debugPrint('Error importing database: $e');
    if (context.mounted) {
      // Close the "Import in progress" dialog if it's showing
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing database: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> reclaimDiskSpace(BuildContext context) async {
  try {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reclaim Disk Space'),
        content: const Text(
          'This will optimize the database by creating a fresh copy and removing unused space. Continue?'
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Continue'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    // Create a dialog that will visibly update
    final progressDialogKey = GlobalKey<_ProgressDialogState>();
    
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => ProgressDialog(key: progressDialogKey),
      );
      
      // Wait to ensure dialog appears
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Create temporary database
    final appDir = await getApplicationDocumentsDirectory();
    final tempDir = await Directory('${appDir.path}/temp_db').create();
    final dbPath = path.join(appDir.path, 'objectbox');
    
    // Update dialog
    progressDialogKey.currentState?.updateProgress(
      'Preparing database...',
      progress: 0,
      useProgressBar: false,
      isActive: true,
    );
    
    // Wait to ensure dialog updates
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Create a separate store with same settings
    final tempStore = await openStore(
      directory: tempDir.path,
      maxDBSizeInKB: 15 * 1024 * 1024,
    );
    
    try {
      // CRITICAL: Use a smaller batch size
      const batchSize = 25; // Reduced from 100
      final docIdMap = <int, int>{};
      
      // Count documents
      final docCount = StoreManager.documentBox.count();
      int processedDocs = 0;
      
      // Update dialog
      progressDialogKey.currentState?.updateProgress(
        'Counting ${docCount.toString()} documents...',
        progress: 0,
        useProgressBar: true,
        isActive: true,
      );
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Get all document IDs (this might take time for very large databases)
      final allDocIds = StoreManager.documentBox.getAll().map((doc) => doc.id).toList();
      
      // Process documents in smaller batches
      for (int i = 0; i < allDocIds.length; i += batchSize) {
        // Update progress dialog after EVERY batch
        progressDialogKey.currentState?.updateProgress(
          'Processing documents... ${processedDocs} of ${docCount}',
          progress: docCount > 0 ? processedDocs / docCount : 0,
          useProgressBar: true,
          isActive: true,
        );
        
        // Yield to UI thread with a slightly longer delay
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Get a batch of IDs
        final batchIds = allDocIds.skip(i).take(batchSize).toList();
        
        // Get documents for this batch
        final docBatch = StoreManager.documentBox.getMany(batchIds);
        
        // Process each document
        for (final doc in docBatch) {
          if (doc != null) {
            final oldId = doc.id;
            doc.id = 0;
            final newId = tempStore.box<Document>().put(doc);
            docIdMap[oldId] = newId;
            processedDocs++;
          }
        }
      }
      
      // Process sections in batches
      final sectionCount = StoreManager.sectionBox.count();
      int processedSections = 0;
      
      // Update dialog
      progressDialogKey.currentState?.updateProgress(
        'Counting ${sectionCount.toString()} sections...',
        progress: 0,
        useProgressBar: true,
        isActive: true,
      );
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Get section IDs
      final allSectionIds = StoreManager.sectionBox.getAll().map((sec) => sec.id).toList();
      
      // Process sections in smaller batches
      for (int i = 0; i < allSectionIds.length; i += batchSize) {
        // Update progress dialog after EVERY batch
        progressDialogKey.currentState?.updateProgress(
          'Processing sections... ${processedSections} of ${sectionCount}',
          progress: sectionCount > 0 ? processedSections / sectionCount : 0,
          useProgressBar: true,
          isActive: true,
        );
        
        // Yield to UI thread
        await Future.delayed(const Duration(milliseconds: 10));
        
        // Get a batch of IDs
        final batchIds = allSectionIds.skip(i).take(batchSize).toList();
        
        // Get sections for this batch
        final sectionBatch = StoreManager.sectionBox.getMany(batchIds);
        
        // Process each section
        for (final section in sectionBatch) {
          if (section != null) {
            final oldDocId = section.document.targetId;
            
            if (oldDocId != null && docIdMap.containsKey(oldDocId)) {
              final newSection = DocumentSection(
                content: section.content,
                embedding: section.embedding,
                pageNumber: section.pageNumber,
              );
              
              newSection.document.targetId = docIdMap[oldDocId];
              tempStore.box<DocumentSection>().put(newSection);
            }
            
            processedSections++;
          }
        }
      }
      
      // Update for final steps
      progressDialogKey.currentState?.updateProgress(
        'Finalizing database...',
        progress: 1.0,
        useProgressBar: true,
        isActive: true,
      );
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Close stores and replace files
      tempStore.close();
      StoreManager.close();
      
      // Replace original database
      await Directory(dbPath).delete(recursive: true);
      await Directory(dbPath).create(recursive: true);
      await File('${tempDir.path}/data.mdb').copy(path.join(dbPath, 'data.mdb'));

      // Reopen store
      await StoreManager.initialize();
      
      // Show completion
      if (context.mounted) {
        Navigator.of(context).pop(); // Close dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database optimization complete'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during database optimization: $e');
      
      try {
        tempStore.close();
      } catch (_) {}
      
      if (!StoreManager.isInitialized) {
        await StoreManager.initialize();
      }
      
      if (context.mounted) {
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error optimizing database: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        debugPrint('Error cleaning up: $e');
      }
    }
  } catch (e) {
    debugPrint('Error in reclaimDiskSpace: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Improved progress dialog with visual activity indicator
class ProgressDialog extends StatefulWidget {
  const ProgressDialog({Key? key}) : super(key: key);

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> with SingleTickerProviderStateMixin {
  String _message = 'Preparing...';
  double _progress = 0.0;
  bool _useProgressBar = false;
  bool _isActive = false;
  
  // Add animation controller for spinner
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void updateProgress(String message, {
    required double progress, 
    required bool useProgressBar,
    bool isActive = false,
  }) {
    if (mounted) {
      setState(() {
        _message = message;
        _progress = progress;
        _useProgressBar = useProgressBar;
        _isActive = isActive;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show progress indicator and spinning icon
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_useProgressBar) 
                Expanded(
                  child: LinearProgressIndicator(value: _progress),
                )
              else
                const CircularProgressIndicator(),
              
              // Add spinning indicator that's always visible
              if (_isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: RotationTransition(
                    turns: _controller,
                    child: const Icon(Icons.sync, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_message),
          // Add a small "working..." text that's always visible during active operations
          if (_isActive)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Working, please wait...',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple function to clear the application cache folders
Future<void> clearCache() async {
  int totalBytesCleared = 0;
  
  try {
    // Get the temporary directory path
    final tempDir = await getTemporaryDirectory();
    debugPrint('Cleaning cache folder: ${tempDir.path}');
    
    if (await tempDir.exists()) {
      // Get all files and folders in the temp directory
      final entities = await tempDir.list().toList();
      debugPrint('Found ${entities.length} items in temp directory');
      
      // Delete each entity, except for objectbox
      for (final entity in entities) {
        final basename = path.basename(entity.path).toLowerCase();
        // Skip the objectbox directory and other important folders
        if (!['objectbox', 'databases', 'shared_prefs'].contains(basename)) {
          try {
            if (await entity.exists()) {
              if (entity is File) {
                // Get and log file size
                final size = await entity.length();
                debugPrint('Deleting file: ${entity.path} (${_formatBytes(size)})');
                await entity.delete();
                totalBytesCleared += size;
                debugPrint('Successfully deleted file: ${entity.path}');
              } else if (entity is Directory) {
                // Log directory contents with sizes
                debugPrint('Examining directory before deletion: ${entity.path}');
                await _logDirectoryContents(entity);
                
                // Get directory size
                final dirStats = await _getDirectorySize(entity);
                final dirSize = dirStats['size'] as int;
                final fileCount = dirStats['files'] as int;
                
                debugPrint('Deleting directory: ${entity.path} (${_formatBytes(dirSize)}, $fileCount files)');
                await entity.delete(recursive: true);
                totalBytesCleared += dirSize;
                debugPrint('Successfully deleted directory: ${entity.path}');
              }
            }
          } catch (e) {
            debugPrint('Error deleting ${entity.path}: $e');
          }
        } else {
          debugPrint('Skipping: ${entity.path}');
        }
      }
    }
    
    debugPrint('Cache clearing completed. Total cleared: ${_formatBytes(totalBytesCleared)}');
  } catch (e) {
    debugPrint('Error clearing cache: $e');
  }
}

// Helper function to list and log directory contents
Future<void> _logDirectoryContents(Directory dir, {String indent = ''}) async {
  try {
    final entities = await dir.list().toList();
    
    for (final entity in entities) {
      if (entity is File) {
        final size = await entity.length();
        debugPrint('$indent - File: ${entity.path} (${_formatBytes(size)})');
      } else if (entity is Directory) {
        debugPrint('$indent + Dir: ${entity.path}');
        // Recurse into subdirectories with increased indent
        await _logDirectoryContents(entity, indent: '$indent  ');
      }
    }
  } catch (e) {
    debugPrint('$indent Error listing directory ${dir.path}: $e');
  }
}

// Helper function to format bytes
String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// Helper function to get directory size
Future<Map<String, dynamic>> _getDirectorySize(Directory dir) async {
  int totalSize = 0;
  int fileCount = 0;

  final entities = await dir.list().toList();
  for (final entity in entities) {
    if (entity is File) {
      totalSize += await entity.length();
      fileCount++;
    } else if (entity is Directory) {
      final dirStats = await _getDirectorySize(entity);
      totalSize += dirStats['size'] as int;
      fileCount += dirStats['files'] as int;
    }
  }

  return {
    'size': totalSize,
    'files': fileCount,
  };
}