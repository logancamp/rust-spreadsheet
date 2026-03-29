import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';

class SpreadsheetGrid extends StatelessWidget {
  final List<TableInfo> tables;
  final List<TableData> tableData;

  const SpreadsheetGrid({
    super.key,
    required this.tables,
    required this.tableData,
  });

  Map<(int, int), String> _buildCellMap(List<TableInfo> tables, List<TableData> tableData) {
    final map = <(int, int), String>{};
    for (final info in tables) {
      final data = tableData.firstWhere(
        (d) => d.name == info.name,
        orElse: () => const TableData(name: '', columns: [], rows: []),
      );
      final startCol = info.position.$1.toInt() + 1;
      final startRow = info.position.$2.toInt() + 1;
      for (int c = 0; c < data.columns.length; c++) {
        map[(startRow, startCol + c)] = data.columns[c];
      }
      for (int r = 0; r < data.rows.length; r++) {
        for (int c = 0; c < data.rows[r].length; c++) {
          map[(startRow + r + 1, startCol + c)] = data.rows[r][c];
        }
      }
    }
    return map;
  }

  String _colLabel(int col) {
    String label = '';
    int c = col;
    do {
      label = String.fromCharCode(65 + (c % 26)) + label;
      c = (c ~/ 26) - 1;
    } while (c >= 0);
    return label;
  }

  @override
  Widget build(BuildContext context) {
    final cellMap = _buildCellMap(tables, tableData);
    return TableView.builder(
      rowCount: 1000,
      columnCount: 100,
      pinnedRowCount: 1,
      pinnedColumnCount: 1,
      rowBuilder: (index) => TableSpan(
        extent: FixedTableSpanExtent(25),
      ),
      columnBuilder: (index) => TableSpan(
        extent: FixedTableSpanExtent(index == 0 ? 50 : 100),
      ),
      cellBuilder: (context, vicinity) {
        final row = vicinity.row;
        final col = vicinity.column;
        if (row == 0 && col == 0) {
          return TableViewCell(child: _headerCell(''));
        }
        if (row == 0) {
          return TableViewCell(child: _headerCell(_colLabel(col - 1)));
        }
        if (col == 0) {
          return TableViewCell(child: _headerCell('$row'));
        }
        return TableViewCell(child: _dataCell(cellMap[(row, col)] ?? ''));
      },
    );
  }

  Widget _headerCell(String label) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFE8E8E8),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF444444),
        ),
      ),
    );
  }

  Widget _dataCell(String value) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.5),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}