import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdfx/pdfx.dart' as pdfx;

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
      final sf.PdfDocument newDocument = sf.PdfDocument();
      sf.PdfSection? section;

      for (final bytes in selectedPDFBytes) {
        final sf.PdfDocument loaded = sf.PdfDocument(inputBytes: bytes);

        for (int i = 0; i < loaded.pages.count; i++) {
          final sf.PdfTemplate template = loaded.pages[i].createTemplate();

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
  late sf.PdfDocument document;
  late List<bool> selectedPages;
  List<Uint8List?> pageImages = [];
  bool isLoadingImages = true;

  @override
  void initState() {
    super.initState();
    document = sf.PdfDocument(inputBytes: widget.pdfBytes);
    selectedPages = List<bool>.filled(document.pages.count, false);
    _generatePagePreviews();
  }

  Future<void> _generatePagePreviews() async {
    setState(() {
      isLoadingImages = true;
      pageImages = List<Uint8List?>.filled(document.pages.count, null);
    });

    try {
      // Use pdfx to generate page previews
      final pdfDocument = await pdfx.PdfDocument.openData(widget.pdfBytes);

      for (int i = 0; i < document.pages.count && i < pdfDocument.pagesCount; i++) {
        try {
          final page = await pdfDocument.getPage(i + 1);
          final pageImage = await page.render(
            width: 200,
            height: 280,
            format: pdfx.PdfPageImageFormat.png,
          );
          page.close();

          if (mounted && pageImage != null && pageImage.bytes.isNotEmpty) {
            setState(() {
              pageImages[i] = pageImage.bytes;
            });
          }
        } catch (pageError) {
          debugPrint('Error rendering page ${i + 1}: $pageError');
        }
      }
      pdfDocument.close();
    } catch (e) {
      debugPrint('Error generating page previews: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingImages = false;
        });
      }
    }
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

    if (pagesToDelete.length >= document.pages.count) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot delete all pages. At least one page must remain.")),
      );
      return;
    }

    try {
      // Create a new document with only the pages we want to keep
      final sf.PdfDocument newDocument = sf.PdfDocument();
      sf.PdfSection? section;

      for (int i = 0; i < document.pages.count; i++) {
        if (!selectedPages[i]) {
          // Keep this page
          final sf.PdfTemplate template = document.pages[i].createTemplate();

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
      }

      final newBytes = await newDocument.save();
      newDocument.dispose();

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
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting pages: $e')),
        );
      }
      debugPrint('$e\n$st');
    }
  }

  void _selectAll() {
    setState(() {
      for (int i = 0; i < selectedPages.length; i++) {
        selectedPages[i] = true;
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (int i = 0; i < selectedPages.length; i++) {
        selectedPages[i] = false;
      }
    });
  }

  @override
  void dispose() {
    document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = selectedPages.where((selected) => selected).length;

    return Scaffold(
      appBar: AppBar(
        title: Text("Select Pages to Delete ($selectedCount selected)"),
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: const Text('Select All', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: _deselectAll,
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: isLoadingImages
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading page previews...'),
          ],
        ),
      )
          : GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: document.pages.count,
        itemBuilder: (context, index) {
          return Card(
            elevation: 4,
            child: InkWell(
              onTap: () {
                setState(() {
                  selectedPages[index] = !selectedPages[index];
                });
              },
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selectedPages[index]
                                  ? Colors.red
                                  : Colors.grey.shade300,
                              width: selectedPages[index] ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: pageImages[index] != null
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              pageImages[index]!,
                              fit: BoxFit.contain,
                            ),
                          )
                              : const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: selectedPages[index]
                                  ? Colors.red
                                  : Colors.grey.shade200,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              selectedPages[index]
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: selectedPages[index]
                                  ? Colors.white
                                  : Colors.grey,
                              size: 24,
                            ),
                          ),
                        ),
                        if (selectedPages[index])
                          Container(
                            margin: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Page ${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selectedPages[index]
                            ? Colors.red
                            : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: selectedCount > 0 ? deleteSelectedPages : null,
        backgroundColor: selectedCount > 0 ? Colors.red : Colors.grey,
        icon: const Icon(Icons.delete),
        label: Text('Delete $selectedCount pages'),
      ),
    );
  }
}