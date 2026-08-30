# Spreadsheet AI

A local-first, privacy-preserving AI-native spreadsheet application built with a Rust backend and Flutter frontend. Data never leaves your machine.

> **Status: Archived** — This project reached a solid proof-of-concept stage and is preserved here as a demonstration of cross-platform native app development with Rust + Flutter.

---

## What It Is

Spreadsheet AI is a desktop spreadsheet application with a canvas-based data model. Rather than a fixed grid of cells, data lives as auto-detected "islands" — rectangular regions of connected cells that are automatically recognized as tables. The canvas is infinite and sandbox-style: you can type anywhere, and islands form, split, and merge reactively.

The long-term vision was an AI-native office suite (spreadsheet, word processor, IDE, presentation tool) where all AI/ML runs locally via Rust — no cloud, no data leaving the machine.

---

## Architecture

### Backend — Rust
- **`spreadsheet-ai/rust/`** — core library crate
- Sparse `RawGrid` using `HashMap<(u32, u32), String>` for canvas representation
- Island detection via BFS flood fill — connected non-empty cells form a `TableObject`
- DataFrames backed by [Polars](https://github.com/pola-rs/polars) for typed columnar storage
- `.sai` file format: Parquet for DataFrames + bincode for metadata
- Import: CSV and XLSX via `calamine` / `rust_xlsxwriter`
- Export: XLSX and CSV

### Bridge — flutter_rust_bridge v2
- **`spreadsheet-ai/flutter/rust/src/api/simple.rs`** — exposed bridge functions
- Codegen via `flutter_rust_bridge_codegen generate`
- Key bridge functions: `getTableData`, `editCell`, `setCanvasCell`, `importCsv`, `importXlsx`, `saveSai`, `openSai`

### Frontend — Flutter (macOS)
- **`spreadsheet-ai/flutter/lib/`**
- `TableView.builder` from `two_dimensional_scrollables` for virtualized grid rendering
- Custom cell selection, inline editing, formula bar
- Zoom via pinch gesture + slider
- Omnidirectional scroll via `DiagonalDragBehavior.free`

---

## What It Can Do

- **Import** CSV and XLSX files — data loads into the canvas as auto-detected table islands
- **Export** to XLSX and CSV
- **Save / Open** native `.sai` files (Parquet + bincode)
- **Display data** in a virtualized scrollable grid with column/row headers
- **Select cells** — single cell, drag to select ranges, Cmd+click for multi-select
- **Inline cell editing** — double-click or type to start editing, Enter to commit, click-off to commit and select new cell
- **Formula bar** — bidirectional sync with selected cell, editable, Enter commits
- **Delete cells** — Backspace/Delete clears selected data cells and headers
- **Create new data** — typing in any empty cell creates a new island on commit
- **Auto table detection** — island detection runs after every edit, tables form and reshape reactively
- **Synthetic headers** — tables created from empty cells get hidden `col_0`, `col_1` headers; only user-defined headers display
- **Header editing** — double-click a header to rename it
- **Zoom** — pinch gesture or slider (0.3×–4.0×)
- **Multi-sheet support** — multiple named sheets, tab bar to switch
- **macOS native** — PlatformMenuBar with File, Window menus and keyboard shortcuts for New, Open, Save, Save As

---

## What It Can't Do (Yet)

- **Arrow key navigation** — Flutter's `TableView` and `Shortcuts/Actions` system conflict; returning `true` from `HardwareKeyboard.addHandler` does not prevent `ScrollAction` from also consuming arrow keys. This is a known Flutter limitation and was deprioritized.
- **Column deletion** — deleting a header should remove the column and shift remaining columns; backend logic not implemented
- **Table splitting** — clearing a middle column/row via canvas-level operations should reactively split a table into two islands; region detection logic exists but is incomplete
- **Undo/Redo** — no history stack implemented
- **Row/column insertion** — insert above/below or left/right not implemented
- **AI/ML features** — the AI pipeline (Polars, DuckDB, LanceDB, Linfa, Candle, ONNX) was planned but not started
- **Cloud sync / auth** — Supabase integration planned but not started
- **Encryption** — AES-256-GCM with OS keychain planned but not started
- **iOS/Android/Windows** — macOS only; SwiftUI+UniFFI and Jetpack Compose+UniFFI paths were planned
- **Formula engine** — no formula evaluation (=SUM, etc.)

---

## Skills & Concepts Demonstrated

### Rust
- Ownership, borrowing, lifetimes
- `RwLock` vs `Mutex` for shared global state (`Lazy<RwLock<Workbook>>`)
- Sparse data structures (`HashMap` as a grid)
- BFS flood fill / connected-components island detection
- Polars DataFrames — creation, column access, cell mutation, schema inference
- `bincode` serialization (positional binary format — adding fields is a breaking change)
- Parquet persistence via Polars
- `calamine` for XLSX parsing, `rust_xlsxwriter` for XLSX export
- Error handling with custom `AppError` enum and `Result` propagation
- Modular crate structure with a separate bridge crate

### Flutter / Dart
- `flutter_rust_bridge` v2 codegen workflow
- `TableView.builder` from `two_dimensional_scrollables` for virtualized 2D grids
- Custom `HardwareKeyboard` handlers for type-to-edit
- `CallbackShortcuts` + `Focus` for key interception
- `GestureDetector` + `Listener` for pointer events, drag selection, double-tap
- `DiagonalDragBehavior.free` for omnidirectional scroll
- `PlatformMenuBar` for native macOS menus
- `TextEditingController` + `FocusNode` for inline cell editing
- `ValueKey` + `commitKey` pattern for forcing full widget rebuild after data commits
- `ExcludeFocus` / `skipTraversal` for focus isolation
- `WidgetsBinding.instance.addPostFrameCallback` for post-render actions
- Regex-based display filtering (`^col_\d+$`) for synthetic header hiding
- Sparse `HashMap` cell maps rebuilt on each commit

### Architecture Decisions
- **Frontend/backend boundary**: anything that must survive save/reload goes to Rust; display-only stays in Flutter
- **Local-first**: all computation in Rust, no network required
- **Reactive island detection**: every canvas edit rebuilds the raw grid and re-runs BFS detection over the affected region
- **Bincode compatibility**: struct fields in serialized types are positional — adding a field breaks existing `.sai` files; reverted `user_defined_headers` from `TableMetadata` for this reason

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Rust, Polars, bincode, calamine, rust_xlsxwriter |
| Bridge | flutter_rust_bridge v2 |
| Frontend | Flutter (Dart), two_dimensional_scrollables |
| File format | `.sai` (Parquet + bincode) |
| Platform | macOS (debug builds) |

---

## Running Locally

```bash
# From spreadsheet-ai/flutter/
flutter_rust_bridge_codegen generate
cargo build
flutter run -d macos
```

Requires: Rust toolchain, Flutter SDK, `flutter_rust_bridge_codegen` installed via cargo.

---

## Why It's Archived

This project served its purpose as a deep learning exercise in Rust systems programming, Flutter cross-platform development, and the flutter_rust_bridge FFI workflow. The core proof-of-concept — a reactive canvas with auto-detecting table islands backed by a Rust/Polars engine — works. Further development would require a Cargo workspace refactor, a formula engine, and resolving the Flutter key interception limitations before AI features could be layered on top.
