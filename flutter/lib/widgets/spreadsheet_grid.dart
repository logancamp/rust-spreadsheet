import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';

class SpreadsheetGrid extends StatefulWidget {
  final List<TableInfo> tables;
  final List<TableData> tableData;

  const SpreadsheetGrid({
    super.key,
    required this.tables,
    required this.tableData,
  });

  @override
  State<SpreadsheetGrid> createState() => _SpreadsheetGridState();
}

class _SpreadsheetGridState extends State<SpreadsheetGrid> {
  (int, int)? _selectionStart;
  (int, int)? _selectionEnd;
  List<((int, int), (int, int))> _additionalSelections = [];

  double _scrollOffsetX = 0;
  double _scrollOffsetY = 0;
  bool _isDragging = false;
  Offset? _dragStartPosition;

  static const double _rowHeaderWidth = 50;
  static const double _colHeaderHeight = 25;
  static const double _cellWidth = 100;
  static const double _cellHeight = 25;

  bool get _isCommandHeld =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  (int, int)? _cellAtOffset(Offset offset) {
    final adjustedX = offset.dx + _scrollOffsetX;
    final adjustedY = offset.dy + _scrollOffsetY;
    if (adjustedX < _rowHeaderWidth || adjustedY < _colHeaderHeight) return null;
    final col = ((adjustedX - _rowHeaderWidth) / _cellWidth).floor() + 1;
    final row = ((adjustedY - _colHeaderHeight) / _cellHeight).floor() + 1;
    if (row < 1 || col < 1) return null;
    return (row, col);
  }

  int? _colHeaderAtOffset(Offset offset) {
    final adjustedX = offset.dx + _scrollOffsetX;
    final adjustedY = offset.dy + _scrollOffsetY;
    if (adjustedY >= _colHeaderHeight) return null;
    if (adjustedX < _rowHeaderWidth) return null;
    return ((adjustedX - _rowHeaderWidth) / _cellWidth).floor() + 1;
  }

  int? _rowHeaderAtOffset(Offset offset) {
    final adjustedX = offset.dx + _scrollOffsetX;
    final adjustedY = offset.dy + _scrollOffsetY;
    if (adjustedX >= _rowHeaderWidth) return null;
    if (adjustedY < _colHeaderHeight) return null;
    return ((adjustedY - _colHeaderHeight) / _cellHeight).floor() + 1;
  }

  void _handleTap(Offset localPosition) {
    final colHeader = _colHeaderAtOffset(localPosition);
    if (colHeader != null) {
      setState(() {
        if (_isCommandHeld && _selectionStart != null && _selectionEnd != null) {
          _additionalSelections.add((_selectionStart!, _selectionEnd!));
        } else {
          _additionalSelections = [];
        }
        _selectionStart = (1, colHeader);
        _selectionEnd = (999, colHeader);
      });
      return;
    }

    final rowHeader = _rowHeaderAtOffset(localPosition);
    if (rowHeader != null) {
      setState(() {
        if (_isCommandHeld && _selectionStart != null && _selectionEnd != null) {
          _additionalSelections.add((_selectionStart!, _selectionEnd!));
        } else {
          _additionalSelections = [];
        }
        _selectionStart = (rowHeader, 1);
        _selectionEnd = (rowHeader, 99);
      });
      return;
    }

    final cell = _cellAtOffset(localPosition);
    if (cell == null) return;
    if (_isCommandHeld) {
      setState(() {
        if (_selectionStart != null && _selectionEnd != null) {
          _additionalSelections.add((_selectionStart!, _selectionEnd!));
        }
        _selectionStart = cell;
        _selectionEnd = cell;
      });
    } else {
      setState(() {
        _selectionStart = cell;
        _selectionEnd = cell;
        _additionalSelections = [];
      });
    }
  }

  bool _inRange(int row, int col, (int, int)? start, (int, int)? end) {
    if (start == null || end == null) return false;
    final minRow = start.$1 < end.$1 ? start.$1 : end.$1;
    final maxRow = start.$1 > end.$1 ? start.$1 : end.$1;
    final minCol = start.$2 < end.$2 ? start.$2 : end.$2;
    final maxCol = start.$2 > end.$2 ? start.$2 : end.$2;
    return row >= minRow && row <= maxRow && col >= minCol && col <= maxCol;
  }

  bool _isSelected(int row, int col) {
    if (_inRange(row, col, _selectionStart, _selectionEnd)) return true;
    for (final sel in _additionalSelections) {
      if (_inRange(row, col, sel.$1, sel.$2)) return true;
    }
    return false;
  }

