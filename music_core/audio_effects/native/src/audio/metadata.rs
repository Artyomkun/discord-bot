pub use std::fmt;

/// Audio metadata
#[derive(Debug, Clone, Default)]
pub struct AudioMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub year: Option<u32>,
    pub track: Option<u32>,
    pub genre: Option<String>,
    pub comments: Option<String>,
}