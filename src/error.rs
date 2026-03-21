use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Polars error: {0}")]
    Polars(#[from] polars::error::PolarsError),

    #[error("Calamine error: {0}")]
    Calamine(#[from] calamine::XlsxError),

    #[error("XLSX write error: {0}")]
    XlsxWrite(#[from] rust_xlsxwriter::XlsxError),

    #[error("Formula error: {0}")]
    Formula(String),

    #[error("Schema error: {0}")]
    Schema(String),

    #[error("Not found: {0}")]
    NotFound(String),
}