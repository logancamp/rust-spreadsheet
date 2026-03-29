use polars::prelude::*;
use std::path::Path;
use calamine::{open_workbook, Reader, Xlsx};

use crate::canvas::types::TableObject;
use crate::error::AppError;

pub fn deduplicate_headers(headers: Vec<String>) -> Vec<String> {
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

pub fn load_csv(path: impl AsRef<Path>) -> Result<Vec<TableObject>, AppError> {
    use crate::canvas::grid::RawGrid;

    let path = path.as_ref();
    let table_name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("table")
        .to_string();

    let content = std::fs::read_to_string(path)?;
    let rows: Vec<Vec<String>> = content.lines()
        .map(|line| line.split(',').map(|s| s.trim().to_string()).collect())
        .collect();

    if rows.is_empty() {
        return Err(AppError::Schema("Empty CSV file".to_string()));
    }

    let num_rows = rows.len() as u32;
    let num_cols = rows.iter().map(|r| r.len()).max().unwrap_or(0) as u32;

    let mut grid = RawGrid::new(num_rows, num_cols);
    for (row_idx, row) in rows.iter().enumerate() {
        for (col_idx, val) in row.iter().enumerate() {
            grid.set(row_idx as u32, col_idx as u32, val.clone());
        }
    }

    let islands = grid.find_islands()?;

    if islands.is_empty() {
        return Err(AppError::Schema("Empty CSV file".to_string()));
    }

    let mut tables = Vec::new();
    for (idx, island) in islands.iter().enumerate() {
        let table_name = if idx == 0 {
            table_name.clone()
        } else {
            format!("{}_{}", table_name, idx)
        };
        let table = grid.island_to_table(island, &table_name, &table_name)?;
        tables.push(table);
    }

    Ok(tables)
}

pub fn load_csv_str(name: &str, content: &str) -> Result<TableObject, AppError> {
    let mut lines = content.lines();

    let raw_headers: Vec<String> = match lines.next() {
        Some(header_line) => header_line.split(',').map(|s| s.trim().to_string()).collect(),
        None => return Err(AppError::Schema("Empty CSV content".to_string())),
    };
    let clean_headers = deduplicate_headers(raw_headers);

    let rest: String = lines.collect::<Vec<&str>>().join("\n");
    let clean_csv = format!("{}\n{}", clean_headers.join(","), rest);

    let cursor = std::io::Cursor::new(clean_csv.as_bytes().to_vec());
    let df = CsvReadOptions::default()
        .with_has_header(true)
        .with_infer_schema_length(Some(100))
        .into_reader_with_file_handle(cursor)
        .finish()?;

    Ok(TableObject::new(name.to_string(), (0.0, 0.0), df))
}

/// Load all sheets from an XLSX file.
/// Each sheet gets island detection — multiple tables per sheet supported.
pub struct SheetTable {
    pub sheet_name: String,
    pub table: TableObject,
}

pub fn load_xlsx(path: impl AsRef<Path>) -> Result<Vec<SheetTable>, AppError> {
    use crate::canvas::grid::RawGrid;

    let path = path.as_ref();
    let mut workbook: Xlsx<_> = open_workbook(path)?;
    let sheet_names = workbook.sheet_names().to_vec();
    let mut results = Vec::new();

    for sheet_name in sheet_names {
        let sheet = workbook
            .worksheet_range(&sheet_name)
            .map_err(|e| AppError::Calamine(e))?;

        let rows: Vec<Vec<String>> = sheet.rows()
            .map(|row| row.iter().map(|c| c.to_string()).collect())
            .collect();

        if rows.is_empty() { continue; }

        let num_rows = rows.len() as u32;
        let num_cols = rows.iter().map(|r| r.len()).max().unwrap_or(0) as u32;

        if num_cols == 0 { continue; }

        let mut grid = RawGrid::new(num_rows, num_cols);
        for (row_idx, row) in rows.iter().enumerate() {
            for (col_idx, val) in row.iter().enumerate() {
                grid.set(row_idx as u32, col_idx as u32, val.clone());
            }
        }

        let islands = grid.find_islands()?;
        if islands.is_empty() { continue; }

        for (idx, island) in islands.iter().enumerate() {
            let table_name = if idx == 0 {
                sheet_name.clone()
            } else {
                format!("{}_{}", sheet_name, idx)
            };
            let table = grid.island_to_table(island, &sheet_name, &table_name)?;
            results.push(SheetTable {
                sheet_name: sheet_name.clone(),
                table,
            });
        }
    }

    if results.is_empty() {
        return Err(AppError::Schema("No valid sheets found in XLSX file".to_string()));
    }

    Ok(results)
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