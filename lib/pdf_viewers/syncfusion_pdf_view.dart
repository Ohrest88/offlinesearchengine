
/*
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:typed_data';

class PDFViewerPage extends StatelessWidget {
  final List<int> fileBytes;
  final String searchText;
  final String title;
  final int initialPage;

  const PDFViewerPage({
    Key? key,
    required this.fileBytes,
    required this.searchText,
    required this.title,
    required this.initialPage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Container(
        child: SfPdfViewer.memory(
          Uint8List.fromList(fileBytes),
          initialPageNumber: initialPage,
        ),
      ),
    );
  }
} 

*/