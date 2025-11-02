import 'package:objectbox/objectbox.dart';
import 'objectbox.g.dart';
import 'dart:math' show min, sqrt, max;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
//import 'package:onnxruntime/onnxruntime.dart';
//import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'page_input_dialog.dart';
import 'screens/faq_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'searchtextfunction.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';  // Add this import
import 'download_db_functions.dart';
import 'screens/manage_documents_screen.dart';
import 'screens/html_viewer_screen.dart';  // Add this import
import 'processors/process_file_isolate.dart';
import 'processors/document_processor.dart';  // Add this import
import 'package:flutter/gestures.dart';  // Add this import
import 'package:url_launcher/url_launcher.dart';  // Add this import

// Make sure you run: flutter pub run build_runner build
//import 'objectbox.g.dart';

import 'package:offline_engine/src/rust/api/simple.dart';
import 'package:offline_engine/src/rust/frb_generated.dart';
//import 'package:offline_engine/src/rust/api/tokenizer.dart' as tokenizer_api;
import 'package:offline_engine/src/rust/api/pdf_text_extractor.dart' as pdf_api;
import 'package:offline_engine/src/rust/api/text_splitter.dart' as text_splitter;
import 'package:offline_engine/src/rust/api/rustpotion.dart' as rustpotion;
//import 'onnxruntime_functions.dart';
//import 'package:offline_engine/src/rust/api/fast_embed.dart' as fast_embed; Don't delete, works on Android but needs .so for onnx runtime for android
//import 'package:offline_engine/src/rust/api/ort_functions.dart' as ort_api;

// Add this import
//import 'pdf_viewers/syncfusion_pdf_view.dart';
import 'pdf_viewers/pdfrx_pdf_view.dart';

// Add this import
import 'handlers/html_file_handler.dart';
import 'handlers/pdf_file_handler.dart';
import 'handlers/webpage_from_url_handler.dart';

// Add this import
import 'package:offline_engine/src/rust/api/fast_html2md_functions.dart' as html2md;

// Add this import
import 'handlers/database_handler.dart';

// Add these constants at the top of the file
//const String MODEL_RELATIVE_PATH = 'assets/pretrainedMiniLM-L6-v2/model_qint8_arm64.onnx';
//const String TOKENIZER_RELATIVE_PATH = 'assets/pretrainedMiniLM-L6-v2/tokenizer_MiniLM-L6-v2.json';

// Add this near the top of the file, after other class declarations
class ProStatus {
  static bool isPro = false;  // Default value, can be changed later
}

@Entity()
class Document {
  @Id()
  int id = 0;

  String filename;
  String fileType;  // 'pdf' or 'txt'
  String hash;      // Store hash for checking duplicates
  String base64Content;  // Store file as base64 string

  Document({
    required this.filename,
    required this.base64Content,
    required this.fileType,
    required this.hash,
  });

  // Helper methods
  List<int> getBytes() {
    return base64Decode(base64Content);
  }

  static String bytesToBase64(List<int> bytes) {
    return base64Encode(bytes);
  }
}

@Entity()
class DocumentSection {
  @Id()
  int id = 0;

  final document = ToOne<Document>();
  String content;
  
  @Property(type: PropertyType.int)
  int pageNumber;
  
  @HnswIndex(
    dimensions: 500,
    distanceType: VectorDistanceType.cosine,
    neighborsPerNode: 16,
    indexingSearchCount: 50
  )
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  // Remove the defaultValue parameter; Dart will initialize this to 0 by default.
  @Property(type: PropertyType.int)
  int originalId = 0;

  DocumentSection({
    this.content = '',
    this.embedding,
    this.pageNumber = 0,
  });

  // Clone method: create a detached copy.
  DocumentSection clone() {
    return DocumentSection(
      content: content,
      embedding: embedding != null ? List<double>.from(embedding!) : null,
      pageNumber: pageNumber,
    )..originalId = id;
  }
}

// Constants
const int CHUNK_SIZE = 1024 * 1024;  // 1MB chunks

// Replace both variables with a single store manager
class StoreManager {
  static Store? _instance;
  
  static Store get instance {
    if (_instance == null || _instance!.isClosed()) {
      throw StateError("Store not initialized or closed");
    }
    return _instance!;
  }
  
