use once_cell::sync::Lazy;
use std::sync::RwLock;
use crate::canvas::SheetObject;
use crate::error::AppError;
use crate::data::import::{load_csv, load_csv_str, load_xlsx};
use crate::canvas::types::{Canvas, Workbook};
use crate::canvas::grid::canvas_to_raw_grid;

static WORKBOOK: Lazy<RwLock<Workbook>> = Lazy::new(|| {
    RwLock::new(Workbook::new())
});

// Helpers
fn lock_err() -> AppError {
    AppError::NotFound("Workbook lock poisoned".to_string())
}

fn no_sheet_err() -> AppError {
    AppError::NotFound("No active sheet".to_string())
}

// Sheet management
pub fn new_sheet(name: &str) -> Result<(), AppError> {
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    guard.sheets.insert(name.to_string(), Canvas::new(name.to_string()));
    guard.active_sheet = Some(name.to_string());
    Ok(())
}

pub fn set_active_sheet(name: &str) -> Result<(), AppError> {
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    if !guard.sheets.contains_key(name) {
        return Err(AppError::NotFound(format!("Sheet '{}' not found", name)));
    }
    guard.active_sheet = Some(name.to_string());
    Ok(())
}

pub fn get_sheets() -> Result<Vec<String>, AppError> {
    let guard = WORKBOOK.read().map_err(|_| lock_err())?;
    let names: Vec<String> = guard.sheets
        .iter()
        .filter(|(_, canvas)| !canvas.objects().is_empty())
        .map(|(name, _)| name.clone())
        .collect();
    Ok(names)
}

pub fn set_workbook(workbook: Workbook) -> Result<(), AppError> {
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    *guard = workbook;
    Ok(())
}

// Canvas access
pub fn read_canvas<F, T>(f: F) -> Result<T, AppError>
where
    F: FnOnce(&Canvas) -> T
{
    let guard = WORKBOOK.read().map_err(|_| lock_err())?;
    let name = guard.active_sheet.as_ref().ok_or_else(no_sheet_err)?;
    let canvas = guard.sheets.get(name).ok_or_else(no_sheet_err)?;
    Ok(f(canvas))
}

pub fn write_canvas<F, T>(f: F) -> Result<T, AppError>
where
    F: FnOnce(&mut Canvas) -> T
{
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    let name = guard.active_sheet.clone().ok_or_else(no_sheet_err)?;
    let canvas = guard.sheets.get_mut(&name).ok_or_else(no_sheet_err)?;
    Ok(f(canvas))
}

pub fn set_cell(
    sheet_name: &str,
    table_name: &str,
    col_name: &str,
    row: usize,
    value: String,
) -> Result<(), AppError> {
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    let canvas = guard.sheets.get_mut(sheet_name)
        .ok_or_else(|| AppError::NotFound(format!("Sheet '{}' not found", sheet_name)))?;
    let table = canvas.get_table_mut(table_name)
        .ok_or_else(|| AppError::NotFound(format!("Table '{}' not found", table_name)))?;
    table.set_cell_value(col_name, row, value)?;
    Ok(())
}

