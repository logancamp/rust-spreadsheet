use polars::prelude::*;
use std::path::Path;
use calamine::{open_workbook, Reader, Xlsx};

use crate::canvas::types::TableObject;
use crate::error::AppError;

/// Load sheet from an CSV file as table object.
/// TODO: run grid detection per sheet to split multiple tables on one sheet.
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

// str for testing
pub fn load_csv_str(name: &str, content: &str) -> Result<TableObject, AppError> {
    let cursor = std::io::Cursor::new(content.as_bytes().to_vec());
    let df = CsvReadOptions::default()
        .with_has_header(true)
        .with_infer_schema_length(Some(100))
        .into_reader_with_file_handle(cursor)
        .finish()?;

    Ok(TableObject::new(name.to_string(), (0.0, 0.0), df))
}

/// Load all sheets from an XLSX file.
/// Each sheet becomes a separate TableObject.
/// TODO: run grid detection per sheet to split multiple tables on one sheet.
pub fn load_xlsx(path: impl AsRef<Path>) -> Result<Vec<TableObject>, AppError> {
    let path = path.as_ref();
    let mut workbook: Xlsx<_> = open_workbook(path)?;
    let sheet_names = workbook.sheet_names().to_vec();
    let mut tables = Vec::new();

    for sheet_name in sheet_names {
        let sheet = workbook
            .worksheet_range(&sheet_name)
            .map_err(|e| AppError::Calamine(e))?;

        let mut rows = sheet.rows();

        let headers: Vec<String> = match rows.next() {
            Some(row) => row.iter().map(|c| c.to_string()).collect(),
            None => continue, // skip empty sheets
        };

        let data_rows: Vec<Vec<String>> = rows
            .map(|row| row.iter().map(|c| c.to_string()).collect())
            .collect();

        if data_rows.is_empty() {
            continue; // skip header-only sheets
        }

        let series: Vec<Column> = headers.iter().enumerate().map(|(i, name)| {
            let values: Vec<String> = data_rows.iter()
                .map(|row| row.get(i).cloned().unwrap_or_default())
                .collect();
            Column::new(name.into(), values)
        }).collect();

        let df = DataFrame::new_infer_height(series)?;
        tables.push(TableObject::new(sheet_name, (0.0, 0.0), df));
    }

    if tables.is_empty() {
        return Err(AppError::Schema("No valid sheets found in XLSX file".to_string()));
    }

    Ok(tables)
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_CSV: &str = "name,revenue,active\nAcme,150000,true\nGlobex,320000,false\nInitech,98000,true\n";

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