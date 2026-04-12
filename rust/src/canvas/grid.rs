use std::collections::{HashMap, HashSet, VecDeque};
use crate::canvas::{Canvas, SheetObject};
use crate::canvas::types::TableObject;
use crate::error::AppError;
use crate::data::import::deduplicate_headers;

// Raw Grid
/// A 2D sparse grid of raw cell values from an imported file.
/// Only stores non-empty cells. Used transiently during import only —
/// never persisted. Detection runs on this, producing TableObjects.
pub struct RawGrid {
    /// Sparse cell storage — only non-empty cells stored
    cells: HashMap<(u32, u32), String>,
    pub rows: u32,
    pub cols: u32,
}

impl RawGrid {
    pub fn new(rows: u32, cols: u32) -> Self {
        Self {
            cells: HashMap::new(),
            rows,
            cols,
        }
    }

    pub fn set(&mut self, row: u32, col: u32, value: String) {
        if value.trim().is_empty() {
            self.cells.remove(&(row, col));
        } else {
            self.cells.insert((row, col), value);
        }
    }

    pub fn get(&self, row: u32, col: u32) -> Option<&String> {
        self.cells.get(&(row, col))
    }

    pub fn is_empty_cell(&self, row: u32, col: u32) -> bool {
        !self.cells.contains_key(&(row, col))
    }

    pub fn resize(&mut self, rows: u32, cols: u32) {
        self.rows = self.rows.max(rows);
        self.cols = self.cols.max(cols);
    }

    /// Find all data islands using orthogonal flood fill + bounding box.
    /// Each island becomes one TableObject.
    pub fn find_islands(&self) -> Result<Vec<IslandData>, AppError> {
        let mut visited: HashSet<(u32, u32)> = HashSet::new();
        let mut islands = Vec::new();

        // collect all non-empty cells sorted top-left to bottom-right
        let mut non_empty: Vec<(u32, u32)> = self.cells.keys().cloned().collect();
        non_empty.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));

        for start in non_empty {
            if visited.contains(&start) {
                continue;
            }

            // BFS flood fill — orthogonal only
            let mut region: Vec<(u32, u32)> = Vec::new();
            let mut queue: VecDeque<(u32, u32)> = VecDeque::new();
            queue.push_back(start);
            visited.insert(start);

            while let Some((row, col)) = queue.pop_front() {
                region.push((row, col));

                // orthogonal neighbours only
                let neighbours = [
                    (row.wrapping_sub(1), col),
                    (row + 1, col),
                    (row, col.wrapping_sub(1)),
                    (row, col + 1),
                ];

                for (nr, nc) in neighbours {
                    if nr < self.rows && nc < self.cols
                        && !visited.contains(&(nr, nc))
                        && !self.is_empty_cell(nr, nc)
                    {
                        visited.insert((nr, nc));
                        queue.push_back((nr, nc));
                    }
                }
            }

            // bounding box of the region
            let min_row = region.iter().map(|c| c.0).min().unwrap();
            let max_row = region.iter().map(|c| c.0).max().unwrap();
            let min_col = region.iter().map(|c| c.1).min().unwrap();
            let max_col = region.iter().map(|c| c.1).max().unwrap();

            islands.push(IslandData {
                min_row,
                min_col,
                max_row,
                max_col,
            });
        }

        Ok(islands)
    }

    /// Convert an island bounding box into a TableObject.
    /// First row of the island = headers.
    pub fn island_to_table(
        &self,
        island: &IslandData,
        canvas_name: &str,
        table_name: &str,
    ) -> Result<TableObject, AppError> {
        use polars::prelude::*;

        // extract header row
        let raw_headers: Vec<String> = (island.min_col..=island.max_col)
            .map(|col| {
                self.get(island.min_row, col)
                    .cloned()
                    .unwrap_or_default()
            })
            .collect();

        let user_defined_headers: Vec<bool> = raw_headers.iter()
            .map(|h| !h.trim().is_empty())
            .collect();

        let headers = deduplicate_headers(raw_headers);

        // extract data rows
        let data_rows: Vec<Vec<String>> = (island.min_row + 1..=island.max_row)
            .map(|row| {
                (island.min_col..=island.max_col)
                    .map(|col| self.get(row, col).cloned().unwrap_or_default())
                    .collect()
            })
            .collect();

        // build DataFrame column by column
        let series: Vec<Column> = headers.iter().enumerate().map(|(i, col_name)| {
            let values: Vec<String> = data_rows.iter()
                .map(|row| row.get(i).cloned().unwrap_or_default())
                .collect();
            Column::new(col_name.into(), values)
        }).collect();

        let df = DataFrame::new_infer_height(series)?;
        let position = (island.min_col as f32, island.min_row as f32);
        Ok(TableObject::new(table_name.to_string(), position, df))
    }

    pub fn find_islands_in_region(
        &self,
        min_row: u32,
        max_row: u32,
        min_col: u32,
        max_col: u32,
    ) -> Result<Vec<IslandData>, AppError> {
        let mut visited: HashSet<(u32, u32)> = HashSet::new();
        let mut islands = Vec::new();

        let mut non_empty: Vec<(u32, u32)> = self.cells.keys()
            .filter(|(r, c)| *r >= min_row && *r <= max_row && *c >= min_col && *c <= max_col)
            .cloned()
            .collect();
        non_empty.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));

        for start in non_empty {
            if visited.contains(&start) {
                continue;
            }

            let mut region: Vec<(u32, u32)> = Vec::new();
            let mut queue: VecDeque<(u32, u32)> = VecDeque::new();
            queue.push_back(start);
            visited.insert(start);

            while let Some((row, col)) = queue.pop_front() {
                region.push((row, col));

                let neighbours = [
                    (row.wrapping_sub(1), col),
                    (row + 1, col),
                    (row, col.wrapping_sub(1)),
                    (row, col + 1),
                ];

                for (nr, nc) in neighbours {
                    if nr >= min_row && nr <= max_row
                        && nc >= min_col && nc <= max_col
                        && !visited.contains(&(nr, nc))
                        && !self.is_empty_cell(nr, nc)
                    {
                        visited.insert((nr, nc));
                        queue.push_back((nr, nc));
                    }
                }
            }

            let r_min = region.iter().map(|c| c.0).min().unwrap();
            let r_max = region.iter().map(|c| c.0).max().unwrap();
            let c_min = region.iter().map(|c| c.1).min().unwrap();
            let c_max = region.iter().map(|c| c.1).max().unwrap();

            islands.push(IslandData {
                min_row: r_min,
                max_row: r_max,
                min_col: c_min,
                max_col: c_max,
            });
        }

        Ok(islands)
    }
}

