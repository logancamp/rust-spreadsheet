use flutter_rust_bridge::frb;
use spreadsheet_ai::data::import::load_csv_str;
use spreadsheet_ai::error::AppError;
use spreadsheet_ai::canvas::types::ColumnSchema;
use polars::prelude::AnyValue;

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

#[frb(sync)]
pub fn load_csv_to_flutter(name: &str, csv: &str) -> Result<TableData, String> {
    let table = load_csv_str(name, csv).map_err(|e| e.to_string())?;
    Ok(TableData {
        name: table.name().to_string(),
        columns: table.schema().columns().iter().map(|c: &ColumnSchema| c.name().to_string()).collect(),
        rows: (0..table.data().height()).map(|row_idx| {
            table.data().get_row(row_idx).unwrap().0
                .iter().map(|v: &AnyValue| v.to_string()).collect()
        }).collect(),
    })
}