  bool _isRowHighlighted(int row) {
    if (_selectionStart != null && _selectionEnd != null) {
      final minRow = _selectionStart!.$1 < _selectionEnd!.$1 ? _selectionStart!.$1 : _selectionEnd!.$1;
      final maxRow = _selectionStart!.$1 > _selectionEnd!.$1 ? _selectionStart!.$1 : _selectionEnd!.$1;
      if (row >= minRow && row <= maxRow) return true;
    }
    for (final sel in _additionalSelections) {
      final minRow = sel.$1.$1 < sel.$2.$1 ? sel.$1.$1 : sel.$2.$1;
      final maxRow = sel.$1.$1 > sel.$2.$1 ? sel.$1.$1 : sel.$2.$1;
      if (row >= minRow && row <= maxRow) return true;
    }
    return false;
  }

  bool _isColHighlighted(int col) {
    if (_selectionStart != null && _selectionEnd != null) {
      final minCol = _selectionStart!.$2 < _selectionEnd!.$2 ? _selectionStart!.$2 : _selectionEnd!.$2;
      final maxCol = _selectionStart!.$2 > _selectionEnd!.$2 ? _selectionStart!.$2 : _selectionEnd!.$2;
      if (col >= minCol && col <= maxCol) return true;
    }
    for (final sel in _additionalSelections) {
      final minCol = sel.$1.$2 < sel.$2.$2 ? sel.$1.$2 : sel.$2.$2;
      final maxCol = sel.$1.$2 > sel.$2.$2 ? sel.$1.$2 : sel.$2.$2;
      if (col >= minCol && col <= maxCol) return true;
    }
    return false;
  }

  Border _borderForCell(int row, int col) {
    const green = BorderSide(color: Color(0xFF00B050), width: 1.5);
    const none = BorderSide(color: Color(0xFFD0D0D0), width: 0.5);

    if (!_isSelected(row, col)) {
      return Border.all(color: const Color(0xFFD0D0D0), width: 0.5);
    }

    return Border(
      top:    _isSelected(row - 1, col) ? none : green,
      bottom: _isSelected(row + 1, col) ? none : green,
      left:   _isSelected(row, col - 1) ? none : green,
      right:  _isSelected(row, col + 1) ? none : green,
    );
  }

  Map<(int, int), String> _buildCellMap() {
    final map = <(int, int), String>{};
    for (final info in widget.tables) {
      final data = widget.tableData.firstWhere(
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
    final cellMap = _buildCellMap();
    return Listener(
      onPointerDown: (event) {
        _isDragging = false;
        _dragStartPosition = event.localPosition;
        _handleTap(event.localPosition);
      },
      onPointerMove: (event) {
        if (_dragStartPosition != null) {
          final delta = (event.localPosition - _dragStartPosition!).distance;
          if (delta > 5) _isDragging = true;
        }
        if (_isDragging && _selectionStart != null) {
          // Check if dragging across col headers
          final colHeader = _colHeaderAtOffset(event.localPosition);
          if (colHeader != null) {
            setState(() => _selectionEnd = (999, colHeader));
            return;
          }
          // Check if dragging across row headers
          final rowHeader = _rowHeaderAtOffset(event.localPosition);
          if (rowHeader != null) {
            setState(() => _selectionEnd = (rowHeader, 99));
            return;
          }
          // Normal cell drag
          final cell = _cellAtOffset(event.localPosition);
          if (cell != null) {
            setState(() => _selectionEnd = cell);
          }
        }
      },
      onPointerUp: (_) {
        _isDragging = false;
        _dragStartPosition = null;
      },
      child: TableView.builder(
        rowCount: 1000,
        columnCount: 100,
        pinnedRowCount: 1,
        pinnedColumnCount: 1,
        rowBuilder: (index) => TableSpan(
          extent: FixedTableSpanExtent(_cellHeight),
        ),
        columnBuilder: (index) => TableSpan(
          extent: FixedTableSpanExtent(index == 0 ? _rowHeaderWidth : _cellWidth),
        ),
        cellBuilder: (context, vicinity) {
          final row = vicinity.row;
          final col = vicinity.column;

          if (row == 0 && col == 0) {
            return TableViewCell(child: _headerCell(''));
          }
          if (row == 0) {
            return TableViewCell(
              child: _headerCell(
                _colLabel(col - 1),
                highlighted: _isColHighlighted(col),
              ),
            );
          }
          if (col == 0) {
            return TableViewCell(
              child: _headerCell(
                '$row',
                highlighted: _isRowHighlighted(row),
              ),
            );
          }
          return TableViewCell(
            child: _dataCell(cellMap[(row, col)] ?? '', row, col),
          );
        },
      ),
    );
  }

  Widget _headerCell(String label, {bool highlighted = false}) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFD0D8C8) : const Color(0xFFE8E8E8),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
          color: const Color(0xFF444444),
        ),
      ),
    );
  }

  Widget _dataCell(String value, int row, int col) {
    final selected = _isSelected(row, col);
    final border = _borderForCell(row, col);
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8F5E9) : Colors.white,
        border: border,
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}