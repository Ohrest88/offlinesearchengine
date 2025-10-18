use anyhow::Result;
use pdf_extract;
//use pdfium_render::prelude::*;
use std::env;
use std::path::PathBuf;
use rayon::prelude::*;
use std::time::Instant;

fn get_pdfium_path() -> PathBuf {
    #[cfg(target_os = "linux")]
    {
        // For Linux, look in the project root first, then try the libs directory
        let paths = [
            "libs/linux-x64/libpdfium.so"  // Libs directory
        ];
        
        for path in paths {
            if PathBuf::from(path).exists() {
                return PathBuf::from(path);
            }
        }
        PathBuf::from("libpdfium.so") // Default fallback
    }
    #[cfg(target_os = "android")]
    {
        if cfg!(target_arch = "aarch64") {
            PathBuf::from("libpdfium.so")  // Android will look in the correct jniLibs directory
        } else {
            PathBuf::from("libpdfium.so")  // Same for 32-bit ARM
        }
    }
}

#[derive(Debug, Clone)]
pub struct TextWithLocation {
    pub text: String,
    pub page_number: i32,
}

/*
#[flutter_rust_bridge::frb(sync)]
pub fn extract_text_from_pdf_pdfium(pdf_bytes: Vec<u8>) -> Result<Vec<TextWithLocation>> {
    // Initialize Pdfium with platform-specific library path
    let pdfium = Pdfium::new(
        Pdfium::bind_to_library(get_pdfium_path().to_str().unwrap())
            .map_err(|e| anyhow::anyhow!("Failed to bind to Pdfium: {}", e))?
    );
    
    // Load PDF from memory
    let document = pdfium
        .load_pdf_from_byte_slice(&pdf_bytes, None)
        .map_err(|e| anyhow::anyhow!("PDF loading error: {}", e))?;

    // Process each page and collect the results
    let text_sections: Vec<TextWithLocation> = document
        .pages()
        .iter()
        .enumerate()
        .filter_map(|(i, page)| {
            page.text()
                .ok()
                .map(|text| TextWithLocation {
                    text: text.all(),
                    page_number: (i + 1) as i32,
                })
        })
        .collect();

    Ok(text_sections)
}
*/

#[flutter_rust_bridge::frb(sync)]
pub fn extract_text_from_pdf_extract(pdf_bytes: Vec<u8>) -> Result<Vec<TextWithLocation>> {
    let start = Instant::now();
    
    let result = match pdf_extract::extract_text_from_mem_by_pages(&pdf_bytes) {
        Ok(pages) => {
            let text_sections = pages.into_iter()
                .enumerate()
                .map(|(i, text)| TextWithLocation {
                    text,
                    page_number: (i + 1) as i32, // Pages are 1-based
                })
                .collect();
            Ok(text_sections)
        },
        Err(e) => Err(anyhow::anyhow!("PDF extraction error: {}", e))
    };
    
    let duration = start.elapsed();
    println!("Single-threaded PDF extraction took: {:?}", duration);
    //std::process::exit(0); // Exit immediately after completion
    
    result
}

// Default method that uses pdfium
#[flutter_rust_bridge::frb(sync)]
pub fn extract_text_from_pdf(pdf_bytes: Vec<u8>) -> Result<Vec<TextWithLocation>> {
    extract_text_from_pdf_extract_multithreaded(pdf_bytes)
}

#[flutter_rust_bridge::frb(sync)]
pub fn extract_text_from_pdf_extract_multithreaded(pdf_bytes: Vec<u8>) -> Result<Vec<TextWithLocation>> {
    let start = Instant::now();
    
    let result = match pdf_extract::extract_text_from_mem_by_pages_multithreaded(&pdf_bytes) {
        Ok(pages) => {
            let text_sections: Vec<_> = pages.into_par_iter()
                .enumerate()
                .map(|(i, text)| TextWithLocation {
                    text,
                    page_number: (i + 1) as i32,
                })
                .collect();
            Ok(text_sections)
        },
        Err(e) => Err(anyhow::anyhow!("PDF extraction error: {}", e))
    };
    
    let duration = start.elapsed();
    println!("Multithreaded PDF extraction took: {:?}", duration);
    //std::process::exit(0);
    
    result
}