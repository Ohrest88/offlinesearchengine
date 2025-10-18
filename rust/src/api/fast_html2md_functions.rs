use flutter_rust_bridge::frb;
use anyhow::Result;
use std::fs;
use std::path::Path;
use html2text::from_read;
use html2text::from_read_rich;
use html2text::config;
use readability::extractor;
use url::Url;
use std::io::Cursor;

#[frb(sync)]
pub fn html_to_markdown(html_content: String, output_path: String) -> Result<String> {
    // Convert HTML to Markdown using the rewriter (default feature)
    let markdown = html2md::rewrite_html(&html_content, false);
    
    // Create markdown file path by replacing .html extension with .md
    let md_path = output_path.replace(".html", ".md");
    
    println!("Saving markdown file to: {}", md_path);
    // Write the markdown content to file
    fs::write(&md_path, &markdown)?;
    
    // Return the markdown content
    Ok(markdown)
}

#[frb(sync)]
pub fn html_to_text(html_content: String, output_path: String, width: usize) -> Result<String> {
    // Convert HTML to plain text with specified width
    let text = from_read(html_content.as_bytes(), usize::MAX)
        .map_err(|e| anyhow::anyhow!("Failed to convert HTML to text: {}", e))?;
    
    // Create text file path by replacing .html extension with .txt
    let txt_path = output_path.replace(".html", ".txt");
    
    println!("Saving text file to: {}", txt_path);
    // Write the text content to file
    fs::write(&txt_path, &text)?;
    
    Ok(text)
}

#[frb(sync)]
pub fn html_to_text_rich(html_content: String, output_path: String, width: usize) -> Result<String> {
    // Convert HTML to text using the config API
    let text = config::plain()
        .string_from_read(html_content.as_bytes(), width)
        .map_err(|e| anyhow::anyhow!("Failed to convert HTML to text: {}", e))?;
    
    // Clean up the text by removing links and bracketed content
    let cleaned = clean_text(&text);
    
    // Create text file path by replacing .html extension with .txt
    let txt_path = output_path.replace(".html", ".txt");
    
    println!("Saving text file to: {}", txt_path);
    // Write the cleaned text content to file
    fs::write(&txt_path, &cleaned)?;
    
    Ok(cleaned)
}

fn clean_text(text: &str) -> String {
    let mut cleaned = String::new();
    let mut in_brackets = 0;
    let mut in_link = false;
    
    for line in text.lines() {
        let mut clean_line = String::new();
        let mut chars = line.chars().peekable();
        
        while let Some(c) = chars.next() {
            match c {
                '[' => in_brackets += 1,
                ']' => if in_brackets > 0 { in_brackets -= 1 },
                'h' if chars.peek() == Some(&'t') && line.contains("http") => in_link = true,
                ' ' => {
                    in_link = false;
                    if in_brackets == 0 { clean_line.push(c); }
                },
                _ => {
                    if in_brackets == 0 && !in_link {
                        clean_line.push(c);
                    }
                }
            }
        }
        
        // Only add non-empty lines
        if !clean_line.trim().is_empty() {
            cleaned.push_str(&clean_line);
            cleaned.push('\n');
        }
    }
    
    cleaned
}

#[frb(sync)]
pub fn html_to_text_readability(html_content: String, output_path: String, width: usize) -> Result<String> {
    // Create a fake URL since we're working with content directly
    let fake_url = Url::parse("http://localhost/article")
        .map_err(|e| anyhow::anyhow!("Failed to parse URL: {}", e))?;
    
    // Create a cursor from our HTML content
    let mut reader = Cursor::new(html_content);
    
    // Extract readable content using readability
    let product = extractor::extract(&mut reader, &fake_url)
        .map_err(|e| anyhow::anyhow!("Failed to extract text: {}", e))?;
    
    // Get the plain text
    let text = product.text;
    
    // Create text file path by replacing .html extension with .txt
    let txt_path = output_path.replace(".html", ".txt");
    
    println!("Saving text file to: {}", txt_path);
    // Write the text content to file
    fs::write(&txt_path, &text)?;
    
    Ok(text)
}