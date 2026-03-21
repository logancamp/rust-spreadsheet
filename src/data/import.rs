use polars::prelude::*;
use std::path::Path;
use calamine::{open_workbook, Reader, Xlsx};

use crate::canvas::types::TableObject;
use crate::error::AppError;

pub fn load_csv(path: impl AsRef<Path>) -> Result<TableObject, AppError> {
    let path = path.as_ref();
    let table_name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("table")
        .to_string();

    let df = CsvReadOptions::default()
        .with_has_header(true)
        .with_infer_schema_length(Some(100))
        .try_into_reader_with_file_path(Some(path.to_path_buf()))?
        .finish()?;

    Ok(TableObject::new(table_name, (0.0, 0.0), df))
}

pub fn load_csv_str(name: &str, content: &str) -> Result<TableObject, AppError> {
    let cursor = std::io::Cursor::new(content.as_bytes().to_vec());
    let df = CsvReadOptions::default()
        .with_has_header(true)
        .with_infer_schema_length(Some(100))
        .into_reader_with_file_handle(cursor)
        .finish()?;

    Ok(TableObject::new(name.to_string(), (0.0, 0.0), df))
}

pub fn load_xlsx(path: impl AsRef<Path>) -> Result<TableObject, AppError> {
    let path = path.as_ref();
    let table_name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("table")
        .to_string();

    // Fetches sheet into grid
    let mut workbook: Xlsx<_> = open_workbook(path)?;
    let sheet = workbook.worksheet_range_at(0).unwrap()?;

    let mut rows = sheet.rows();

    // First row is headers
    let headers: Vec<String> = match rows.next() {
        Some(row) => row.iter().map(|c| c.to_string()).collect(),
        None => return Err(AppError::Schema("Empty sheet".to_string())),
    };

    // Remaining rows are data
    let data_rows: Vec<Vec<String>> = rows
        .map(|row| row.iter().map(|c| c.to_string()).collect())
        .collect();

    // Build one Series per column then combine into a DataFrame
    let series: Vec<Column> = headers.iter().enumerate().map(|(i, name)| {
        let values: Vec<String> = data_rows.iter()
            .map(|row| row.get(i).cloned().unwrap_or_default())
            .collect();
        Column::new(name.into(), values)
    }).collect();

    let df = DataFrame::new_infer_height(series)?;
    Ok(TableObject::new(table_name, (0.0, 0.0), df))
}


////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_CSV: &str = "\
name,revenue,active
Acme,150000,true
Globex,320000,false
Initech,98000,true
";

    #[test]
    fn test_load_csv_str_shape() {
        let table = load_csv_str("companies", SAMPLE_CSV).unwrap();
        assert_eq!(table.row_count(), 3usize);
        assert_eq!(table.col_count(), 3usize);
    }

    #[test]
    fn test_load_csv_str_name() {
        let table = load_csv_str("companies", SAMPLE_CSV).unwrap();
        assert_eq!(table.name(), "companies");
    }
}