  static Box<Document> get documentBox => instance.box<Document>();
  static Box<DocumentSection> get sectionBox => instance.box<DocumentSection>();
  
  static Future<void> initialize([Store? existingStore]) async {
    if (_instance != null && !_instance!.isClosed()) {
      return; // Already initialized
    }
    
    if (existingStore != null) {
      _instance = existingStore;
      debugPrint("Store initialized with existing Store instance");
      return;
    }
    
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(appDir.path, 'objectbox');
    
    _instance = await openStore(
      directory: dbPath,
      maxDBSizeInKB: 15 * 1024 * 1024,
    );
    
    debugPrint("Store initialized successfully");
  }
  
  static void close() {
    if (_instance != null && !_instance!.isClosed()) {
      _instance!.close();
      _instance = null;
      debugPrint("Store closed successfully");
    }
  }

  static bool get isInitialized => instance != null && !instance!.isClosed();
}

// Add this line
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> copyAssetsToAppDir(String appDir) async {
  debugPrint("Starting asset copy to: $appDir");
  
  final modelsDir = Directory(path.join(appDir, 'models', 'RETRIEVAL32M'));  // Add RETRIEVAL32M
  debugPrint("Creating models directory at: ${modelsDir.path}");
  await modelsDir.create(recursive: true);

  final modelDst = File(path.join(modelsDir.path, 'model.safetensors'));
  final tokenizerDst = File(path.join(modelsDir.path, 'tokenizer.json'));

  // Only copy if files don't exist
  if (!await modelDst.exists()) {
    debugPrint("Copying model file...");
    final modelBytes = await rootBundle.load('assets/potion-retrieval-32M/potion-retrieval-32M_model.safetensors');
    debugPrint("Model bytes loaded: ${modelBytes.lengthInBytes} bytes");
    await modelDst.writeAsBytes(modelBytes.buffer.asUint8List());
    debugPrint("Model file copied to: ${modelDst.path}");
  } else {
    debugPrint("Model file already exists at: ${modelDst.path}");
  }

  if (!await tokenizerDst.exists()) {
    debugPrint("Copying tokenizer file...");
    final tokenizerBytes = await rootBundle.load('assets/potion-retrieval-32M/potion-retrieval-32M_tokenizer.json');
    debugPrint("Tokenizer bytes loaded: ${tokenizerBytes.lengthInBytes} bytes");
    await tokenizerDst.writeAsBytes(tokenizerBytes.buffer.asUint8List());
    debugPrint("Tokenizer file copied to: ${tokenizerDst.path}");
  } else {
    debugPrint("Tokenizer file already exists at: ${tokenizerDst.path}");
  }
  
  debugPrint("Asset copy complete");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check and save install date
  final prefs = await SharedPreferences.getInstance();
  final installDate = prefs.getString('install_date');
  
  if (installDate == null) {
    final now = DateTime.now().toIso8601String();
    await prefs.setString('install_date', now);
    debugPrint('First run date saved: $now');
  } else {
    debugPrint('App was first installed on: $installDate');
  }

  // Initialize the Rust bridge
  await RustLib.init();

  // Get the application directory
  final appDir = await getApplicationDocumentsDirectory();
  debugPrint("App directory: ${appDir.path}");

  // Initialize ONNX Runtime and related components
  //await initializeOnnxRuntime();

  // Initialize ObjectBox
  final dbPath = path.join(appDir.path, 'objectbox');
  debugPrint("ObjectBox database location: $dbPath");
  
  // Close any existing store
  StoreManager.close();
  
  // Try to open store with corruption check
  try {
    await StoreManager.initialize();
  } catch (e) {
    if (e.toString().contains('DbPagesCorruptException') || 
        e.toString().contains('page not found')) {
      // Database is corrupted, delete and recreate
      if (await Directory(dbPath).exists()) {
        await Directory(dbPath).delete(recursive: true);
      }
      
      // Create fresh store
      await StoreManager.initialize();
      
      // Show error dialog after app starts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: navigatorKey.currentContext!,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Database Error'),
            content: const Text(
              'Catastrophic error: The database ran into an unrecoverable problem, likely as a result of '
              'a malfunction in a previous action, from exiting the app mid-import, or from insufficient storage during DB import. The database has been restored to default settings.'
              'Please manually delete storage and cache from the App settings. Contact pocketse.contact@gmail.com if this issue persists.'
            ),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      });
    } else {
      rethrow;  // Rethrow other errors
    }
  }

  // Get app directory
  final appDir2 = await getApplicationDocumentsDirectory();
  
  // Copy assets if needed
  await copyAssetsToAppDir(appDir2.path);
  
  // Initialize RustPotion
  rustpotion.initPotion(appDir: appDir2.path);

  // Print database size using static method
  final sizeInBytes = Store.dbFileSize(dbPath);  // Use static method
  final sizeInMB = sizeInBytes / (1024 * 1024);  // Convert to MB
  final sizeInGB = sizeInBytes / (1024 * 1024 * 1024);  // Convert to MB
  if (sizeInGB > 1) {
    debugPrint('ObjectBox database size: ${sizeInGB.toStringAsFixed(3)} GB');
  } else if (sizeInGB < 1) {
    debugPrint('ObjectBox database size: ${sizeInMB.toStringAsFixed(2)} MB');
  } else {
    debugPrint('ObjectBox database size: ${sizeInBytes} bytes');
  }
  
  // After store initialization
  // await checkAndOfferPreIndexedDB(context);

  /*
  // Extract filenames from paths
  final modelFilename = path.basename(MODEL_RELATIVE_PATH);
  final tokenizerFilename = path.basename(TOKENIZER_RELATIVE_PATH);
  
  // Copy model file if needed
  final modelFile = File(path.join(appDir2.path, modelFilename));
  if (!await modelFile.exists()) {
    final bytes = await rootBundle.load(MODEL_RELATIVE_PATH);
    await modelFile.writeAsBytes(bytes.buffer.asUint8List());
    debugPrint("Copied model file to: ${modelFile.path}");
  }
  
  // Copy tokenizer file if needed
  final tokenizerFile = File(path.join(appDir2.path, tokenizerFilename));
  if (!await tokenizerFile.exists()) {
    final bytes = await rootBundle.load(TOKENIZER_RELATIVE_PATH);
    await tokenizerFile.writeAsBytes(bytes.buffer.asUint8List());
    debugPrint("Copied tokenizer file to: ${tokenizerFile.path}");
  }
  
  // Initialize tokenizer and model
  try {
    await tokenizer_api.initTokenizer(tokenizerPath: tokenizerFile.path);
    await ort_api.initModel(modelPath: modelFile.path);
    debugPrint("Successfully initialized tokenizer and model");

    // Test tokenize and inference with actual text
    final textEmbedding = await ort_api.ortTokenizeAndInfer(text: "This is an example sentence");
    debugPrint("Test inference - first 5 values: ${textEmbedding.take(5).toList()}");
  } catch (e) {
    debugPrint("Error initializing model/tokenizer: $e");
  }
  */

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Offline Search Engine',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),  // Light grey background
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 172, 207, 235),  // Even lighter blue color for AppBar
          iconTheme: IconThemeData(color: Colors.white),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFFAFAFA),  // Light background for Drawer
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  String _searchQuery = '';
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  Box<Document>? documentBox;
  Box<DocumentSection>? sectionBox;
  Map<String, String> _filePaths = {};  // Store original file paths
  String? _selectedDirectory;  // Add this field
  bool _isProcessing = false;
  String _processingStatus = '';
  double _processingProgress = 0.0;

  // Add cache for section counts
  Map<int, int>? _sectionCountsCache;

  // Add this field
  late ReceivePort _receivePort;

  // Add this controller
  final TextEditingController _searchController = TextEditingController();

  // Optimized section counts - only get counts for visible documents
  Future<Map<int, int>> _getSectionCounts(List<int> documentIds) async {
    if (documentIds.isEmpty) return {};

    Map<int, int> counts = {};
    
    // Initialize all counts to 0
    for (var id in documentIds) {
      counts[id] = 0;
    }

    // Count sections for each document individually
    for (var docId in documentIds) {
      final count = sectionBox!
        .query(DocumentSection_.document.equals(docId))
        .build()
        .count();  // Use count() instead of find()
      counts[docId] = count;
    }

    return counts;
  }

  @override
  void initState() {
    super.initState();
    // Initialize the store reference
    documentBox = StoreManager.documentBox;
    sectionBox = StoreManager.sectionBox;
    // Add this to check database after widget is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAndOfferPreIndexedDB(context);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();  // Dispose the controller
    // No need to close store here as it's managed globally
    super.dispose();
  }

  void _searchText(String searchText) async {
    // Update the search state
    setState(() {
      _searchQuery = searchText;
      _isSearching = true;
    });

    try {
      final results = await performSearch(searchText, context);
      setState(() {
        _searchResults = results;
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  // Add this helper method to normalize text
  String _normalizeText(String text) {
    // Replace newlines and multiple spaces with single space
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
    //return text;
  }

  Widget _buildHighlightedText() {
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('No results found'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        final document = result.section.document.target!;
        
        // Get search terms to highlight
        final searchTerms = _searchQuery
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
            .split(RegExp(r'\s+'))
            .where((term) => term.length > 3) // Changed from > 2 to > 3
            .toList();

        // Create highlighted content using RichText
        final content = _normalizeText(result.section.content);  // Normalize the content first
        final spans = <TextSpan>[];
        int currentIndex = 0;

        // Skip highlighting if no valid search terms
        if (searchTerms.isEmpty) {
          spans.add(TextSpan(
            text: content,  // Using normalized content
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF202124),
              height: 1.4,
            ),
          ));
        } else {
          // Create regex pattern for all search terms
          final pattern = RegExp(
            searchTerms.map((term) => RegExp.escape(term)).join('|'),
            caseSensitive: false,
          );

          // Find all matches and create spans
          for (final match in pattern.allMatches(content.toLowerCase())) {
            // Add non-matching text before this match
            if (match.start > currentIndex) {
              spans.add(TextSpan(
                text: content.substring(currentIndex, match.start),  // Using normalized content
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF202124),
                  height: 1.4,
                ),
              ));
            }

            // Add the highlighted matching text
            spans.add(TextSpan(
              text: content.substring(match.start, match.end),  // Using normalized content
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF202124),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ));

            currentIndex = match.end;
          }

          // Add any remaining text after the last match
          if (currentIndex < content.length) {
            spans.add(TextSpan(
              text: content.substring(currentIndex),  // Using normalized content
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF202124),
                height: 1.4,
              ),
            ));
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filename as title with page number
              InkWell(
                onTap: () {
                  _openDocument(document, result.section);
                },
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: document.filename,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      // Only show page number for PDF files
                      if (document.fileType == 'pdf')  // Add this condition
                        TextSpan(
                          text: ' - Page ${result.section.pageNumber}',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Similarity score as URL-like text
              Text(
                'Relevance: ${(result.similarity * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green[700],
                ),
              ),
              const SizedBox(height: 8),
              // Content preview with light gray background and highlighted text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                child: RichText(
                  text: TextSpan(
                    children: spans,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Add this to your state class
  static const defaultPdfViewer = 2; // 1 for Syncfusion, 2 for pdfrx

  // Update _openDocument method
  void _openDocument(Document document, DocumentSection section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => document.fileType == 'pdf'
            ? PdfrxViewerPage(
                fileBytes: document.getBytes(),
                title: document.filename,
                searchText: section.content,
                initialPage: section.pageNumber,
              )
            : HtmlViewerScreen(
                fileBytes: document.getBytes(),
                filename: document.filename,
                isZip: document.fileType == 'html_zip',
                searchText: section.content,  // Pass the section content
              ),
      ),
    );
  }

  void _updateProcessingStatus(String status, double progress) {
    debugPrint("Updating status: $status, progress: $progress");
    setState(() {
      _processingStatus = status;
      _processingProgress = progress;
    });
  }

  Future<void> _deleteAllData(BuildContext context) async {
    try {
      // First show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear Database'),
          content: const Text(
            'This will completely delete and recreate the database from zero. '
            'This operation cannot be undone. Are you sure?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Now show progress dialog
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
                Text('Deleting all data...'),
              ],
            ),
          ),
        );
      }

      // Close current store first
      StoreManager.close();

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = path.join(appDir.path, 'objectbox');
      
      // For Linux or any platform, be specific about what to delete
      if (await Directory(dbPath).exists()) {
        debugPrint('Deleting database directory: $dbPath');
        await Directory(dbPath).delete(recursive: true);
      } else {
        debugPrint('Database directory does not exist: $dbPath');
      }

      // Create a new empty database
      await Directory(dbPath).create(recursive: true);
      
      // Reopen store with empty database
      await StoreManager.initialize();

      if (context.mounted) {
        // Close progress dialog
        Navigator.of(context).pop();
        
        // Show completion message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data has been deleted.'),
            backgroundColor: Colors.green,
          ),
        );
        
        setState(() {
          _searchResults = [];
          _searchQuery = '';
          // Reset other state variables as needed
        });
      }
    } catch (e) {
      debugPrint('Error clearing data: $e');
      if (context.mounted) {
        // Close progress dialog
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Scrollbar(  // Add a Scrollbar widget
          thumbVisibility: true,  // Ensure the scrollbar is always visible
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,  // Ensure left alignment for the entire column
              children: [
                // Help & Support section
                _buildDrawerSection(
                  'Help & Support',
                  [
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.help_outline, size: 20, color: Colors.blueGrey),
                      title: const Text(
                        'FAQ / Info / Support',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const FAQScreen()),
                        );
                      },
                      hoverColor: Colors.blue.withOpacity(0.1),
                    ),
                  ],
                ),
                // Document Management section
                _buildDrawerSection('Document Management', [
                  _buildDrawerItem(
                    icon: Icons.picture_as_pdf,
                    title: 'Add PDF',
                    onTap: () {
                      Navigator.pop(context);  // Close drawer first
                      handlePdfFileSelection(context);
                    },
                    infoMessage: 'Add a PDF document to the application for processing. This will add a copy of the document to the database and allow you to search it.',
                  ),
                  _buildDrawerItem(
                    icon: Icons.html,
                    title: 'Add Static HTML File',
                    onTap: () {
                      Navigator.pop(context);
                      _addHtmlFile();
                    },
                    infoMessage: 'Add a local HTML file to the search engine.',
                  ),
                  _buildDrawerItem(
                    icon: Icons.folder,
                    title: 'Add Multiple Files',
                    onTap: () {
                      Navigator.pop(context);  // Close drawer first
                      handleMultipleFiles(context);
                    },
                    infoMessage: 'Select multiple files at once for batch processing. Supported file types are PDF and HTML.',
                  ),
                  _buildDrawerItem(
                    icon: Icons.folder_outlined,
                    title: 'Manage Indexed Documents',
                    onTap: () {
                      Navigator.pop(context);
                      _showDocumentManager();
                    },
                    infoMessage: 'Manage and organize your indexed documents.',
                  ),
                ]),
                // Database section
                _buildDrawerSection(
                  'Database',
                  [
                    ListTile(
                      leading: const Icon(Icons.download),
                      title: const Text('Download and import pre-indexed DB with essential information'),
                      onTap: () async {
                        final confirmed = await showDownloadConfirmationDialog(context);
                        if (confirmed) {
                          await downloadAndImportDB(
                            context,
                            'https://storage.googleapis.com/semantic_engine_1/1.1.0/data.mdb.zip',
                          );
                        }
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.upload_file,
                      title: 'Export Database',
                      onTap: () => exportDatabase(context),
                      infoMessage: 'Export the current database to a file. The extension needs to be .mdb. The exported database will include all documents and metadata.',
                    ),
                    _buildDrawerItem(
                      icon: Icons.download_for_offline,
                      title: 'Import Database',
                      onTap: () => importDatabase(context),
                      infoMessage: 'Import a database from a file. The extension needs to be .mdb',
                    ),
                    _buildDrawerItem(
                      icon: Icons.delete_outline,
                      title: 'Clear Database',
                      onTap: () {
                        Navigator.pop(context);
                        _deleteAllData(context);
                      },
                      infoMessage: 'Clear all data from the database. After this operation, the database will be empty. This operation will reclaim the space that the DB occupied.',
                    ),
                    _buildDrawerItem(
                      icon: Icons.cleaning_services,
                      title: 'Reclaim Disk Space',
                      onTap: () => reclaimDiskSpace(context),
                      infoMessage: 'Use this feature only if you have removed files manually from the "Manage Documents" section. There is a current technical limitation where the database does not automatically free up space when deleting documents from DB. This is useful if you are regularly deleting documents and want to reclaim space after it.',
                    ),
                  ],
                ),
                // Version and Database Size section
                _buildDrawerSection(
                  'App Info',
                  [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),  // Align content with other sections
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          return FutureBuilder<String>(
                            future: _getDatabaseSize(),
                            builder: (context, snapshot) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Version 1.1.0',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Database Size',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    snapshot.data ?? 'Calculating...',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,  // Ensure left alignment
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),  // Consistent padding
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required String infoMessage,
    Color? color,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color ?? Colors.blueGrey),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: color ?? Colors.blueGrey,
              ),
            ),
          ),
          InkWell(
            onTap: () {
              if (title == 'Add Static HTML File') {
                _showHtmlFileInfoDialog(context);
              } else {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Information'),
                    content: Text(infoMessage),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Icon(Icons.info_outline, size: 20, color: color ?? Colors.blueGrey),
            ),
          ),
        ],
      ),
      onTap: onTap,
      hoverColor: Colors.blue.withOpacity(0.1),
    );
  }

  void _showDocumentManager() {
    showDialog(
      context: context,
      builder: (context) {
        return DocumentManagerDialog(
          pageSize: 20,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 172, 207, 235),
        elevation: 1,  // Slightly reduced elevation
        toolbarHeight: 64,
        automaticallyImplyLeading: false,
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              color: Colors.white,
            ),
          ),
        ],
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),  // Subtle white overlay
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/icon/icon.png',
                height: 28,
                width: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              'Offline Search Engine',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,  // Slightly smaller
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,  // Added letter spacing
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.white.withOpacity(0.1),  // Very subtle divider
            height: 1,
          ),
        ),
      ),
      endDrawer: _buildDrawer(),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              // Search bar section
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Center(
                  child: SizedBox(
                    width: 600,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Perform search',
                              prefixIcon: const Icon(Icons.search, color: Colors.grey),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchResults = [];
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,  // White background for search bar
                              contentPadding: const EdgeInsets.symmetric(vertical: 10.0),
                            ),
                            onSubmitted: _searchText,
                            onChanged: (text) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Only show search tips when there are no results and not searching
              if (_searchResults.isEmpty && !_isSearching)
                Center(  // Add this to center the container
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,  // Add this to keep container tight
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb_outline, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text(
                              'Search Tips:',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            children: [
                              TextSpan(
                                text: 'where to find water in the wild',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const TextSpan(
                                text: ' → Semantic search: finds related content even if words don\'t match exactly',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            children: [
                              TextSpan(
                                text: '"reef knot"',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const TextSpan(
                                text: ' → Keyword search: finds sections containing the exact words: reef knot. If many results, tries to select most useful',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            children: [
                              TextSpan(
                                text: '"filter"',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const TextSpan(text: ' '),
                              TextSpan(
                                text: 'water purification',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const TextSpan(
                                text: ' → Hybrid search: results must contain keyword filter, ranked by relevance to the phrase: filter water purification',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _buildHighlightedText(),
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          value: _processingProgress,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _processingStatus,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Add this method to calculate database size
  Future<String> _getDatabaseSize() async {
    final appDir = await getApplicationDocumentsDirectory();
    final sizeInBytes = Store.dbFileSize(path.join(appDir.path, 'objectbox'));
    
    if (sizeInBytes > 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (sizeInBytes > 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (sizeInBytes > 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '$sizeInBytes bytes';
    }
  }

  void _showHtmlFileInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Static HTML File'),
        content: Scrollbar(  // Add a Scrollbar widget
          thumbVisibility: true,  // Ensure the scrollbar is always visible
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black, fontSize: 14, height: 1.5),
                    children: [
                      const TextSpan(
                        text: 'Select a HTML file to add to the internal database. It should be a single file (that can contain images/css). \n\n',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(
                        text: 'Tip: There are a number of ways to download web-pages from the Internet as single-file HTML. On Firefox for Android, for example, you can use the extension "SingleFile" (by Gildas Lormeau, ',
                      ),
                      TextSpan(
                        text: 'https://github.com/gildas-lormeau/SingleFile',
                        style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final url = 'https://addons.mozilla.org/en-US/android/addon/single-file/';
                            if (await canLaunch(url)) {
                              await launch(url);
                            } else {
                              throw 'Could not launch $url';
                            }
                          },
                      ),
                      const TextSpan(
                        text: ').\n\nAfter you install the extension, you can navigate to a web-page and download it as a single-file HTML as shown below.',
                      ),
                      const TextSpan(
                        text: '\nGet the extension here: ',
                      ),
                      TextSpan(
                        text: 'Mozilla Add-ons',
                        style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () async {
                            final url = 'https://addons.mozilla.org/en-US/android/addon/single-file/';
                            if (await canLaunch(url)) {
                              await launch(url);
                            } else {
                              throw 'Could not launch $url';
                            }
                          },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Image.asset('assets/images/singlefile_demo.gif'),  // Display the GIF
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _addHtmlFile() {
    handleHtmlFileSelection(context);
  }
}

class TextViewerPage extends StatefulWidget {
  final String filePath;
  final String searchText;  // This will be the content from DB to search for

  const TextViewerPage({
    Key? key,
    required this.filePath,
    required this.searchText,
  }) : super(key: key);

  @override
  State<TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<TextViewerPage> {
  String? _fileContent;
  List<TextSpan>? _highlightedSpans;
  
  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final content = await File(widget.filePath).readAsString();
      final spans = _processHighlights(content);
      if (mounted) {
        setState(() {
          _fileContent = content;
          _highlightedSpans = spans;
        });
      }
    } catch (e) {
      debugPrint('Error reading file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e')),
        );
      }
    }
  }

  List<TextSpan> _processHighlights(String source) {
    final spans = <TextSpan>[];
    
    // Get significant words from search text
    final words = widget.searchText
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 3)
        .take(6)
        .toList();

    // Create pattern for each word individually
    final patterns = words.map((word) => RegExp(
      RegExp.escape(word),
      caseSensitive: false,
      multiLine: true,
    ));

    // Track which parts of the text should be highlighted
    final highlights = List<bool>.filled(source.length, false);

    // Mark positions to highlight for each word
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source.toLowerCase())) {
        for (int i = match.start; i < match.end; i++) {
          highlights[i] = true;
        }
      }
    }

    // Build spans based on highlights
    int currentPos = 0;
    bool isHighlighted = false;
    
    for (int i = 0; i < source.length; i++) {
      if (highlights[i] != isHighlighted) {
        if (currentPos < i) {
          spans.add(TextSpan(
            text: source.substring(currentPos, i),
            style: isHighlighted ? 
              const TextStyle(backgroundColor: Colors.yellow) : 
              null,
          ));
        }
        currentPos = i;
        isHighlighted = highlights[i];
      }
    }

    // Add final span
    if (currentPos < source.length) {
      spans.add(TextSpan(
        text: source.substring(currentPos),
        style: isHighlighted ? 
          const TextStyle(backgroundColor: Colors.yellow) : 
          null,
      ));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(path.basename(widget.filePath))),
      body: _highlightedSpans == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.black),
                  children: _highlightedSpans,
                ),
                ),
              ),
    );
  }
}

List<double> normalizeEmbedding(List<double> embedding) {
  // L2 normalization (unit vector)
  double sumSquares = 0.0;
  for (var val in embedding) {
    sumSquares += val * val;
  }
  
  final norm = sqrt(max(sumSquares, 1e-12));
  if (norm > 1e-12) {
    for (var i = 0; i < embedding.length; i++) {
      embedding[i] /= norm;
    }
  }
  
  // Debug normalization
  double checkNorm = 0.0;
  for (var val in embedding) {
    checkNorm += val * val;
  }
  debugPrint("Normalized vector L2 norm: ${sqrt(checkNorm)}");  // Should be very close to 1.0
  
  return embedding;
}

Future<List<double>> getEmbedding(String text) async {
  //return await ort_api.ortTokenizeAndInfer(text: text);
  return await rustpotion.getEmbeddingFromRustpotion(text: text);
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) throw Exception('Vectors must be of same length');
  
  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  
  for (var i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  
  return dotProduct / (sqrt(normA) * sqrt(normB));
}

// Test function to compare two sentences
Future<void> testEmbeddings() async {
  final sentences = [
    'This is an example sentence',
    'piero was eating an ice cream'
  ];
  
  final appDir = await getApplicationDocumentsDirectory();
  
  debugPrint("\n=== Testing sentence similarity ===");
  debugPrint("Processing sentence 1: ${sentences[0]}");
  final embedding1 = await getEmbedding(sentences[0]);
  
  debugPrint("\nProcessing sentence 2: ${sentences[1]}");
  final embedding2 = await getEmbedding(sentences[1]);
  
  if (embedding1.isNotEmpty && embedding2.isNotEmpty) {
    final similarity = cosineSimilarity(embedding1, embedding2);
    debugPrint('\nCosine similarity: ${similarity.toStringAsFixed(6)}');
    
    // Enhanced debug info
    debugPrint('Embedding 1:');
    debugPrint('  Length: ${embedding1.length}');
    debugPrint('  First 5 values: ${embedding1.take(5).map((e) => e.toStringAsFixed(8)).toList()}');
    debugPrint('  Min: ${embedding1.reduce(min).toStringAsFixed(8)}');
    debugPrint('  Max: ${embedding1.reduce(max).toStringAsFixed(8)}');
    debugPrint('  Mean: ${(embedding1.reduce((a, b) => a + b) / embedding1.length).toStringAsFixed(8)}');
    
    debugPrint('\nEmbedding 2:');
    debugPrint('  Length: ${embedding2.length}');
    debugPrint('  First 5 values: ${embedding2.take(5).map((e) => e.toStringAsFixed(8)).toList()}');
    debugPrint('  Min: ${embedding2.reduce(min).toStringAsFixed(8)}');
    debugPrint('  Max: ${embedding2.reduce(max).toStringAsFixed(8)}');
    debugPrint('  Mean: ${(embedding2.reduce((a, b) => a + b) / embedding2.length).toStringAsFixed(8)}');
  }
  debugPrint("=== Test complete ===\n");
}

class SearchResult {
  final DocumentSection section;
  final double similarity;

  SearchResult(this.section, this.similarity);
}

// Helper function to check if user is legacy
Future<bool> isLegacyUser() async {
  final prefs = await SharedPreferences.getInstance();
  final installDate = prefs.getString('install_date');
  if (installDate == null) return false;
  
  final installed = DateTime.parse(installDate);
  final cutoffDate = DateTime(2024, 6, 1);
  
  return installed.isBefore(cutoffDate);
}

// Add this function to show the blocking progress dialog
void showBlockingProgressDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false, // Prevents dismissing by tapping outside
    builder: (BuildContext context) {
      return WillPopScope(
        onWillPop: () async => false, // Prevents dismissing with back button
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      );
    },
  );
}

// Add this function to hide the progress dialog
void hideProgressDialog(BuildContext context) {
  Navigator.of(context).pop();
}

Future<void> handleMultipleFiles(BuildContext context) async {
  try {
    if (Platform.isLinux) {
      // For Linux, pick a directory
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      final dir = Directory(result);
      final files = await dir.list(recursive: true).where((entity) {
        if (entity is! File) return false;
        final ext = path.extension(entity.path).toLowerCase();
        return ['.pdf', '.html', '.htm', '.zip'].contains(ext);
      }).toList();

      if (files.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No supported files found in selected directory'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final totalFiles = files.length;
      var currentFile = 1;

      for (final file in files) {
        if (file is File) {
          final fileBytes = await file.readAsBytes();
          final fileType = path.extension(file.path).toLowerCase().replaceAll('.', '');
          
          if (context.mounted) {
            await processDocumentFile(
              context,
              filePath: file.path,
              filename: path.basename(file.path),
              fileBytes: fileBytes,
              fileType: fileType,
              currentFileIndex: currentFile,
              totalFiles: totalFiles,
            );
          }
          currentFile++;
        }
      }
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'html', 'htm'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      final totalFiles = result.files.length;
      var currentFile = 1;

      for (final file in result.files) {
        if (file.path == null) continue;

        final fileBytes = await File(file.path!).readAsBytes();
        final fileType = path.extension(file.path!).toLowerCase().replaceAll('.', '');

        if (context.mounted) {
          await processDocumentFile(
            context,
            filePath: file.path!,
            filename: file.name,
            fileBytes: fileBytes,
            fileType: fileType,
            currentFileIndex: currentFile,
            totalFiles: totalFiles,
          );
        }
        currentFile++;
      }
      await clearCache();
    }
  } catch (e) {
    debugPrint('Error picking files: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking files: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> processUserSelectedFiles(BuildContext context) async {
  try {
    // Your existing file processing code
    // ...
    
    // After processing is complete, clear the cache
    await clearCache();
  } catch (e) {
    // Error handling
  }
}

