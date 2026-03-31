use flutter_rust_bridge::frb;
use spreadsheet_ai::canvas::state::{
    new_sheet, canvas_load_csv, canvas_load_xlsx,
    read_canvas, write_canvas, read_workbook, set_workbook,
    get_sheets, set_active_sheet,
};
use spreadsheet_ai::canvas::types::SheetObject;
use spreadsheet_ai::data::persistence::{save_workbook, load_workbook};
use spreadsheet_ai::data::export::{save_xlsx, save_csv};

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub struct TableData {
    pub name: String,
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

pub struct TableInfo {
    pub name: String,
    pub rows: u32,
    pub cols: u32,
    pub position: (f32, f32),
}

fn validate_path(path: &str) -> Result<std::path::PathBuf, String> {
    if path.is_empty() {
        return Err("Path cannot be empty".to_string());
    }
    Ok(std::path::Path::new(path).to_path_buf())
}

fn validate_existing_path(path: &str) -> Result<std::path::PathBuf, String> {
    let p = validate_path(path)?;
    if !p.exists() {
        return Err(format!("File not found: {}", path));
    }
    if !p.is_file() {
        return Err(format!("Not a file: {}", path));
    }
    Ok(p)
}

#[frb(sync)]
pub fn new_canvas(name: &str) -> Result<(), String> {
    new_sheet(name).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn open_sai(path: &str) -> Result<(), String> {
    validate_existing_path(path)?;
    let workbook = load_workbook(path)
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?;
    set_workbook(workbook)
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())
}

#[frb(sync)]
pub fn save_sai(path: &str) -> Result<(), String> {
    validate_path(path)?;
    read_workbook(|wb| save_workbook(wb, path))
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())
}

#[frb(sync)]
pub fn get_sheets_list() -> Result<Vec<String>, String> {
    get_sheets().map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn switch_sheet(name: &str) -> Result<(), String> {
    set_active_sheet(name).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn import_csv(path: &str) -> Result<(), String> {
    validate_existing_path(path)?;
    canvas_load_csv(path).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn import_xlsx(path: &str) -> Result<(), String> {
    validate_existing_path(path)?;
    canvas_load_xlsx(path).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn export_xlsx(path: &str) -> Result<(), String> {
    validate_path(path)?;
    read_canvas(|canvas| save_xlsx(canvas, path))
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())
}

#[frb(sync)]
pub fn export_csv(path: &str, table_name: &str) -> Result<(), String> {
    validate_path(path)?;
    let table = read_canvas(|canvas| {
        canvas.get_table(table_name).cloned()
    }).map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?
    .ok_or_else(|| format!("Table '{}' not found", table_name))?;
    save_csv(&table, path).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn get_canvas_tables() -> Result<Vec<TableInfo>, String> {
    read_canvas(|canvas| {
        canvas.objects().iter().filter_map(|o| match o {
            SheetObject::Table(t) => Some(TableInfo {
                name: t.name().to_string(),
                rows: t.row_count() as u32,
                cols: t.col_count() as u32,
                position: *t.position(),
            }),
        }).collect()
    }).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn get_table_data(table_name: &str) -> Result<TableData, String> {
    let table = read_canvas(|canvas| {
        canvas.get_table(table_name).cloned()
    }).map_err(|e| e.to_string())?
    .ok_or_else(|| format!("Table '{}' not found", table_name))?;

    Ok(TableData {
        name: table.name().to_string(),
        columns: table.schema().columns().iter()
            .map(|c| c.name().to_string()).collect(),
        rows: {
            let df = table.data();
            let height = df.height();
            (0..height).map(|row_idx| {
                df.columns().iter().map(|col: &polars::prelude::Column| {
                    match col.get(row_idx).unwrap() {
                        polars::prelude::AnyValue::String(s) => s.to_string(),
                        polars::prelude::AnyValue::StringOwned(s) => s.to_string(),
                        other => other.to_string(),
                    }
                }).collect()
            }).collect()
        },
    })
}

#[frb(sync)]
pub fn set_table_position(table_name: &str, x: f32, y: f32) -> Result<(), String> {
    write_canvas(|canvas| {
        if let Some(table) = canvas.get_table_mut(table_name) {
            table.set_position((x, y));
        }
    }).map_err(|e| e.to_string())
}

pub struct EditResult {
    pub affected_tables: Vec<String>,
}

#[frb(sync)]
pub fn edit_cell(
    sheet_name: &str,
    table_name: &str,
    col_name: &str,
    row: u32,
    value: &str,
) -> Result<EditResult, String> {
    spreadsheet_ai::canvas::state::set_cell(
        sheet_name,
        table_name,
        col_name,
        row as usize,
        value.to_string(),
    ).map_err(|e| e.to_string())?;

    let tables = read_canvas(|canvas| {
        canvas.objects().iter().filter_map(|o| match o {
            SheetObject::Table(t) => Some(t.name().to_string()),
        }).collect::<Vec<String>>()
    }).map_err(|e| e.to_string())?;

    Ok(EditResult { affected_tables: tables })
}