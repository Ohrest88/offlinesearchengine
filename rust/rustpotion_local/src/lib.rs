use safetensors::SafeTensors;
use serde::Deserialize;
use std::collections::HashMap;
use regex::Regex;

use reqwest::blocking::get;
use std::fs::File;
use std::io::Write;
use std::path::Path;

use rayon::prelude::*;
use memmap2::Mmap;
use std::io::BufReader;

#[derive(Deserialize)]
struct Tokenizer {
    model: ModelVocab,
}

#[derive(Deserialize)]
struct ModelVocab {
    vocab: HashMap<String, i32>, 
}

/*
    Converts a word into corresponding token(s) using the vocab. Matches largest from the right.
    Not performant for long words (!!!)
    Might be optimized with a cache for popular words
*/ 
fn word2tok(mut word: String, vocab: &HashMap<String, i32>) -> Result<Vec<i32>, ()> {
 
    let mut tokens = Vec::new();        // Resulting tokens
    let mut i = word.len();                // Current split index

    while !word.is_empty() {

        /*
            Some tokens are reserved if they appear within a word
            Eg, the "able" token in "unable" vs "able" is different.

            These unique tokens are "continuing-subwords", and are differentiated by starting with a ##.
            In our case we can work backwards and just query our original target but with a ## when we 
            are already working within a word.
        */
        let target = if tokens.len() > 0 {
            format!("##{}", &word[..i])
        } else {
            word[..i].to_string()
        };


        /*
            Start actually querying the vocabulary
         */
        match vocab.get(&target) {
            Some(&candidate) => {
                
                // Token found, push to results and reset split index
                tokens.push(candidate);
                word = word[i..].to_string();
                i = word.len();
            },
            
            None => {

                // Unknown character in the word
                if i == 0 {
                    return Err(());
                }

                // Query missed, continuing shortening word
                i -= 1;
            }
        }
    }

    Ok(tokens)
}

/*
    Split the sentence before attempting to find tokens, specifically to deal with punctuation & spaces.
*/
fn setencen2tok(sentence:&str, vocab:&HashMap<String, i32>) -> Result<Vec<i32>, ()> {

    /*
        Splitting the sentence into words & punctuation
        Regex is quite performant for this
     */

    let re = Regex::new(r"[\w'-]+|[.,!?;]").unwrap();
    let lower = sentence.to_lowercase();
    let lower:String = lower.chars().filter(|&c| c.is_ascii()).collect();
    let words:Vec<&str> = re.find_iter(&lower).map(|mat| mat.as_str()).collect();
    
    /*
        Accumulate found token ids
     */
    let mut all_tokens = vec![];
    for word in words {
        all_tokens.extend(word2tok(word.to_string(), vocab)?)
    }

    return Ok(all_tokens)

}

/*
    Mainly used for loading the model weights as safetensor returns binary data
*/
fn u8_to_f32_vec(v: &[u8]) -> Vec<f32> {
    v.par_chunks_exact(4)
        .map(|chunk| f32::from_le_bytes(chunk.try_into().unwrap()))
        .collect()
}

/*
    Returns size of vector, used later to position embedding on unit circle. 
*/
fn norm(v: &Vec<f32>) -> f32 {
    let sum_of_squares: f32 = v.iter().map(|&x| x * x).sum();
    sum_of_squares.sqrt()
}

fn download_file(url: &str, destination: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let response = get(url)?;
    if !response.status().is_success() {
        return Err(format!("Failed to download file: {}", response.status()).into());
    }
    
    let mut file = File::create(destination)?;
    let content = response.bytes()?;
    file.write_all(&content)?;
    
    Ok(())
}

/*
    Read disk path and load in model "weights"
*/
fn load_embeddings(safetensors_dst: &Path) -> (Vec<f32>, usize) {
    let file = std::fs::File::open(safetensors_dst).unwrap();
    // Memory map the file - this is more efficient for large files
    let mmap = unsafe { Mmap::map(&file).unwrap() };
    let emb_tensors = SafeTensors::deserialize(&mmap).unwrap();
    let embeddings = emb_tensors.tensor("embeddings").unwrap();
    (u8_to_f32_vec(embeddings.data()), embeddings.shape()[1])
}