// Island
/// Bounding box of a detected data island.
pub struct IslandData {
    pub min_row: u32,
    pub max_row: u32,
    pub min_col: u32,
    pub max_col: u32,
}

pub fn canvas_to_raw_grid(canvas: &Canvas) -> RawGrid {
    let mut max_row = 0u32;
    let mut max_col = 0u32;

    for obj in canvas.objects() {
        let SheetObject::Table(t) = obj;
        let (pos_col, pos_row) = t.position();
        let (width, height) = t.shape();
        max_row = max_row.max(*pos_row as u32 + height);
        max_col = max_col.max(*pos_col as u32 + width);
    }

    let mut grid = RawGrid::new(max_row + 1, max_col + 1);

    for obj in canvas.objects() {
        let SheetObject::Table(t) = obj;
        let (pos_col, pos_row) = t.position();
        let pos_row = *pos_row as u32;
        let pos_col = *pos_col as u32;

        for (col_idx, col) in t.schema().columns().iter().enumerate() {
            grid.set(pos_row, pos_col + col_idx as u32, col.name().to_string());
        }

        for (col_idx, series) in t.data().columns().iter().enumerate() {
            for row_idx in 0..series.len() {
                let val = match series.get(row_idx).unwrap() {
                    polars::prelude::AnyValue::String(s) => s.to_string(),
                    polars::prelude::AnyValue::StringOwned(s) => s.to_string(),
                    polars::prelude::AnyValue::Null => String::new(),
                    other => other.to_string(),
                };
                grid.set(pos_row + 1 + row_idx as u32, pos_col + col_idx as u32, val);
            }
        }
    }
    grid
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;

    fn make_grid(cells: &[((u32, u32), &str)], rows: u32, cols: u32) -> RawGrid {
        let mut grid = RawGrid::new(rows, cols);
        for ((row, col), val) in cells {
            grid.set(*row, *col, val.to_string());
        }
        grid
    }

    #[test]
    fn test_single_island() {
        let grid = make_grid(&[
            ((0, 0), "name"), ((0, 1), "age"),
            ((1, 0), "Alice"), ((1, 1), "30"),
            ((2, 0), "Bob"), ((2, 1), "25"),
        ], 10, 10);

        let islands = grid.find_islands().unwrap();
        assert_eq!(islands.len(), 1);
        assert_eq!(islands[0].min_row, 0);
        assert_eq!(islands[0].min_col, 0);
        assert_eq!(islands[0].max_row, 2);
        assert_eq!(islands[0].max_col, 1);
    }

    #[test]
    fn test_two_islands() {
        let grid = make_grid(&[
            ((0, 0), "name"), ((0, 1), "age"),
            ((1, 0), "Alice"), ((1, 1), "30"),
            // gap at row 2
            ((4, 5), "product"), ((4, 6), "price"),
            ((5, 5), "Widget"), ((5, 6), "9.99"),
        ], 10, 10);

        let islands = grid.find_islands().unwrap();
        assert_eq!(islands.len(), 2);
    }

    #[test]
    fn test_island_to_table() {
        let grid = make_grid(&[
            ((0, 0), "name"), ((0, 1), "age"),
            ((1, 0), "Alice"), ((1, 1), "30"),
            ((2, 0), "Bob"), ((2, 1), "25"),
        ], 10, 10);

        let islands = grid.find_islands().unwrap();
        let table = grid.island_to_table(&islands[0], "Sheet1", "Sheet1").unwrap();
        assert_eq!(table.name(), "Sheet1");
        assert_eq!(table.row_count(), 2);
        assert_eq!(table.col_count(), 2);
        assert_eq!(*table.position(), (0.0, 0.0));
    }

    #[test]
    fn test_island_position() {
        let grid = make_grid(&[
            ((3, 5), "city"), ((3, 6), "pop"),
            ((4, 5), "London"), ((4, 6), "9000000"),
        ], 10, 10);

        let islands = grid.find_islands().unwrap();
        let table = grid.island_to_table(&islands[0], "Sheet1", "Sheet1").unwrap();
        assert_eq!(*table.position(), (5.0, 3.0));
    }
}