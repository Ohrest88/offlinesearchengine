import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'dart:typed_data';
import '../page_input_dialog.dart';

class PdfrxViewerPage extends StatefulWidget {
  final List<int> fileBytes;
  final String searchText;
  final String title;
  final int initialPage;

  const PdfrxViewerPage({
    Key? key,
    required this.fileBytes,
    required this.searchText,
    required this.title,
    required this.initialPage,
  }) : super(key: key);

  @override
  State<PdfrxViewerPage> createState() => _PdfrxViewerPageState();
}

class _PdfrxViewerPageState extends State<PdfrxViewerPage> {
  final _controller = PdfViewerController();
  late final _textSearcher = SinglePageTextSearcher(_controller, targetPage: widget.initialPage);
  bool _documentLoaded = false;
  final _loadStartTime = DateTime.now();
  bool _hasSearched = false;

  String _getSearchPhrase() {
    // First split by any type of line break
    final lines = widget.searchText.split(RegExp(r'\n|\r\n|\r|\f'));
    if (lines.isEmpty) return '';
    
    // Take only first line and get up to 5 words
    final words = lines[0]
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(5)
        .toList();
    
    return words.join(' ');
  }

  void _update() {
    if (mounted && !_hasSearched && _textSearcher.matches.isNotEmpty) {
      debugPrint('Found match on page ${widget.initialPage}');
      _hasSearched = true;
      // Schedule listener removal for next frame
      Future.microtask(() {
        _textSearcher.removeListener(_update);
      });
    }
  }

  void _jumpToPage() async {
    if (_documentLoaded) {
      await Future.delayed(const Duration(milliseconds: 1000));
      debugPrint('Jumping to page ${widget.initialPage}');
      await _controller.goToPage(pageNumber: widget.initialPage);
      
      final searchPhrase = _getSearchPhrase();
      debugPrint('Starting search with phrase: "$searchPhrase"');
      
      _hasSearched = false;
      _textSearcher.addListener(_update);
      _textSearcher.startTextSearch(
        searchPhrase,
        caseInsensitive: true,
        goToFirstMatch: true,
        searchImmediately: true
      );
    }
  }

  @override
  void dispose() {
    _textSearcher.removeListener(_update);
    _textSearcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PdfViewer.data(
            Uint8List.fromList(widget.fileBytes),
            sourceName: widget.title,
            controller: _controller,
            params: PdfViewerParams(
              enableTextSelection: true,
              maxScale: 3.0,
              minScale: 0.5,
              pagePaintCallbacks: [
                _textSearcher.pageTextMatchPaintCallback,
              ],
              onViewerReady: (document, controller) {
                setState(() {
                  _documentLoaded = true;
                  final loadTime = DateTime.now().difference(_loadStartTime);
                  debugPrint('PDF viewer fully loaded in ${loadTime.inMilliseconds}ms');
                });
                _jumpToPage();
              },
            ),
          ),
          if (!_documentLoaded)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Opening PDF... Large files might take longer'),
                  ],
                ),
              ),
            ),
          // Top toolbar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              elevation: 4,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_in),
                      onPressed: () => _controller.zoomUp(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.zoom_out),
                      onPressed: () => _controller.zoomDown(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.pageview),
                      onPressed: () async {
                        final page = await showDialog<int>(
                          context: context,
                          builder: (context) => PageInputDialog(
                            pageCount: _controller.pageCount ?? 0,
                          ),
                        );
                        if (page != null) {
                          await _controller.goToPage(pageNumber: page);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Navigation buttons
          Positioned(
            left: 16,
            bottom: MediaQuery.of(context).size.height / 2,
            child: FloatingActionButton(
              heroTag: "pageUp",
              onPressed: () {
                final currentPage = _controller.pageNumber;
                if (_documentLoaded && currentPage != null && currentPage > 1) {
                  _controller.goToPage(pageNumber: currentPage - 1);
                }
              },
              child: const Icon(Icons.arrow_upward),
            ),
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height / 2,
            child: FloatingActionButton(
              heroTag: "pageDown",
              onPressed: () {
                final currentPage = _controller.pageNumber;
                final totalPages = _controller.pageCount;
                if (_documentLoaded && 
                    currentPage != null && 
                    totalPages != null && 
                    currentPage < totalPages) {
                  _controller.goToPage(pageNumber: currentPage + 1);
                }
              },
              child: const Icon(Icons.arrow_downward),
            ),
          ),
        ],
      ),
    );
  }
}

