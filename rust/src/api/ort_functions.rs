
/*
use anyhow::Result;
use flutter_rust_bridge::frb;
use ort::session::{builder::GraphOptimizationLevel, Session};
use ort::environment::Environment;
use std::path::PathBuf;
use std::sync::OnceLock;
use ort::value::Value;
use crate::api::tokenizer::encode_text;
use ndarray::{Array2, ArrayView2};
use rayon::prelude::*;

static MODEL: OnceLock<Session> = OnceLock::new();

#[frb(sync)]
pub fn init_model(model_path: String) -> Result<bool> {
    println!("Loading model from: {:?}", model_path);

    #[cfg(target_os = "linux")]
    {
        // Get the executable path
        let exe_path = std::env::current_exe()
            .expect("Failed to get executable path");
        println!("Executable path: {:?}", exe_path);
        
        // The library should be in the same directory as the executable
        let lib_path = exe_path
            .parent()
            .unwrap()
            .join("lib")
            .join("libonnxruntime.so");
        
        println!("Checking if library exists: {:?}", lib_path);
        println!("Library exists: {}", lib_path.exists());
        
        let lib_path_str = lib_path
            .to_str()
            .expect("Invalid path to libonnxruntime.so")
            .to_string();
        
        println!("Loading ORT library from: {}", lib_path_str);
        ort::init_from(lib_path_str)
            .commit()
            .expect("Failed to initialize ORT");
    }

    #[cfg(target_os = "android")]
    {
        println!("Loading ORT library...");
        ort::init_from("libonnxruntime.so")
            .commit()
            .expect("Failed to initialize ORT");
    }
    
    MODEL.get_or_init(|| {
        Session::builder()
            .expect("Failed to create session builder")
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .expect("Failed to set optimization level")
            .with_intra_threads(4)
            .expect("Failed to set threads")
            .commit_from_file(&model_path)
            .expect("Failed to load model")
    });

    Ok(true)
}

fn mean_pooling(token_embeddings: ArrayView2<f32>, attention_mask: &[i64]) -> Vec<f32> {
    let embedding_dim = token_embeddings.shape()[1];
    let mut mean_embedding = vec![0.0; embedding_dim];
    let mut sum_mask = 0.0;

    // Sum embeddings for tokens with attention mask = 1
    for (i, &mask) in attention_mask.iter().enumerate() {
        if mask == 1 {
            for j in 0..embedding_dim {
                mean_embedding[j] += token_embeddings.get((i, j)).copied().unwrap_or(0.0);
            }
            sum_mask += 1.0;
        }
    }

    // Calculate mean
    if sum_mask > 0.0 {
        for val in mean_embedding.iter_mut() {
            *val /= sum_mask;
        }
    }

    // L2 normalize
    let sum_squares: f32 = mean_embedding.iter().map(|&x| x * x).sum();
    let norm = sum_squares.sqrt();
    
    if norm > 0.0 {
        for val in mean_embedding.iter_mut() {
            *val /= norm;
        }
    }

    mean_embedding
}

#[frb(sync)]
pub fn test_model_load(app_dir: String) -> Result<bool> {
    let _model = MODEL.get()
        .ok_or_else(|| anyhow::anyhow!("Model not initialized"))?;
    Ok(true)
}

#[frb(sync)]
pub fn test_model_inference(app_dir: String) -> Result<Vec<f32>> {
    let model = MODEL.get()
        .ok_or_else(|| anyhow::anyhow!("Model not initialized"))?;
    
    // Create input tensors using shape and data tuples
    let input_ids = ([1, 8], vec![101i64, 2023, 2003, 1037, 3793, 6251, 1012, 102]);
    let attention_mask = ([1, 8], vec![1i64, 1, 1, 1, 1, 1, 1, 1]);
    let token_type_ids = ([1, 8], vec![0i64, 0, 0, 0, 0, 0, 0, 0]);

    let outputs = model.run(ort::inputs! {
        "input_ids" => Value::from_array(input_ids)?,
        "attention_mask" => Value::from_array(attention_mask)?,
        "token_type_ids" => Value::from_array(token_type_ids)?
    }?)?;

    // Print available output names
    println!("Available output names: {:?}", outputs.keys().collect::<Vec<_>>());

    // Try to get the first output
    let first_output_name = outputs.keys().next()
        .ok_or_else(|| anyhow::anyhow!("No outputs available"))?;
    
    let tensor = outputs[first_output_name].try_extract_tensor::<f32>()?;
    Ok(tensor.view().as_slice().unwrap().to_vec())
}

#[frb(sync)]
pub fn ort_tokenize_and_infer(text: String) -> Result<Vec<f32>> {
    let model = MODEL.get()
        .ok_or_else(|| anyhow::anyhow!("Model not initialized"))?;
    
    let tokenized = encode_text(text.clone())?;
    
    // Convert to the format needed for inference
    let input_ids = ([1, tokenized.input_ids.len()], 
        tokenized.input_ids.iter().map(|&x| x).collect::<Vec<i64>>());
    let attention_mask = ([1, tokenized.attention_mask.len()], 
        tokenized.attention_mask.iter().map(|&x| x).collect::<Vec<i64>>());
    let token_type_ids = ([1, tokenized.token_type_ids.len()], 
        tokenized.token_type_ids.iter().map(|&x| x).collect::<Vec<i64>>());

    let outputs = model.run(ort::inputs! {
        "input_ids" => Value::from_array(input_ids)?,
        "attention_mask" => Value::from_array(attention_mask)?,
        "token_type_ids" => Value::from_array(token_type_ids)?
    }?)?;

    let first_output_name = outputs.keys().next()
        .ok_or_else(|| anyhow::anyhow!("No outputs available"))?;
    
    let tensor = outputs[first_output_name].try_extract_tensor::<f32>()?;
    let token_embeddings = tensor.view();
    
    // Convert to Array2 with correct dimensions
    let seq_len = tokenized.attention_mask.len();
    let emb_dim = token_embeddings.shape()[2];  // Last dimension is embedding size
    let reshaped = Array2::from_shape_vec((seq_len, emb_dim), 
        token_embeddings.as_slice().unwrap()[..seq_len * emb_dim].to_vec())?;
    
    // Apply mean pooling
    let embedding = mean_pooling(reshaped.view(), &tokenized.attention_mask);

    // Print first few values for debugging
    println!("First 10 values for text '{}': {:?}", text, &embedding[..10.min(embedding.len())]);

    Ok(embedding)
}

#[frb(sync)]
pub fn ort_tokenize_and_infer_many(texts: Vec<String>) -> Result<Vec<Vec<f32>>> {
    let model = MODEL.get()
        .ok_or_else(|| anyhow::anyhow!("Model not initialized"))?;
    let batch_size = 50;  // Maximum batch size
    let mut all_embeddings = Vec::with_capacity(texts.len());
    
    let total_batches = (texts.len() + batch_size - 1) / batch_size;  // Ceiling division
    
    // Process texts in batches
    for (batch_idx, chunk) in texts.chunks(batch_size).enumerate() {
        println!("Processing batch {}/{} ({} entries)", 
            batch_idx + 1, 
            total_batches,
            chunk.len()
        );
        
        // Parallel tokenization of current batch
        let encodings: Vec<_> = chunk.par_iter()
            .map(|text| encode_text(text.clone()))
            .collect::<Result<Vec<_>>>()?;

        println!("Batch {}/{}: Tokenization complete", batch_idx + 1, total_batches);
        
        // Get the padded length and prepare input tensors
        let padded_token_length = encodings[0].input_ids.len();
        
        // Get flattened arrays for current batch
        let input_ids: Vec<i64> = encodings.iter()
            .flat_map(|e| e.input_ids.iter().copied())
            .collect();
        let attention_mask: Vec<i64> = encodings.iter()
            .flat_map(|e| e.attention_mask.iter().copied())
            .collect();
        let token_type_ids: Vec<i64> = encodings.iter()
            .flat_map(|e| e.token_type_ids.iter().copied())
            .collect();

        // Create input tensors with shape [batch_size, sequence_length]
        let input_ids = ([chunk.len(), padded_token_length], input_ids);
        let attention_mask = ([chunk.len(), padded_token_length], attention_mask);
        let token_type_ids = ([chunk.len(), padded_token_length], token_type_ids);

        // Run inference on the current batch
        let outputs = model.run(ort::inputs! {
            "input_ids" => Value::from_array(input_ids)?,
            "attention_mask" => Value::from_array(attention_mask)?,
            "token_type_ids" => Value::from_array(token_type_ids)?
        }?)?;

        let first_output_name = outputs.keys().next()
            .ok_or_else(|| anyhow::anyhow!("No outputs available"))?;
        
        let tensor = outputs[first_output_name].try_extract_tensor::<f32>()?;
        let token_embeddings = tensor.view();
        
        // Process each text's embeddings in current batch
        for (idx, encoded) in encodings.iter().enumerate() {
            let seq_len = encoded.attention_mask.len();
            let emb_dim = token_embeddings.shape()[2];
            
            // Extract this text's embeddings from the batch
            let start_idx = idx * seq_len * emb_dim;
            let end_idx = start_idx + (seq_len * emb_dim);
            let text_embeddings = Array2::from_shape_vec(
                (seq_len, emb_dim),
                token_embeddings.as_slice().unwrap()[start_idx..end_idx].to_vec()
            )?;
            
            // Apply mean pooling
            let embedding = mean_pooling(
                text_embeddings.view(),
                &encoded.attention_mask
            );
            
            all_embeddings.push(embedding);
        }
        
        // Optional: Print when batch is complete
        println!("Completed batch {}/{}", batch_idx + 1, total_batches);
    }

    println!("All {} batches processed successfully", total_batches);
    Ok(all_embeddings)
} 

*/