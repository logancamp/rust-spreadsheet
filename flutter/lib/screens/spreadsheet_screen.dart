import 'package:flutter/material.dart';
import '../services/bridge_service.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';
import '../widgets/table_widget.dart';

class SpreadsheetScreen extends StatefulWidget {
  const SpreadsheetScreen({super.key});

  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  TableData? _tableData;

  @override
  void initState() {
    super.initState();
    setState(() {
      _tableData = BridgeService.loadCsv(
          'test', "name,age,city\nAlice,30,NYC\nBob,25,LA\nClara,35,Chicago");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spreadsheet AI'),
      ),
      body: _tableData == null
          ? const Center(child: Text('Loading...'))
          : TableWidget(data: _tableData!),
    );
  }
}
