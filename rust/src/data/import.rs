fn deduplicate_headers(headers: Vec<String>) -> Vec<String> {
    let mut seen: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
    headers.into_iter().enumerate().map(|(i, name)| {
        let name = if name.trim().is_empty() {
            format!("col_{}", i)
        } else {
            name
        };
        let count = seen.entry(name.clone()).or_insert(0);
        let result = if *count == 0 {
            name.clone()
        } else {
            format!("{}_{}", name, count)
        };
        *count += 1;
        result
    }).collect()
}

fn fix_dataframe_columns(df: DataFrame) -> Result<DataFrame, AppError> {
    let headers: Vec<String> = df.get_column_names()
        .iter().map(|s| s.to_string()).collect();
    let deduped = deduplicate_headers(headers);
    let mut df = df;
    for (i, name) in deduped.iter().enumerate() {
        let old_name = df.get_column_names()[i].to_string();
        if old_name != *name {
            df.rename(&old_name, name.into())?;
        }
    }
    Ok(df)
}

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

    let df = fix_dataframe_columns(df)?;
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

    let df = fix_dataframe_columns(df)?;
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
            Some(row) => deduplicate_headers(row.iter().map(|c| c.to_string()).collect()),
            None => continue,
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
        let df = fix_dataframe_columns(df)?;
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

    #[test]
    fn test_deduplicate_headers() {
        let headers = vec![
            "name".to_string(),
            "name".to_string(),
            "".to_string(),
            "revenue".to_string(),
            "name".to_string(),
        ];
        let result = deduplicate_headers(headers);
        assert_eq!(result[0], "name");
        assert_eq!(result[1], "name_1");
        assert_eq!(result[2], "col_2");
        assert_eq!(result[3], "revenue");
        assert_eq!(result[4], "name_2");
    }
}