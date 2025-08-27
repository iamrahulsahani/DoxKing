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
      title: 'PDF Merger',
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
      withData: true, // ensures we get raw bytes
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

      // 🔽 Save into Android Downloads folder
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PDF Merger (Downloads Save)")),
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
            const SizedBox(height: 20),
            if (mergedPath != null)
              SelectableText("📂 Merged file: $mergedPath"),
          ],
        ),
      ),
    );
  }
}