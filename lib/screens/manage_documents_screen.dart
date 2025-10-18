import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart';
import '../pdf_viewers/pdfrx_pdf_view.dart';
import '../main.dart';
import '../objectbox.g.dart';
import '../screens/html_viewer_screen.dart';
import 'dart:math' show min;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';

class DocumentManagerDialog extends StatefulWidget {
  final int pageSize;
  
  const DocumentManagerDialog({
    super.key,
    required this.pageSize,
  });

  @override
  _DocumentManagerDialogState createState() => _DocumentManagerDialogState();
}

class _DocumentManagerDialogState extends State<DocumentManagerDialog> {
  List<Document> _documents = [];
  Map<int, int> _sectionCounts = {};
  String _searchQuery = '';
  int _currentPage = 0;
  int _totalPages = 0;
  int _totalDocuments = 0;
  bool _isLoading = true;
  
  // New variable to control the visibility of the sections button
  bool displaySectionsButton = false;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }
  
  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    
    try {
      Query<Document> query;
      if (_searchQuery.isEmpty) {
        query = StoreManager.documentBox.query().build();
      } else {
        query = StoreManager.documentBox.query(
          Document_.filename.contains(_searchQuery, caseSensitive: false)
        ).build();
      }
      
      _totalDocuments = query.count();
      _totalPages = (_totalDocuments / widget.pageSize).ceil();
      
      query.offset = _currentPage * widget.pageSize;
      query.limit = widget.pageSize;
      _documents = query.find().reversed.toList();
      query.close();
      
      final List<int> documentIds = _documents.map((doc) => doc.id).toList();
      _sectionCounts = await _getSectionCounts(documentIds);
    } catch (e) {
      debugPrint('Error loading documents: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<Map<int, int>> _getSectionCounts(List<int> documentIds) async {
    Map<int, int> counts = {};
    
    for (var docId in documentIds) {
      final countQuery = StoreManager.sectionBox
        .query(DocumentSection_.document.equals(docId))
        .build();
      counts[docId] = countQuery.count();
      countQuery.close();
    }
    
    return counts;
  }
  
  void _changePage(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() {
        _currentPage = page;
      });
      _loadDocuments();
    }
  }
  
  void _deleteDocument(Document document) async {
    try {
      final dialogResult = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Delete "${document.filename}"?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      
      if (dialogResult != true) return;
      
      // Create a progress dialog with a key to update it
      final progressDialogKey = GlobalKey<_DeleteProgressDialogState>();
      
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => DeleteProgressDialog(key: progressDialogKey),
        );
        
        // Ensure dialog is shown
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      try {
        debugPrint('Querying sections...');
        progressDialogKey.currentState?.updateProgress(
          'Querying sections...',
          progress: 0,
          isActive: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        final queryStart = DateTime.now();
        final query = StoreManager.sectionBox
          .query(DocumentSection_.document.equals(document.id))
          .build();
        final ids = query.findIds();
        query.close();
        final queryDuration = DateTime.now().difference(queryStart);
        debugPrint('Found ${ids.length} sections to delete (took ${queryDuration.inMilliseconds}ms)');
        
        if (ids.isNotEmpty) {
          progressDialogKey.currentState?.updateProgress(
            'Deleting ${ids.length} sections...',
            progress: 0,
            isActive: true,
          );
          await Future.delayed(const Duration(milliseconds: 50));
          
          // Process in batches of 5
          const batchSize = 50;
          int processedSections = 0;
          int totalSections = ids.length;
          
          // Split into batches
          for (int i = 0; i < ids.length; i += batchSize) {
            // Get current batch (up to batchSize items)
            final endIndex = (i + batchSize < ids.length) ? i + batchSize : ids.length;
            final batchIds = ids.sublist(i, endIndex);
            
            // Delete this batch
            final removedCount = StoreManager.sectionBox.removeMany(batchIds);
            processedSections += removedCount;
            
            // Update progress
            progressDialogKey.currentState?.updateProgress(
              'Deleting sections: $processedSections of $totalSections',
              progress: processedSections / totalSections,
              isActive: true,
            );
            
            // Yield to UI thread
            await Future.delayed(const Duration(milliseconds: 10));
          }
          
          debugPrint('All sections deleted: $processedSections');
        }
        
        // Update progress for document deletion
        progressDialogKey.currentState?.updateProgress(
          'Deleting document...',
          progress: 1.0,
          isActive: true,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Delete the document
        StoreManager.documentBox.remove(document.id);
        debugPrint('Document deleted');
        
        if (mounted) {
          Navigator.of(context).pop(); // Close progress dialog
        }
        
        _loadDocuments();
      } catch (e) {
        debugPrint('Error during deletion: $e');
        if (mounted) {
          Navigator.of(context).pop(); // Close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting document: $e')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error deleting document: $e');
    }
  }
  
  Future<void> _getDatabaseSize() async {
    final appDir = await getApplicationDocumentsDirectory();
    final sizeInBytes = Store.dbFileSize(path.join(appDir.path, 'objectbox'));
    
    String readableSize;
    if (sizeInBytes > 1024 * 1024 * 1024) {
      readableSize = '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (sizeInBytes > 1024 * 1024) {
      readableSize = '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (sizeInBytes > 1024) {
      readableSize = '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    } else {
      readableSize = '$sizeInBytes bytes';
    }
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Database Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total size: $readableSize'),
              Text('Documents: $_totalDocuments'),
              const Text('\nNote: Delete documents to reduce database size'),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }
  
  void _openDocument(Document document, {String? searchText}) {
    if (document.fileType == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfrxViewerPage(
            fileBytes: document.getBytes(),
            title: document.filename,
            searchText: searchText ?? '',
            initialPage: 1,
          ),
        ),
      );
    } else if (document.fileType == 'html' || document.fileType == 'html_zip') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HtmlViewerScreen(
            fileBytes: document.getBytes(),
            filename: document.filename,
            isZip: document.fileType == 'html_zip',
            searchText: searchText,
          ),
        ),
      );
    }
  }

  void _showSectionsDialog(Document document) async {
    final sections = await _getSectionsForDocument(document.id);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sections for ${document.filename}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections.map((section) {
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      section.content,  // Assuming 'content' is a field in your section model
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<List<DocumentSection>> _getSectionsForDocument(int documentId) async {
    final query = StoreManager.sectionBox
        .query(DocumentSection_.document.equals(documentId))
        .build();
    final sections = query.find();
    query.close();
    return sections;
  }

  Future<void> _downloadDocument(Document document) async {
    try {
      // Get bytes from the document
      final bytes = document.getBytes();
      
      // Check if bytes are null or empty
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Document bytes are null or empty');
      }

      if (Platform.isAndroid || Platform.isIOS) {
        // Use FileSaver for mobile platforms
        final filePath = await FileSaver.instance.saveAs(
          name: document.filename,
          bytes: Uint8List.fromList(bytes),
          ext: document.fileType,
          mimeType: MimeType.other,
        );
        
        if (mounted && filePath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved to: $filePath')),
          );
        }
      } else {
        // Use FilePicker for desktop platforms
        String? outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ${document.filename}',
          fileName: document.filename,
          type: FileType.custom,
          allowedExtensions: [document.fileType],
        );
        
        if (outputPath == null) {
          return;
        }
        
        final file = File(outputPath);
        await file.writeAsBytes(bytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File saved to: $outputPath')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Documents'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Documents: $_totalDocuments',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                        icon: const Icon(Icons.chevron_left, size: 20),
                        onPressed: _currentPage <= 0 ? null : () {
                          setState(() {
                            _currentPage--;
                            _isLoading = true;
                          });
                          _loadDocuments();
                        },
                      ),
                      Text(
                        'Page ${_currentPage + 1} / $_totalPages',
                        style: const TextStyle(fontSize: 12),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                        icon: const Icon(Icons.chevron_right, size: 20),
                        onPressed: (_currentPage + 1) * widget.pageSize >= _totalDocuments ? null : () {
                          setState(() {
                            _currentPage++;
                            _isLoading = true;
                          });
                          _loadDocuments();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      thumbVisibility: true,
                      thickness: 6,
                      radius: const Radius.circular(4),
                      child: ListView.separated(
                        itemCount: _documents.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = _documents[index];
                          final sectionCount = _sectionCounts[doc.id] ?? 0;

                          return ListTile(
                            dense: true,
                            visualDensity: const VisualDensity(
                              horizontal: -4,
                              vertical: -4,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            title: Text(
                              doc.filename,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$sectionCount sections',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: const VisualDensity(
                                    horizontal: -4,
                                    vertical: -4,
                                  ),
                                  icon: Icon(
                                    Icons.open_in_new,
                                    size: 16,
                                    color: Colors.blue.shade700,
                                  ),
                                  onPressed: () => _openDocument(doc),
                                ),
                                IconButton(
                                  visualDensity: const VisualDensity(
                                    horizontal: -4,
                                    vertical: -4,
                                  ),
                                  icon: Icon(
                                    Icons.download,
                                    size: 16,
                                    color: Colors.purple.shade700,
                                  ),
                                  onPressed: () => _downloadDocument(doc),
                                ),
                                IconButton(
                                  visualDensity: const VisualDensity(
                                    horizontal: -4,
                                    vertical: -4,
                                  ),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.red.shade700,
                                  ),
                                  onPressed: () => _deleteDocument(doc),
                                ),
                                if (displaySectionsButton)  // Conditionally display the button
                                  IconButton(
                                    visualDensity: const VisualDensity(
                                      horizontal: -4,
                                      vertical: -4,
                                    ),
                                    icon: Icon(
                                      Icons.list,
                                      size: 16,
                                      color: Colors.green.shade700,
                                    ),
                                    onPressed: () => _showSectionsDialog(doc),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// Add this progress dialog class for deletion operations
class DeleteProgressDialog extends StatefulWidget {
  const DeleteProgressDialog({Key? key}) : super(key: key);

  @override
  State<DeleteProgressDialog> createState() => _DeleteProgressDialogState();
}

class _DeleteProgressDialogState extends State<DeleteProgressDialog> with SingleTickerProviderStateMixin {
  String _message = 'Preparing to delete...';
  double _progress = 0.0;
  bool _isActive = false;
  
  // Animation controller for spinner
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
    bool isActive = false,
  }) {
    if (mounted) {
      setState(() {
        _message = message;
        _progress = progress;
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
          // Progress indicator and activity indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: LinearProgressIndicator(value: _progress),
              ),
              
              // Spinning indicator
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