/*
    Read tokenizer.json - we ignore everything other than vocabulary data for the sake of simplicity
*/
fn load_vocab(tokenizer_dst: &Path) -> HashMap<String, i32> {
    let file = std::fs::read_to_string(tokenizer_dst).expect("Unable to read file");
    let tokenizer: Tokenizer = serde_json::from_str(&file).unwrap();
    tokenizer.model.vocab
}

/*
    Primary struct for loading/inferencing the model
*/
pub struct RustPotion {
    embeddings: Vec<f32>, // flattened 2d array: (vocab, dimensions)
    dimensions: usize,
    vocab: HashMap<String, i32>
}

/*
    Enum for each provided model from minishlab
*/
#[derive(Debug)]
pub enum PotionModel {
    RETRIEVAL32M,
    BASE8M,
    BASE4M,
    BASE2M,
}

/* Additional function for organising destination paths on disk */
impl std::fmt::Display for PotionModel {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl RustPotion {
    /*
        Load model and vocabulary
        
        Example:
        ```
        use rustpotion::{RustPotion, PotionModel};
        let model =  RustPotion::new(PotionModel::BASE2M);
        model.encode("Hello, World!");
        ```
     */
    pub fn new(model_kind: PotionModel, working_directory: &Path) -> Self {
        println!("Starting model initialization...");
        println!("Model kind: {:?}", model_kind);
        println!("Base working directory: {}", working_directory.display());
        
        // Create the model destination directory if it doesn't exist
        let working_directory = working_directory.join(model_kind.to_string());
        println!("Full working directory path: {}", working_directory.display());
        
        if !working_directory.exists() {
            println!("Creating model directory at: {}", working_directory.display());
            std::fs::create_dir_all(&working_directory).unwrap();
        }

        // Define destination paths
        let safetensors_path = working_directory.join("model.safetensors");
        let tokenizer_path = working_directory.join("tokenizer.json");

        println!("Checking paths:");
        println!("  Model path: {}", safetensors_path.display());
        println!("  Tokenizer path: {}", tokenizer_path.display());

        // Check if files exist
        println!("\nChecking files:");
        println!("  Model exists: {}", safetensors_path.exists());
        println!("  Tokenizer exists: {}", tokenizer_path.exists());

        // List directory contents
        if working_directory.exists() {
            println!("\nDirectory contents of {}:", working_directory.display());
            if let Ok(entries) = std::fs::read_dir(&working_directory) {
                for entry in entries {
                    if let Ok(entry) = entry {
                        println!("  - {}", entry.path().display());
                    }
                }
            }
        }

        // Load the model files
        println!("Loading model into memory...");
        let file = match std::fs::File::open(&safetensors_path) {
            Ok(f) => {
                println!("Successfully opened safetensors file");
                f
            },
            Err(e) => {
                println!("Failed to open safetensors file: {}", e);
                panic!("Could not open safetensors file: {}", e);
            }
        };

        let mmap = unsafe { 
            match Mmap::map(&file) {
                Ok(m) => {
                    println!("Successfully memory mapped safetensors file");
                    m
                },
                Err(e) => {
                    println!("Failed to memory map safetensors file: {}", e);
                    panic!("Could not memory map safetensors file: {}", e);
                }
            }
        };

        let emb_tensors = match SafeTensors::deserialize(&mmap) {
            Ok(t) => {
                println!("Successfully deserialized safetensors data");
                t
            },
            Err(e) => {
                println!("Failed to deserialize safetensors data: {}", e);
                panic!("Could not deserialize safetensors data: {}", e);
            }
        };

        let embeddings = match emb_tensors.tensor("embeddings") {
            Ok(e) => {
                println!("Successfully retrieved embeddings tensor");
                e
            },
            Err(e) => {
                println!("Failed to get embeddings tensor: {}", e);
                panic!("Could not get embeddings tensor: {}", e);
            }
        };

        let (embeddings, dimensions) = (u8_to_f32_vec(embeddings.data()), embeddings.shape()[1]);
        println!("Successfully loaded embeddings: {} dimensions", dimensions);

        // Load vocab
        println!("Loading tokenizer from: {}", tokenizer_path.display());
        let vocab = {
            let file_content = match std::fs::read_to_string(&tokenizer_path) {
                Ok(content) => {
                    println!("Successfully read tokenizer file");
                    content
                },
                Err(e) => {
                    println!("Failed to read tokenizer file: {}", e);
                    panic!("Could not read tokenizer file: {}", e);
                }
            };

            match serde_json::from_str::<Tokenizer>(&file_content) {
                Ok(tokenizer) => {
                    println!("Successfully parsed tokenizer JSON");
                    tokenizer.model.vocab
                },
                Err(e) => {
                    println!("Failed to parse tokenizer JSON: {}", e);
                    panic!("Could not parse tokenizer JSON: {}", e);
                }
            }
        };

        println!("Model loaded successfully:");
        println!("  - Dimensions: {}", dimensions);
        println!("  - Vocabulary size: {}", vocab.len());

        Self {
            embeddings,
            dimensions,
            vocab
        }
    }

