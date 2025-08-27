import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const PDFMergerApp());
}

class PDFMergerApp extends StatelessWidget {
  const PDFMergerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Merger & Editor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PDFMergerScreen(),
    );
  }
}

class PDFMergerScreen extends StatefulWidget {
  const PDFMergerScreen({super.key});

  @override
  State<PDFMergerScreen> createState() => _PDFMergerScreenState();
}

class _PDFMergerScreenState extends State<PDFMergerScreen> {
  List<Uint8List> selectedPDFBytes = [];
  String? mergedPath;

  Future<void> pickPDFs() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      withData: true,
    );

    if (result != null) {
      setState(() {
        selectedPDFBytes = result.files
            .where((f) => f.bytes != null)
            .map((f) => f.bytes!)
            .toList();
      });
    }
  }

  Future<void> mergePDFs() async {
    if (selectedPDFBytes.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pick at least 2 PDF files")),
      );
      return;
    }

    try {
      final PdfDocument newDocument = PdfDocument();
      PdfSection? section;

      for (final bytes in selectedPDFBytes) {
        final PdfDocument loaded = PdfDocument(inputBytes: bytes);

        for (int i = 0; i < loaded.pages.count; i++) {
          final PdfTemplate template = loaded.pages[i].createTemplate();

          if (section == null ||
              section.pageSettings.size != template.size) {
            section = newDocument.sections!.add();
            section.pageSettings.size = template.size;
            section.pageSettings.margins.all = 0;
          }
          section.pages
              .add()
              .graphics
              .drawPdfTemplate(template, const Offset(0, 0));
        }
        loaded.dispose();
      }

      final mergedBytes = await newDocument.save();
      newDocument.dispose();

      final downloadsDir = Directory('/storage/emulated/0/Download');
      final outPath =
          '${downloadsDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outFile = File(outPath);
      await outFile.writeAsBytes(mergedBytes, flush: true);

      setState(() => mergedPath = outPath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Merged PDF saved at: $outPath')),
      );
    } catch (e, st) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error merging PDFs: $e')),
      );
      debugPrint('$e\n$st');
    }
  }

  Future<void> pickPDFForDelete() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DeletePagesScreen(pdfBytes: result.files.single.bytes!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PDF Merger & Editor")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: pickPDFs,
              child: const Text("Pick PDF Files"),
            ),
            const SizedBox(height: 10),
            Text("Selected: ${selectedPDFBytes.length} files"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: mergePDFs,
              child: const Text("Merge PDFs"),
            ),
            const Divider(height: 40),
            ElevatedButton(
              onPressed: pickPDFForDelete,
              child: const Text("Delete Pages from PDF"),
            ),
            const SizedBox(height: 20),
            if (mergedPath != null)
              SelectableText("📂 Last merged file: $mergedPath"),
          ],
        ),
      ),
    );
  }
}

class DeletePagesScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  const DeletePagesScreen({super.key, required this.pdfBytes});

  @override
  State<DeletePagesScreen> createState() => _DeletePagesScreenState();
}

class _DeletePagesScreenState extends State<DeletePagesScreen> {
  late PdfDocument document;
  late List<bool> selectedPages;

  @override
  void initState() {
    super.initState();
    document = PdfDocument(inputBytes: widget.pdfBytes);
    selectedPages = List<bool>.filled(document.pages.count, false);
  }

  Future<void> deleteSelectedPages() async {
    final pagesToDelete = <int>[];
    for (int i = 0; i < selectedPages.length; i++) {
      if (selectedPages[i]) {
        pagesToDelete.add(i);
      }
    }

    if (pagesToDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pages selected")),
      );
      return;
    }

    // Delete pages (from last to first to avoid index shift)
    for (int i = pagesToDelete.length - 1; i >= 0; i--) {
      document.pages.removeAt(pagesToDelete[i]);
    }

    final newBytes = await document.save();
    document.dispose();

    final downloadsDir = Directory('/storage/emulated/0/Download');
    final outPath =
        '${downloadsDir.path}/deleted_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outFile = File(outPath);
    await outFile.writeAsBytes(newBytes, flush: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ New PDF saved at: $outPath')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Pages to Delete")),
      body: ListView.builder(
        itemCount: document.pages.count,
        itemBuilder: (context, index) {
          return CheckboxListTile(
            value: selectedPages[index],
            title: Text("Page ${index + 1}"),
            onChanged: (val) {
              setState(() => selectedPages[index] = val ?? false);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: deleteSelectedPages,
        child: const Icon(Icons.delete),
      ),
    );
  }
}