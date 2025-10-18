use tokenizers::tokenizer::Tokenizer;
use flutter_rust_bridge::frb;
use anyhow::Result;
use std::path::PathBuf;
use std::env;
use std::sync::OnceLock;

static TOKENIZER: OnceLock<Tokenizer> = OnceLock::new();

#[derive(Debug, Clone)]
pub struct TokenizerOutput {
    pub input_ids: Vec<i64>,
    pub token_type_ids: Vec<i64>,
    pub attention_mask: Vec<i64>,
}

/*
fn get_or_init_tokenizer(app_dir: &str) -> Result<&'static Tokenizer> {
    Ok(TOKENIZER.get_or_init(|| {
        let tokenizer_path = PathBuf::from(app_dir)
            .join("tokenizer_MiniLM-L6-v2.json");
        
        eprintln!("Loading tokenizer from: {:?}", tokenizer_path);
        
        Tokenizer::from_file(tokenizer_path.to_str().unwrap())
            .expect("Failed to load tokenizer")
    }))
}
*/
#[frb(sync)]
pub fn init_tokenizer(tokenizer_path: String) -> Result<bool> {
    eprintln!("Loading tokenizer from: {:?}", tokenizer_path);
    
    TOKENIZER.get_or_init(|| {
        Tokenizer::from_file(&tokenizer_path)
            .expect("Failed to load tokenizer")
    });
    
    Ok(true)
}

#[frb(sync)]
pub fn encode_text(input: String) -> Result<TokenizerOutput> {
    let tokenizer = TOKENIZER.get()
        .ok_or_else(|| anyhow::anyhow!("Tokenizer not initialized"))?;
    
    let encoding = tokenizer.encode(input, true)
        .map_err(|e| anyhow::anyhow!("{}", e))?;
    
    Ok(TokenizerOutput {
        input_ids: encoding.get_ids().iter().map(|&x| x as i64).collect(),
        token_type_ids: encoding.get_type_ids().iter().map(|&x| x as i64).collect(),
        attention_mask: encoding.get_attention_mask().iter().map(|&x| x as i64).collect(),
    })
} 