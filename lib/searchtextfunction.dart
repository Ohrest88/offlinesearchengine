import 'dart:io';
import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart';
import 'dart:math' show min;
import 'package:offline_engine/src/rust/api/rustpotion.dart' as rustpotion;

import 'main.dart';
import 'objectbox.g.dart';

Future<List<SearchResult>> performSearch(
  String searchText,
  BuildContext context,
) async {
  try {
    // Always use the StoreManager to get the boxes
    final sectionBox = StoreManager.sectionBox;
    
    debugPrint("Starting hybrid search for: '$searchText'");

    // Extract exact phrases (words in quotes)
    final RegExp phraseRegExp = RegExp(r'"([^"]+)"');
    final Iterable<Match> matches = phraseRegExp.allMatches(searchText);
    final List<String> exactPhrases =
        matches.map((match) => match.group(1)!.toLowerCase()).toList();

    // Determine the text to use for semantic embedding
    String semanticSearchText;
    if (exactPhrases.isNotEmpty) {
      semanticSearchText = searchText;
    } else {
      semanticSearchText = searchText.replaceAll(phraseRegExp, '').trim();
      if (semanticSearchText.isEmpty) {
        semanticSearchText = searchText;
      }
    }

    // Generate an embedding for the semantic search text
    final queryEmbedding = await getEmbedding(semanticSearchText);
    debugPrint("Generated query embedding, length: ${queryEmbedding.length}");

    debugPrint("\n=== Starting hybrid search ===");
    if (exactPhrases.isNotEmpty) {
      debugPrint("Exact phrases: ${exactPhrases.join(', ')}");
    } else {
      debugPrint("No exact phrases specified, doing pure semantic search");
    }

    // CASE 1: Pure semantic search (no exact phrases)
    if (exactPhrases.isEmpty) {
      final vectorCondition = DocumentSection_.embedding.nearestNeighborsF32(queryEmbedding, 20);
      final vectorQuery = sectionBox.query(vectorCondition).build();
      final resultsWithScores = vectorQuery.findWithScores();
      vectorQuery.close();
      debugPrint("Vector search found ${resultsWithScores.length} sections");

      final List<SearchResult> results = resultsWithScores
          .map((result) {
            final similarity = 1.0 - (result.score / 2.0);
            debugPrint("Document ID: ${result.object.id}, cosine similarity: ${similarity.toStringAsFixed(4)}");
            return SearchResult(result.object, similarity);
          })
          .where((result) => result.similarity > 0.6)
          .toList();

      results.sort((a, b) => b.similarity.compareTo(a.similarity));
      return results;
    } 
    // CASE 2: Hybrid search (exact phrases provided)
    else {
      // Step 1: Keyword Filtering
      final Condition<DocumentSection> keywordCondition = exactPhrases
          .map((phrase) =>
              DocumentSection_.content.contains(phrase, caseSensitive: false))
          .reduce((prev, element) => prev & element);
      final keywordQuery = sectionBox.query(keywordCondition).build();
      keywordQuery.limit = 1000;

      final List<DocumentSection> candidateEntries = keywordQuery.find();
      keywordQuery.close();
      debugPrint("Keyword search found ${candidateEntries.length} sections containing all keywords");

      if (candidateEntries.isEmpty) {
        return [];
      }

      // Create a map of candidate IDs to original candidates
      final Map<int, DocumentSection> candidateMap = {
        for (var candidate in candidateEntries) candidate.id: candidate
      };

      // Step 2: Clone candidates and create a temporary store
      final tempDir = await Directory.systemTemp.createTemp('objectbox_temp');
      final tempStore = Store(getObjectBoxModel(), directory: tempDir.path);
      final Box<DocumentSection> tempBox = tempStore.box<DocumentSection>();
      final List<DocumentSection> candidateClones =
          candidateEntries.map((e) => e.clone()).toList();
      tempBox.putMany(candidateClones);
      debugPrint("Temporary store created with ${candidateClones.length} candidate entries");

      // Step 3: Run the vector search (ANN) on the temporary box
      final vectorCondition = DocumentSection_.embedding.nearestNeighborsF32(queryEmbedding, 20);
      final vectorQuery = tempBox.query(vectorCondition).build();
      final resultsWithScores = vectorQuery.findWithScores();
      vectorQuery.close();
      tempStore.close();
      await tempDir.delete(recursive: true);
      debugPrint("Vector ranking on candidate set found ${resultsWithScores.length} sections");

      // Step 4: Process and rank the results
      final List<SearchResult> results = resultsWithScores.map((result) {
        final similarity = 1.0 - (result.score / 2.0);
        final originalId = result.object.originalId;
        DocumentSection? original;
        if (originalId != null && candidateMap.containsKey(originalId)) {
          original = candidateMap[originalId];
        }
        debugPrint("Document ID: ${original?.id ?? result.object.id}, cosine similarity: ${similarity.toStringAsFixed(4)}");
        return original != null ? SearchResult(original, similarity) : null;
      }).whereType<SearchResult>().toList();

      results.sort((a, b) => b.similarity.compareTo(a.similarity));
      return results.take(10).toList();
    }
  } catch (e, stackTrace) {
    debugPrint("Error during search: $e");
    debugPrint("Stack trace: $stackTrace");
    
    // Try to reinitialize if store is closed
    if (e.toString().contains("Store is closed")) {
      try {
        await StoreManager.initialize();
        // You could retry the search here if needed
      } catch (reinitError) {
        debugPrint("Failed to reinitialize store: $reinitError");
      }
    }
    
    return [];
  }
}

Future<List<double>> getEmbedding(String text) async {
  return await rustpotion.getEmbeddingFromRustpotion(text: text);
}