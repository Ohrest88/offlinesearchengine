use text_splitter::TextSplitter;
use anyhow::Result;
use crate::api::rustpotion;
use flutter_rust_bridge::frb;

#[flutter_rust_bridge::frb(sync)]
pub fn split_text(text: String, max_chars: i32) -> Result<Vec<String>> {
    //println!("\n=== Starting Basic Text Splitting ===");
    //println!("Original text length: {} chars", text.len());
    //println!("Full text:\n{}\n", text);

    let splitter = TextSplitter::new(350..2500);
    let initial_chunks: Vec<String> = splitter.chunks(&text).map(|s| s.to_string()).collect();
    let initial_len = initial_chunks.len();  // Store length before moving
    
    // Filter out chunks that are too small
    let chunks: Vec<String> = initial_chunks.into_iter()
        .filter(|chunk| chunk.len() >= 200)
        .collect();
    
    //println!("\nSplit into {} chunks (removed {} small chunks):", 
    //    chunks.len(), 
    //    initial_len - chunks.len()
    //);
    
    //for (i, chunk) in chunks.iter().enumerate() {
    //    println!("\nChunk {} (length: {} chars):", i, chunk.len());
    //    println!("Full content:\n{}", chunk);
    //    println!("-----------------");
    //}
    
    //println!("\n=== Finished Basic Text Splitting ===");
    //println!("Total chunks: {}", chunks.len());
    //if !chunks.is_empty() {
    //    let avg_size = chunks.iter().map(|c| c.len()).sum::<usize>() / chunks.len();
    //    println!("Average chunk size: {} chars", avg_size);
    //    println!("Smallest chunk: {} chars", chunks.iter().map(|c| c.len()).min().unwrap());
    //    println!("Largest chunk: {} chars", chunks.iter().map(|c| c.len()).max().unwrap());
    //}
    
    Ok(chunks)
}

#[frb(sync)]
pub fn semantic_chunking(text: String, max_chars: i32) -> Result<Vec<String>> {
    // First do a rough split to get manageable chunks
    let initial_chunks = split_text(text, max_chars)?;
    let mut final_chunks = Vec::new();
    
    // Process chunks sequentially
    let mut current_chunk = String::new();
    let mut last_embedding: Option<Vec<f64>> = None;
    
    for chunk in initial_chunks {
        // Get embedding for current chunk
        let chunk_embedding = rustpotion::get_embedding_from_rustpotion(chunk.clone())?;
        
        // If we have a previous chunk to compare to
        if let Some(last_emb) = &last_embedding {
            // Calculate cosine similarity
            let similarity = cosine_similarity(last_emb, &chunk_embedding);
            
            // If similarity is high (chunks are semantically related)
            if similarity > 0.7 && (current_chunk.len() + chunk.len()) <= max_chars as usize * 4 {
                // Combine chunks
                if !current_chunk.is_empty() {
                    current_chunk.push(' ');
                }
                current_chunk.push_str(&chunk);
            } else {
                // Save current chunk and start new one
                if !current_chunk.is_empty() {
                    final_chunks.push(current_chunk);
                }
                current_chunk = chunk;
            }
        } else {
            // First chunk
            current_chunk = chunk;
        }
        
        last_embedding = Some(chunk_embedding);
    }
    
    // Add the last chunk
    if !current_chunk.is_empty() {
        final_chunks.push(current_chunk);
    }
    
    Ok(final_chunks)
}

