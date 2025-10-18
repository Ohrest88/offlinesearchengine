use rustpotion::{RustPotion, PotionModel};
use flutter_rust_bridge::frb;
use anyhow::Result;
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::Instant;

// Just mark it as opaque without deriving traits
#[frb]
pub struct PotionWrapper(pub(crate) RustPotion);

static POTION: OnceLock<RustPotion> = OnceLock::new();

#[frb(sync)]
pub fn init_potion(app_dir: String) -> Result<bool> {
    let start = Instant::now();
    let model_path = PathBuf::from(&app_dir).join("models");
    
    // Ensure model directory exists
    if !model_path.exists() {
        std::fs::create_dir_all(&model_path)
            .expect("Failed to create model directory");
    }
    
    println!("Initializing RustPotion with model path: {:?}", model_path);
    
    POTION.get_or_init(|| {
        RustPotion::new(PotionModel::RETRIEVAL32M, &model_path)
    });
    
    println!("RustPotion initialization took: {:?}", start.elapsed());
    Ok(true)
}

#[frb(sync)]
pub fn get_embedding_from_rustpotion(text: String) -> Result<Vec<f64>> {
    let potion = POTION.get()
        .ok_or_else(|| anyhow::anyhow!("RustPotion not initialized"))?;
    
    // Truncate text to 400 chars
    let truncated = text.chars().take(2500).collect::<String>();
    Ok(potion.encode(&truncated)
        .into_iter()
        .map(|x| x as f64)
        .collect())
}

#[frb(sync)]
pub fn get_embeddings_from_rustpotion(texts: Vec<String>) -> Result<Vec<Vec<f64>>> {
    let potion = POTION.get()
        .ok_or_else(|| anyhow::anyhow!("RustPotion not initialized"))?;
    
    // Truncate each text to 400 chars before encoding
    let truncated_texts: Vec<String> = texts.into_iter()
        .map(|text| text.chars().take(2500).collect())
        .collect();
    
    Ok(potion.encode_many(truncated_texts)
        .into_iter()
        .map(|vec| vec.into_iter().map(|x| x as f64).collect())
        .collect())
} 