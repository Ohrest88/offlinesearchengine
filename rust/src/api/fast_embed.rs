
/* Don'r delete, works on Android but needs .so for onnx runtime for android
use fastembed::{TextEmbedding, InitOptions, EmbeddingModel};
use flutter_rust_bridge::frb;
use anyhow::Result;
use std::sync::OnceLock;
use std::time::Instant;

static FAST_EMBED: OnceLock<TextEmbedding> = OnceLock::new();
static mut INIT_COUNT: u32 = 0;  // For debugging

fn init_fast_embed() -> TextEmbedding {
    // Safety: This is only used for debugging
    unsafe { 
        INIT_COUNT += 1;
        println!("=== FASTEMBED INITIALIZATION #{} ===", INIT_COUNT);
    }
    
    let start = Instant::now();
    
    println!("Initializing FastEmbed");
    let model = TextEmbedding::try_new(
        InitOptions::new(EmbeddingModel::AllMiniLML6V2)
            .with_show_download_progress(true),
    ).expect("Failed to initialize FastEmbed");
    
    println!("FastEmbed initialization took: {:?}", start.elapsed());
    println!("=== INITIALIZATION COMPLETE ===\n");
    model
}

#[frb(sync)]
pub fn get_embedding_from_fast_embed(text: String) -> Result<Vec<f64>> {
    let start = Instant::now();
    
    let was_initialized = FAST_EMBED.get().is_some();
    let model = FAST_EMBED.get_or_init(init_fast_embed);
    if was_initialized {
        println!("Using existing FastEmbed instance");
    }
    
    // Truncate text to 400 chars to match RustPotion behavior
    //let truncated = text.chars().take(400).collect::<String>();
    
    // Get embedding and convert to f64
    let embeddings = model.embed(vec![text], None)
        .expect("Failed to generate embedding");
    
    let embedding: Vec<f64> = embeddings[0]
        .iter()
        .map(|&x| x as f64)
        .collect();
    
    println!("Embedding generation took: {:?}", start.elapsed());
    Ok(embedding)
}

#[frb(sync)]
pub fn get_embeddings_from_fast_embed(texts: Vec<String>) -> Result<Vec<Vec<f64>>> {
    let model = FAST_EMBED.get()
        .ok_or_else(|| anyhow::anyhow!("FastEmbed not initialized"))?;
    
    /*    
    // Truncate each text to 400 chars to match RustPotion behavior
    let truncated_texts = texts.into_iter()
        .map(|text| text.chars().take(400).collect::<String>())
        .collect::<Vec<_>>();
    */

    for some reason,4 times slower than the other allminilm methods that I had tried
    let embeddings = model.embed(texts, Some (16))
        .expect("Failed to generate embeddings");
    
    Ok(embeddings
        .into_iter()
        .map(|vec| vec.into_iter().map(|x| x as f64).collect())
        .collect())
} 
*/