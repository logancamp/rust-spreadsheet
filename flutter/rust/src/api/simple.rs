use flutter_rust_bridge::frb;
use spreadsheet_ai::canvas::state::{init_canvas, canvas_load_csv, canvas_load_xlsx, with_canvas, set_canvas};
use spreadsheet_ai::canvas::types::SheetObject;
use spreadsheet_ai::data::persistence::{save_canvas, load_canvas};
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
}

#[frb(sync)]
pub fn new_canvas(name: &str) -> Result<(), String> {
    init_canvas(name).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn open_sai(path: &str) -> Result<(), String> {
    let canvas = load_canvas(path).map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?;
    set_canvas(canvas).map_err(|e: spreadsheet_ai::error::AppError| e.to_string())
}

#[frb(sync)]
pub fn save_sai(path: &str) -> Result<(), String> {
    with_canvas(|canvas| save_canvas(canvas, path))
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())
}

#[frb(sync)]
pub fn import_csv(path: &str) -> Result<(), String> {
    canvas_load_csv(path).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn import_xlsx(path: &str) -> Result<(), String> {
    canvas_load_xlsx(path).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn export_xlsx(path: &str) -> Result<(), String> {
    with_canvas(|canvas| save_xlsx(canvas, path))
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?
        .map_err(|e: spreadsheet_ai::error::AppError| e.to_string())
}

#[frb(sync)]
pub fn export_csv(path: &str, table_name: &str) -> Result<(), String> {
    let table = with_canvas(|canvas| {
        canvas.get_table(table_name).cloned()
    }).map_err(|e: spreadsheet_ai::error::AppError| e.to_string())?
    .ok_or_else(|| format!("Table '{}' not found", table_name))?;
    save_csv(&table, path).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn get_canvas_tables() -> Result<Vec<TableInfo>, String> {
    with_canvas(|canvas| {
        canvas.objects().iter().filter_map(|o| match o {
            SheetObject::Table(t) => Some(TableInfo {
                name: t.name().to_string(),
                rows: t.row_count() as u32,
                cols: t.col_count() as u32,
            }),
        }).collect()
    }).map_err(|e| e.to_string())
}

#[frb(sync)]
pub fn get_table_data(table_name: &str) -> Result<TableData, String> {
    let table = with_canvas(|canvas| {
        canvas.get_table(table_name).cloned()
    }).map_err(|e| e.to_string())?
    .ok_or_else(|| format!("Table '{}' not found", table_name))?;

    Ok(TableData {
        name: table.name().to_string(),
        columns: table.schema().columns().iter()
            .map(|c| c.name().to_string()).collect(),
        rows: (0..table.data().height()).map(|row_idx| {
            table.data().get_row(row_idx).unwrap().0
                .iter().map(|v| v.to_string()).collect()
        }).collect(),
    })
}