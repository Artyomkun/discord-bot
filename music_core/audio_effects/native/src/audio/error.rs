pub use thiserror::Error;

/// Audio operation errors
#[derive(Debug, Error)]
pub enum AudioError {
    #[error("Invalid audio format: {0}")]
    InvalidFormat(String),

    #[error("Unsupported sample rate: {0}")]
    UnsupportedSampleRate(u32),

    #[error("Unsupported channel count: {0}")]
    UnsupportedChannels(u8),

    #[error("Invalid audio data: {0}")]
    InvalidData(String),

    #[error("IO error: {0}")]
    IoError(String),

    #[error("End of stream")]
    EndOfStream,

    #[error("Buffer overflow")]
    BufferOverflow,

    #[error("Conversion error: {0}")]
    ConversionError(String),

    #[error("Decoder error: {0}")]
    DecoderError(String),

    #[error("Encoder error: {0}")]
    EncoderError(String),

    #[error("Effect configuration error: {0}")]
    EffectConfig(String),

    #[error("Invalid parameter: {0}")]
    InvalidParameter(String),

    #[error("OutOfBounds parameter")]
    OutOfBounds,

    #[error("BufferError parameter")]
    BufferError(String),

    #[error("Unsupported format parameter: {0}")]
    UnsupportedFormat(String),

    #[error("Buffer size error")]
    BufferSizeError,

    #[error("Invalid data length")]
    InvalidDataLength,

    #[error("Unsupported sample format")]
    UnsupportedSampleFormat,
}

pub type AudioResult<T> = Result<T, AudioError>;