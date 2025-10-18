use flutter_rust_bridge::frb;
use anyhow::Result;

#[frb(sync)]
pub fn download_web_page(url: String) -> Result<bool> {    
    println!("Starting download of: {:?}", url);
    Ok(true)
}