    /* 
        Primary function for converting a single sentence into an embedding.
    */
    pub fn encode(&self, sentence: &str) -> Vec<f32> {

        let tokens = setencen2tok(sentence, &self.vocab).unwrap();
        let mut out_array = vec![0.0f32; self.dimensions];

        if sentence.len() == 0 {
            return out_array
        }

        for token in tokens.iter() {
            let tmp_arr = self.embeddings[*token as usize * self.dimensions .. (*token as usize * self.dimensions) + self.dimensions].to_vec();
            for i in 0..tmp_arr.len() {
                out_array[i] += tmp_arr[i]
            }
        }

        for i in 0..out_array.len() {
            out_array[i] /= tokens.len() as f32;
        }
    
        let n = norm(&out_array);

        for i in 0..out_array.len() {
            out_array[i] /=  n;
        }

        out_array
    }

    /* 
        Useful for converting multiple sentences into their respective embeddings.
        Will use all available threads.
    */
    pub fn encode_many(&self, sentences: Vec<String>) -> Vec<Vec<f32>> {
        sentences.par_iter() 
        .map(|sentence| self.encode(sentence))
        .collect()
    }

}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn load_and_encode() {
        let encoder = RustPotion::new(PotionModel::BASE2M, &Path::new("models/"));
        assert_eq!(encoder.encode("test"), vec![
            -0.2448156, 0.061568744, -0.22705789, -0.31100106, 0.12387812, 0.012164102, 0.01942585, 0.035540108, 
            -0.07884298, -0.06828589, 0.050681777, 0.010798689, -0.24065527, 0.017179, -0.14778298, 0.017902775, 
            -0.021063324, 0.0009791754, 0.1243356, 0.068948865, 0.07675242, 0.075124845, -0.24434778, -0.04048412, 
            -0.103753075, 0.09782061, -0.061317045, 0.10301087, -0.08056018, 0.07269006, -0.09015573, 0.10328307, 
            -0.036621373, -0.15114696, -0.1601051, 0.07354359, 0.1521876, 0.14489494, 0.0033242279, 0.042615157, 
            0.16762823, 0.14624678, -0.056714535, 0.006396434, 0.22005582, -0.12236872, 0.12488188, -0.11172927, 
            -0.10943516, 0.038111348, 0.03470044, -0.14869972, -0.10061913, -0.04580568, 0.12865654, 0.040736992, 
            0.09603614, -0.030117376, 0.34759793, 0.1326759, 0.063730046, -0.09230757, 0.20546633, 0.046358567
        ]);
    }

    #[test]
    fn zeroed() {
        let encoder = RustPotion::new(PotionModel::BASE2M, &Path::new("models/"));
        assert_eq!(encoder.encode(""), vec![0.0; 64]);
    }
}