#[frb(sync)]
pub fn semantic_chunking_v2(text: String, min_chunk_size: i32) -> Result<Vec<String>> {
    println!("\n=== Starting Semantic Chunking V2 ===");
    println!("Original text length: {} chars", text.len());
    println!("First 100 chars: {}", text.chars().take(100).collect::<String>());
    println!("Min chunk size: {}", min_chunk_size);

    // First split into sentences
    let sentences: Vec<String> = text
        .split('.')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string() + ".")
        .collect();

    println!("\nSplit into {} sentences:", sentences.len());
    for (i, sentence) in sentences.iter().enumerate().take(3) {
        println!("Sentence {}: {}", i, sentence);
    }
    if sentences.len() > 3 {
        println!("... ({} more sentences)", sentences.len() - 3);
    }

    // Early return check
    if sentences.len() <= min_chunk_size as usize {
        println!("Too few sentences ({}), returning original text", sentences.len());
        return Ok(vec![text]);
    }

    // Get embeddings
    println!("\nGetting embeddings for sentences...");
    let sentence_embeddings = rustpotion::get_embeddings_from_rustpotion(sentences.clone())?;
    println!("Got {} embeddings", sentence_embeddings.len());
    
    // Calculate distances
    let mut distances: Vec<f64> = Vec::new();
    for i in 0..sentence_embeddings.len() - 1 {
        let distance = 1.0 - cosine_similarity(&sentence_embeddings[i], &sentence_embeddings[i + 1]);
        distances.push(distance);
    }

    if distances.is_empty() {
        println!("No distances calculated, returning original text");
        return Ok(vec![text]);
    }

    println!("\nCalculated {} distances between consecutive sentences:", distances.len());
    println!("Min distance: {:.3}", distances.iter().fold(f64::INFINITY, |a, &b| a.min(b)));
    println!("Max distance: {:.3}", distances.iter().fold(f64::NEG_INFINITY, |a, &b| a.max(b)));
    println!("First few distances: {:?}", distances.iter().take(3).collect::<Vec<_>>());

    // Calculate threshold
    let mut sorted_distances = distances.clone();
    sorted_distances.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let threshold_idx = (distances.len() * 3) / 4;
    let threshold = sorted_distances[threshold_idx];
    println!("\nUsing threshold {:.3} (75th percentile)", threshold);
    
    // Find breakpoints
    let breakpoints: Vec<usize> = distances.iter()
        .enumerate()
        .filter(|(_, &dist)| dist > threshold)
        .map(|(i, _)| i)
        .collect();

    println!("\nFound {} breakpoints at indices: {:?}", 
        breakpoints.len(),
        if breakpoints.len() > 5 {
            format!("{:?}...", breakpoints.iter().take(5).collect::<Vec<_>>())
        } else {
            format!("{:?}", breakpoints)
        }
    );

    if breakpoints.is_empty() {
        println!("No breakpoints found, returning original text");
        return Ok(vec![text]);
    }

    // Create chunks
    let mut chunks = Vec::new();
    let mut start_idx = 0;
    
    for &breakpoint in &breakpoints {
        if breakpoint - start_idx >= min_chunk_size as usize {
            let chunk = sentences[start_idx..=breakpoint].join(" ");
            let chunk_len = chunk.len();  // Get length before moving
            chunks.push(chunk);
            println!("Created chunk from sentences {}-{} ({} chars)", 
                start_idx, breakpoint, chunk_len);
            start_idx = breakpoint + 1;
        }
    }

    // Add final chunk
    if start_idx < sentences.len() {
        let chunk = sentences[start_idx..].join(" ");
        let chunk_len = chunk.len();  // Get length before moving
        println!("Added final chunk from sentences {}-{} ({} chars)", 
            start_idx, sentences.len()-1, chunk_len);
        chunks.push(chunk);
    }

    if chunks.is_empty() {
        println!("No chunks created, returning original text");
        Ok(vec![text])
    } else {
        println!("\n=== Finished Chunking ===");
        println!("Created {} chunks", chunks.len());
        println!("Average chunk size: {} chars", 
            chunks.iter().map(|c| c.len()).sum::<usize>() / chunks.len());
        Ok(chunks)
    }
}

// Helper function to calculate cosine similarity
fn cosine_similarity(a: &[f64], b: &[f64]) -> f64 {
    let mut dot_product = 0.0;
    let mut norm_a = 0.0;
    let mut norm_b = 0.0;
    
    for (x, y) in a.iter().zip(b.iter()) {
        dot_product += x * y;
        norm_a += x * x;
        norm_b += y * y;
    }
    
    dot_product / (norm_a.sqrt() * norm_b.sqrt())
}