// Import
pub fn canvas_load_csv(path: &str) -> Result<(), AppError> {
    let tables = load_csv(path)?;
    let sheet_name = std::path::Path::new(path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("sheet")
        .to_string();

    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    let canvas = guard.sheets
        .entry(sheet_name.clone())
        .or_insert_with(|| Canvas::new(sheet_name.clone()));
    for table in tables {
        let table = table.with_source_path(path);
        canvas.add_or_replace_table(table);
    }
    guard.active_sheet = Some(sheet_name);
    Ok(())
}

pub fn canvas_load_csv_str(name: &str, csv: &str) -> Result<(), AppError> {
    let table = load_csv_str(name, csv)?;
    let sheet_name = name.to_string();

    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    let canvas = guard.sheets
        .entry(sheet_name.clone())
        .or_insert_with(|| Canvas::new(sheet_name.clone()));
    canvas.add_or_replace_table(table);
    guard.active_sheet = Some(sheet_name);
    Ok(())
}

pub fn canvas_load_xlsx(path: &str) -> Result<(), AppError> {
    let sheet_tables = load_xlsx(path)?;
    let mut first_sheet: Option<String> = None;

    {
        let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
        for sheet_table in sheet_tables {
            let sheet_name = sheet_table.sheet_name.clone();
            let table = sheet_table.table.with_source_path(path);

            let canvas = guard.sheets
                .entry(sheet_name.clone())
                .or_insert_with(|| Canvas::new(sheet_name.clone()));
            canvas.add_or_replace_table(table);

            if first_sheet.is_none() {
                first_sheet = Some(sheet_name);
            }
        }
    }

    if let Some(name) = first_sheet {
        let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
        guard.active_sheet = Some(name);
    }

    Ok(())
}

pub fn read_workbook<F, T>(f: F) -> Result<T, AppError>
where
    F: FnOnce(&Workbook) -> T
{
    let guard = WORKBOOK.read().map_err(|_| lock_err())?;
    Ok(f(&guard))
}

pub fn write_workbook<F, T>(f: F) -> Result<T, AppError>
where
    F: FnOnce(&mut Workbook) -> T
{
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    Ok(f(&mut guard))
}

pub fn cell_edited(
    sheet: &str,
    row: u32,
    col: u32,
    value: String,
) -> Result<(), AppError> {
    let mut guard = WORKBOOK.write().map_err(|_| lock_err())?;
    let canvas = guard.sheets.get_mut(sheet)
        .ok_or_else(|| AppError::NotFound(format!("Sheet '{}' not found", sheet)))?;

    let mut grid = canvas_to_raw_grid(canvas);

    // ← add this: grow grid to fit the edited cell if canvas was empty
    let needed_rows = row + 1;
    let needed_cols = col + 1;
    if grid.rows < needed_rows || grid.cols < needed_cols {
        grid.resize(
            grid.rows.max(needed_rows),
            grid.cols.max(needed_cols),
        );
    }

    // apply the edit
    grid.set(row, col, value);

    // find affected region — scan outward from edited cell to find bounds
    let region_min_row = (0..row).rev()
        .find(|&r| (0..grid.cols).all(|c| grid.is_empty_cell(r, c)))
        .map(|r| r + 1)
        .unwrap_or(0);

    let region_max_row = (row + 1..grid.rows)
        .find(|&r| (0..grid.cols).all(|c| grid.is_empty_cell(r, c)))
        .map(|r| r - 1)
        .unwrap_or(grid.rows - 1);

    let region_min_col = (0..col).rev()
        .find(|&c| (0..grid.rows).all(|r| grid.is_empty_cell(r, c)))
        .map(|c| c + 1)
        .unwrap_or(0);

    let region_max_col = (col + 1..grid.cols)
        .find(|&c| (0..grid.rows).all(|r| grid.is_empty_cell(r, c)))
        .map(|c| c - 1)
        .unwrap_or(grid.cols - 1);

    // re-detect islands in affected region only
    let islands = grid.find_islands_in_region(
        region_min_row,
        region_max_row,
        region_min_col,
        region_max_col,
    )?;

    // remove old tables that overlap this region
    canvas.retain_tables(|o| match o {
        SheetObject::Table(t) => {
            let (pc, pr) = t.position();
            let pr = *pr as u32;
            let pc = *pc as u32;
            let (w, h) = t.shape();
            let t_max_row = pr + h;
            let t_max_col = pc + w;
            // keep if completely outside region
            t_max_row < region_min_row || pr > region_max_row ||
                t_max_col < region_min_col || pc > region_max_col
        }
    });

    // add newly detected islands
    let sheet_name = canvas.name().to_string();
    for (idx, island) in islands.iter().enumerate() {
        let table_name = if idx == 0 {
            sheet_name.clone()
        } else {
            format!("{}_{}", sheet_name, idx)
        };
        let table = grid.island_to_table(island, &sheet_name, &table_name)?;
        canvas.add_or_replace_table(table);
    }

    canvas.modified_at = chrono::Utc::now();
    Ok(())
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use crate::canvas::types::SheetObject;

    #[test]
    #[serial]
    fn test_table_name_deduplication() {
        new_sheet("dedup_test").unwrap();
        canvas_load_csv_str("Sheet1", "a,b\n1,2\n").unwrap();
        canvas_load_csv_str("Sheet1", "c,d\n3,4\n").unwrap();

        read_canvas(|canvas| {
            let names: Vec<String> = canvas.objects().iter().filter_map(|o| match o {
                SheetObject::Table(t) => Some(t.name().to_string()),
            }).collect();
            assert_eq!(names.len(), 2);
            assert!(names.contains(&"Sheet1".to_string()));
            assert!(names.contains(&"Sheet1_1".to_string()));
        }).unwrap();
    }
}