class SinglePageTextSearcher extends PdfTextSearcher {
  SinglePageTextSearcher(PdfViewerController controller, {required this.targetPage}) 
    : super(controller);
  
  final int targetPage;
  final List<PdfTextRangeWithFragments> _pageMatches = [];
  PdfTextRangeWithFragments? _activeMatch;
  int _searchSession = 0;

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
  }) {
    debugPrint('startTextSearch called with pattern: $pattern');
    
    // Increment search session to cancel any ongoing search
    _searchSession++;

    bool _patternIsEmpty(Pattern value) {
      if (value is String) return value.isEmpty;
      if (value is RegExp) return value.pattern.isEmpty;
      return false;
    }

    // Start search immediately
    if (_patternIsEmpty(pattern)) {
      _resetTextSearch();
      return;
    }
    
    // Call our internal search directly
    _startTextSearchInternal(
      pattern,
      _searchSession,
      caseInsensitive,
      goToFirstMatch
    );
  }

  void _resetTextSearch() {
    _pageMatches.clear();
    _activeMatch = null;
    notifyListeners();
  }

  @override
  Future<void> _startTextSearchInternal(
    Pattern text,
    int searchSession,
    bool caseInsensitive,
    bool goToFirstMatch,
  ) async {
    debugPrint('_startTextSearchInternal called with text: $text');
    
    await controller?.useDocument((document) async {
      debugPrint('Using document, searching page $targetPage');
      if (targetPage > document.pages.length) return;
      
      // Only search the target page
      final pageText = await loadText(pageNumber: targetPage);
      debugPrint('Loaded text for page $targetPage: ${pageText != null}');
      if (pageText == null) return;
      
      _pageMatches.clear();
      await for (final f in pageText.allMatches(text, caseInsensitive: caseInsensitive)) {
        debugPrint('Found match: ${f.fragments.map((frag) => frag.text).join()}');
        _pageMatches.add(f);
      }
      
      debugPrint('SinglePageTextSearcher: Found ${_pageMatches.length} matches');
      
      if (_pageMatches.isNotEmpty) {
        _activeMatch = _pageMatches[0];
        debugPrint('Set active match: ${_activeMatch?.fragments.map((f) => f.text).join()}');
        
        // Make sure we're on the right page
        await controller?.goToPage(pageNumber: targetPage);
        
        // Ensure the match is visible and highlighted
        await controller?.ensureVisible(
          controller!.calcRectForRectInsidePage(
            pageNumber: targetPage,
            rect: _pageMatches[0].bounds
          ),
          margin: 50,
        );
        
        // Force redraw to show highlight
        controller?.invalidate();
        notifyListeners();
      }
    });
  }

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    // Only load text for our target page
    if (pageNumber != targetPage) return null;
    return await super.loadText(pageNumber: pageNumber);
  }

  @override
  void pageTextMatchPaintCallback(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    if (page.pageNumber != targetPage) return;
    
    debugPrint('Paint callback for page ${page.pageNumber}, matches: ${_pageMatches.length}');
    
    // Only paint matches for our target page
    final matchTextColor = controller?.params.matchTextColor ?? Colors.yellow.withOpacity(0.5);
    final activeMatchTextColor = controller?.params.activeMatchTextColor ?? Colors.orange.withOpacity(0.5);

    // Paint all matches
    for (final match in _pageMatches) {
      final rect = match.bounds.toRect(
        page: page,
        scaledPageSize: pageRect.size
      ).translate(pageRect.left, pageRect.top);
      
      debugPrint('Painting match at $rect');
      
      canvas.drawRect(
        rect,
        Paint()..color = match == _activeMatch ? activeMatchTextColor : matchTextColor
      );
    }
  }

  @override
  List<PdfTextRangeWithFragments> get matches => _pageMatches;
} 