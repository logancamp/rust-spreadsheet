import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';

class SpreadsheetGrid extends StatefulWidget {
  final List<TableInfo> tables;
  final List<TableData> tableData;
  final void Function(
    (int, int)? cell,
    String value,
    String? tableName,
    String? colName,
    int? rowIndex,
    bool isNew,
  )? onCellSelected;
  final void Function(
    (int, int) cell,
    String value,
    String? tableName,
    String? colName,
    int? rowIndex,
    bool isNew,
  )? onCellCommit;
  final void Function(
    (int, int) cell,
    String? tableName,
    String? colName,
    int? rowIndex,
    bool isNew,
  )? onCellDeleteCommit;
  final void Function((int, int)? start, (int, int)? end, String value)? onSelectionChanged;
  final void Function(double)? onScaleChanged;
  final void Function(String value)? onCellValueChanged;
  final double? externalScale;
  final String? formulaBarValue;
  final (int, int)? formulaBarCell;
  final bool formulaBarFocused;

  const SpreadsheetGrid({
    super.key,
    required this.tables,
    required this.tableData,
    this.onCellSelected,
    this.onCellCommit,
    this.onCellDeleteCommit,
    this.onSelectionChanged,
    this.onScaleChanged,
    this.onCellValueChanged,
    this.externalScale,
    this.formulaBarValue,
    this.formulaBarCell,
    this.formulaBarFocused = false,
  });

  @override
  State<SpreadsheetGrid> createState() => _SpreadsheetGridState();
}

class _SpreadsheetGridState extends State<SpreadsheetGrid> {
  (int, int)? _selectionStart;
  (int, int)? _selectionEnd;
  List<((int, int), (int, int))> _additionalSelections = [];
  Map<(int, int), Set<String>> _tableBorderMap = {};

  double _scrollOffsetX = 0;
  double _scrollOffsetY = 0;
  bool _isDragging = false;
  Offset? _dragStartPosition;
  Timer? _autoScrollTimer;
  double _scale = 1.0;
  double _lastScale = 1.0;

  Map<(int, int), String> _cellMap = {};
  Map<(int, int), bool> _numericMap = {};
  Map<(int, int), ({String tableName, String colName, int rowIndex, bool isNew})> _cellInfoMap = {};

  (int, int)? _lastTappedCell;
  DateTime? _lastTapTime;

  (int, int)? _inlineEditingCell;
  final TextEditingController _inlineCellController = TextEditingController();

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  static const double _rowHeaderWidth = 50;
  static const double _colHeaderHeight = 25;
  static const double _cellWidth = 100;
  static const double _cellHeight = 25;

  bool get _isCommandHeld =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  double get _scaledRowHeaderWidth => _rowHeaderWidth * _scale;
  double get _scaledColHeaderHeight => _colHeaderHeight * _scale;
  double get _scaledCellWidth => _cellWidth * _scale;
  double get _scaledCellHeight => _cellHeight * _scale;

  @override
  void initState() {
    super.initState();
    if (widget.externalScale != null) _scale = widget.externalScale!;
    _rebuildCellMap();
    _verticalScrollController.addListener(() => _scrollOffsetY = _verticalScrollController.offset);
    _horizontalScrollController.addListener(() => _scrollOffsetX = _horizontalScrollController.offset);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void didUpdateWidget(SpreadsheetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalScale != null && widget.externalScale != oldWidget.externalScale) {
      setState(() => _scale = widget.externalScale!);
    }
    if (_inlineEditingCell == null &&
        (widget.tables != oldWidget.tables || widget.tableData != oldWidget.tableData)) {
      setState(() => _rebuildCellMap());
    }
    if (widget.formulaBarValue != oldWidget.formulaBarValue &&
        widget.formulaBarCell != null &&
        _inlineEditingCell == null) {
      setState(() => _cellMap[widget.formulaBarCell!] = widget.formulaBarValue ?? '');
    }
  }

