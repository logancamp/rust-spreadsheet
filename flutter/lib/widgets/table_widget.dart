import 'package:flutter/material.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';

class TableWidget extends StatelessWidget {
  const TableWidget({super.key, required this.data});
  final TableData data;


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: data.columns.map((col) => DataColumn(label: Text(col))).toList(),
          rows: data.rows.map((row) => DataRow(
            cells: row.map((cell) => DataCell(Text(cell))).toList(),
          )).toList(),
        ),
      ),
    );
  }
}