  void _rebuildCellMap() {
    final newCellMap = <(int, int), String>{};
    final newNumericMap = <(int, int), bool>{};
    final newCellInfoMap = <(int, int), ({String tableName, String colName, int rowIndex, bool isNew})>{};

    for (final info in widget.tables) {
      final data = widget.tableData.firstWhere(
        (d) => d.name == info.name,
        orElse: () => const TableData(
          name: '',
          columns: [],
          rows: [],
        ),
      );
      final startCol = info.position.$1.toInt() + 1;
      final startRow = info.position.$2.toInt() + 1;

      // Column headers
      for (int c = 0; c < data.columns.length; c++) {
        final key = (startRow, startCol + c);
        final colName = data.columns[c];
        final isSynthetic = RegExp(r'^col_\d+$').hasMatch(colName);
        newCellMap[key] = isSynthetic ? '' : colName;
        newNumericMap[key] = false;
        newCellInfoMap[key] = (tableName: info.name, colName: colName, rowIndex: -1, isNew: false);
      }

      // Data cells
      for (int r = data.rows.length; r < data.rows.length + 5; r++) {
        for (int c = 0; c < data.columns.length; c++) {
          final key = (startRow + r + 1, startCol + c);
          if (!newCellInfoMap.containsKey(key)) {
            newCellInfoMap[key] = (tableName: info.name, colName: data.columns[c], rowIndex: r, isNew: true);
          }
        }
      }

      // Extra empty rows for appending
      for (int r = data.rows.length; r < data.rows.length + 20; r++) {
        for (int c = 0; c < data.columns.length; c++) {
          final key = (startRow + r + 1, startCol + c);
          if (!newCellInfoMap.containsKey(key)) {
            newCellInfoMap[key] = (tableName: info.name, colName: data.columns[c], rowIndex: r, isNew: true);
          }
        }
      }
    }

    _cellMap = newCellMap;
    _numericMap = newNumericMap;
    _cellInfoMap = newCellInfoMap;
    _tableBorderMap = _buildTableBorderMap();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (widget.formulaBarFocused) return false;
    if (_selectionStart == null) return false;
    if (_inlineEditingCell != null) return false;
    if (_isCommandHeld) return false;

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final toDelete = <(int, int)>[];
      for (final key in _cellInfoMap.keys) {
        if (_isSelected(key.$1, key.$2)) {
          final info = _cellInfoMap[key];
          if (info != null && info.rowIndex >= 0 && !info.isNew) {
            toDelete.add(key);
          }
        }
      }
      for (final key in toDelete) {
        final info = _cellInfoMap[key]!;
        setState(() => _cellMap[key] = '');
        widget.onCellDeleteCommit?.call(key, info.tableName, info.colName, info.rowIndex, info.isNew);
      }
      if (toDelete.isNotEmpty) {
        setState(() {
          _selectionStart = null;
          _selectionEnd = null;
          _additionalSelections = [];
        });
      }
      return toDelete.isNotEmpty;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      final cell = _selectionStart!;
      final info = _cellInfoMap[cell];

      // Allow any cell — table data rows, empty rows, and non-table cells
      if (info == null || info.rowIndex >= 0) {
        _inlineCellController.text = char;
        _inlineCellController.selection = TextSelection.collapsed(offset: char.length);
        _cellMap[cell] = char;
        setState(() => _inlineEditingCell = cell);
        widget.onCellValueChanged?.call(char);
        return true;
      }
    }

    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _autoScrollTimer?.cancel();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _inlineCellController.dispose();
    super.dispose();
  }

  (int, int)? _cellAtOffset(Offset offset) {
    final adjustedX = offset.dx + _scrollOffsetX;
    final adjustedY = offset.dy + _scrollOffsetY;
    if (adjustedX < _scaledRowHeaderWidth || adjustedY < _scaledColHeaderHeight) return null;
    final col = ((adjustedX - _scaledRowHeaderWidth) / _scaledCellWidth).floor() + 1;
    final row = ((adjustedY - _scaledColHeaderHeight) / _scaledCellHeight).floor() + 1;
    if (row < 1 || col < 1) return null;
    return (row, col);
  }

  int? _colHeaderAtOffset(Offset offset) {
    if (offset.dy >= _scaledColHeaderHeight) return null;
    if (offset.dx < _scaledRowHeaderWidth) return null;
    return ((offset.dx + _scrollOffsetX - _scaledRowHeaderWidth) / _scaledCellWidth).floor() + 1;
  }

  int? _rowHeaderAtOffset(Offset offset) {
    if (offset.dx >= _scaledRowHeaderWidth) return null;
    if (offset.dy < _scaledColHeaderHeight) return null;
    return ((offset.dy + _scrollOffsetY - _scaledColHeaderHeight) / _scaledCellHeight).floor() + 1;
  }

  void _startAutoScrollIfNeeded(Offset position) {
    _autoScrollTimer?.cancel();
    const edgeSize = 40.0;
    const scrollSpeed = 10.0;
    double dx = 0;
    double dy = 0;
    if (position.dx < _scaledRowHeaderWidth + edgeSize) dx = -scrollSpeed;
    if (context.size != null && position.dx > context.size!.width - edgeSize) dx = scrollSpeed;
    if (position.dy < _scaledColHeaderHeight + edgeSize) dy = -scrollSpeed;
    if (context.size != null && position.dy > context.size!.height - edgeSize) dy = scrollSpeed;
    if (dx == 0 && dy == 0) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (dx != 0 && _horizontalScrollController.hasClients) {
        _horizontalScrollController.jumpTo(
          (_horizontalScrollController.offset + dx).clamp(0, _horizontalScrollController.position.maxScrollExtent),
        );
      }
      if (dy != 0 && _verticalScrollController.hasClients) {
        _verticalScrollController.jumpTo(
          (_verticalScrollController.offset + dy).clamp(0, _verticalScrollController.position.maxScrollExtent),
        );
      }
    });
  }

  void _startInlineEdit((int, int) cell) {
    final info = _cellInfoMap[cell];
    if (info != null && info.rowIndex < 0) return;
    final currentValue = _cellMap[cell] ?? '';
    _inlineCellController.text = currentValue;
    _inlineCellController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentValue.length,
    );
    setState(() => _inlineEditingCell = cell);
  }

  void _handleTap(Offset localPosition) {
    if (_inlineEditingCell != null) {
      final editCell = _inlineEditingCell!;
      final v = _inlineCellController.text;
      final info = _cellInfoMap[editCell];
      setState(() {
        _cellMap[editCell] = v;
        _inlineEditingCell = null;
        _selectionStart = null;
        _selectionEnd = null;
      });
      widget.onCellCommit?.call(
        editCell, v,
        info?.tableName, info?.colName, info?.rowIndex,
        info?.isNew ?? false,
      );
      return;
    }

    if (localPosition.dx < _scaledRowHeaderWidth && localPosition.dy < _scaledColHeaderHeight) {
      final isAllSelected = _selectionStart == (1, 1) && _selectionEnd == (999, 99);
      setState(() {
        _selectionStart = isAllSelected ? null : (1, 1);
        _selectionEnd = isAllSelected ? null : (999, 99);
        _additionalSelections = [];
      });
      widget.onSelectionChanged?.call(_selectionStart, _selectionEnd, '');
      return;
    }

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
      widget.onCellSelected?.call(null, '', null, null, null, false);
      widget.onSelectionChanged?.call((1, colHeader), (999, colHeader), '');
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
      widget.onCellSelected?.call(null, '', null, null, null, false);
      widget.onSelectionChanged?.call((rowHeader, 1), (rowHeader, 99), '');
      return;
    }

    final cell = _cellAtOffset(localPosition);
    if (cell == null) return;

    final now = DateTime.now();
    final isDoubleTap = _lastTappedCell == cell &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 400;

    _lastTappedCell = cell;
    _lastTapTime = now;

    if (isDoubleTap) {
      _startInlineEdit(cell);
      return;
    }

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
    final value = _cellMap[cell] ?? '';
    final info = _cellInfoMap[cell];
    widget.onCellSelected?.call(cell, value, info?.tableName, info?.colName, info?.rowIndex, info?.isNew ?? false);
    widget.onSelectionChanged?.call(cell, cell, value);
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
    const tableBorder = BorderSide(color: Color(0xFF888888), width: 1.0);

    if (_isSelected(row, col)) {
      return Border(
        top:    _isSelected(row - 1, col) ? none : green,
        bottom: _isSelected(row + 1, col) ? none : green,
        left:   _isSelected(row, col - 1) ? none : green,
        right:  _isSelected(row, col + 1) ? none : green,
      );
    }

    final tableSides = _tableBorderMap[(row, col)];
    if (tableSides != null) {
      return Border(
        top:    tableSides.contains('top') ? tableBorder : none,
        bottom: tableSides.contains('bottom') ? tableBorder : none,
        left:   tableSides.contains('left') ? tableBorder : none,
        right:  tableSides.contains('right') ? tableBorder : none,
      );
    }

    return Border.all(color: const Color(0xFFD0D0D0), width: 0.5);
  }

  Map<(int, int), Set<String>> _buildTableBorderMap() {
    final map = <(int, int), Set<String>>{};
    for (final info in widget.tables) {
      final startCol = info.position.$1.toInt() + 1;
      final startRow = info.position.$2.toInt() + 1;
      final endCol = startCol + info.cols - 1;
      final endRow = startRow + info.rows;
      for (int r = startRow; r <= endRow; r++) {
        for (int c = startCol; c <= endCol; c++) {
          final key = (r, c);
          map[key] ??= {};
          if (r == startRow) map[key]!.add('top');
          if (r == endRow) map[key]!.add('bottom');
          if (c == startCol) map[key]!.add('left');
          if (c == endCol) map[key]!.add('right');
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
    return GestureDetector(
      onScaleStart: (details) => _lastScale = _scale,
      onScaleUpdate: (details) {
        if (details.pointerCount >= 2) {
          final focalPoint = details.localFocalPoint;
          final oldScale = _scale;
          final newScale = (_lastScale * details.scale).clamp(0.3, 4.0);
          final newScrollX = (focalPoint.dx + _scrollOffsetX) * (newScale / oldScale) - focalPoint.dx;
          final newScrollY = (focalPoint.dy + _scrollOffsetY) * (newScale / oldScale) - focalPoint.dy;
          setState(() => _scale = newScale);
          widget.onScaleChanged?.call(newScale);
          if (_horizontalScrollController.hasClients) {
            _horizontalScrollController.jumpTo(newScrollX.clamp(0.0, _horizontalScrollController.position.maxScrollExtent));
          }
          if (_verticalScrollController.hasClients) {
            _verticalScrollController.jumpTo(newScrollY.clamp(0.0, _verticalScrollController.position.maxScrollExtent));
          }
        }
      },
      child: Listener(
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
          if (_isDragging && _selectionStart != null && _inlineEditingCell == null) {
            _startAutoScrollIfNeeded(event.localPosition);
            final colHeader = _colHeaderAtOffset(event.localPosition);
            if (colHeader != null) { setState(() => _selectionEnd = (999, colHeader)); return; }
            final rowHeader = _rowHeaderAtOffset(event.localPosition);
            if (rowHeader != null) { setState(() => _selectionEnd = (rowHeader, 99)); return; }
            final cell = _cellAtOffset(event.localPosition);
            if (cell != null) setState(() => _selectionEnd = cell);
          }
        },
        onPointerUp: (_) {
          _isDragging = false;
          _dragStartPosition = null;
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          if (_inlineEditingCell == null) {
            final value = (_selectionStart == _selectionEnd && _selectionStart != null)
                ? _cellMap[_selectionStart] ?? '' : '';
            widget.onSelectionChanged?.call(_selectionStart, _selectionEnd, value);
          }
        },
        child: TableView.builder(
          diagonalDragBehavior: DiagonalDragBehavior.free,
          rowCount: 1000,
          columnCount: 100,
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          verticalDetails: ScrollableDetails.vertical(controller: _verticalScrollController),
          horizontalDetails: ScrollableDetails.horizontal(controller: _horizontalScrollController),
          rowBuilder: (index) => TableSpan(extent: FixedTableSpanExtent(_scaledCellHeight)),
          columnBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(index == 0 ? _scaledRowHeaderWidth : _scaledCellWidth),
          ),
          cellBuilder: (context, vicinity) {
            final row = vicinity.row;
            final col = vicinity.column;
            if (row == 0 && col == 0) {
              return TableViewCell(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E8E8),
                    border: Border.all(color: const Color(0xFFD0D0D0), width: 0.5),
                  ),
                  child: CustomPaint(painter: _CornerTrianglePainter()),
                ),
              );
            }
            if (row == 0) {
              return TableViewCell(child: _headerCell(_colLabel(col - 1), highlighted: _isColHighlighted(col)));
            }
            if (col == 0) {
              return TableViewCell(child: _headerCell('$row', highlighted: _isRowHighlighted(row)));
            }
            return TableViewCell(child: _dataCell(_cellMap[(row, col)] ?? '', row, col));
          },
        ),
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
          fontSize: 12 * _scale,
          fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
          color: const Color(0xFF444444),
        ),
      ),
    );
  }

  Widget _dataCell(String value, int row, int col) {
    final selected = _isSelected(row, col);
    final border = _borderForCell(row, col);
    final isNumeric = _numericMap[(row, col)] == true;
    final isEditing = _inlineEditingCell == (row, col);

    return Container(
      alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: 4 * _scale),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8F5E9) : Colors.white,
        border: border,
      ),
      child: isEditing
          ? TextField(
              controller: _inlineCellController,
              autofocus: true,
              style: TextStyle(fontSize: 12 * _scale),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                _cellMap[(row, col)] = v;
                widget.onCellValueChanged?.call(v);
              },
              onSubmitted: (v) {
                final info = _cellInfoMap[(row, col)];
                setState(() {
                  _cellMap[(row, col)] = v;
                  _inlineEditingCell = null;
                  _selectionStart = null;
                  _selectionEnd = null;
                });
                widget.onCellCommit?.call(
                  (row, col), v,
                  info?.tableName, info?.colName, info?.rowIndex,
                  info?.isNew ?? false,
                );
              },
            )
          : Text(value, style: TextStyle(fontSize: 12 * _scale), overflow: TextOverflow.ellipsis),
    );
  }
}

class _CornerTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(size.width - 8, size.height)
      ..lineTo(size.width, size.height - 8)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerTrianglePainter oldDelegate) => false;
}