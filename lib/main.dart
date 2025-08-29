import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';

void main() {
  runApp(const PDFMergerApp());
}

class PDFMergerApp extends StatelessWidget {
  const PDFMergerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Merger & Scanner',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PDFMergerScreen(),
      debugShowCheckedModeBanner: false,
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
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

          if (section == null || section.pageSettings.size != template.size) {
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DeletePagesScreen(
            pdfBytes: result.files.single.bytes!,
          ),
        ),
      );
    }
  }

  Future<void> lockPDF() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final pdfBytes = result.files.single.bytes!;
      final TextEditingController passCtrl = TextEditingController();

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Set PDF Password"),
          content: TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: "Enter password"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, passCtrl.text),
              child: const Text("OK"),
            ),
          ],
        ),
      ).then((password) async {
        if (password != null && password.isNotEmpty) {
          try {
            final sf.PdfDocument document = sf.PdfDocument(inputBytes: pdfBytes);
            document.security.userPassword = password;
            document.security.ownerPassword = password;
            document.security.permissions.addAll([
              sf.PdfPermissionsFlags.print,
              sf.PdfPermissionsFlags.copyContent,
              sf.PdfPermissionsFlags.fillFields,
            ]);

            final newBytes = await document.save();
            document.dispose();

            final downloadsDir = Directory('/storage/emulated/0/Download');
            final outPath =
                '${downloadsDir.path}/locked_${DateTime.now().millisecondsSinceEpoch}.pdf';
            final outFile = File(outPath);
            await outFile.writeAsBytes(newBytes, flush: true);

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('🔒 PDF locked & saved at: $outPath')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error locking PDF: $e')),
            );
          }
        }
      });
    }
  }

  Future<void> unlockPDF() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final pdfBytes = result.files.single.bytes!;
      final TextEditingController passCtrl = TextEditingController();

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Enter PDF Password"),
          content: TextField(
            controller: passCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: "Password"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, passCtrl.text),
              child: const Text("OK"),
            ),
          ],
        ),
      ).then((password) async {
        if (password != null && password.isNotEmpty) {
          try {
            final sf.PdfDocument document = sf.PdfDocument(
              inputBytes: pdfBytes,
              password: password,
            );

            // Save without password
            document.security.userPassword = '';
            document.security.ownerPassword = '';

            final newBytes = await document.save();
            document.dispose();

            final downloadsDir = Directory('/storage/emulated/0/Download');
            final outPath =
                '${downloadsDir.path}/unlocked_${DateTime.now().millisecondsSinceEpoch}.pdf';
            final outFile = File(outPath);
            await outFile.writeAsBytes(newBytes, flush: true);

            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('🔓 PDF unlocked & saved at: $outPath')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('❌ Wrong password or error unlocking PDF')),
            );
          }
        }
      });
    }
  }

  Future<void> startImageScanning() async {
    final cameraStatus = await Permission.camera.request();
    final storageStatus = await Permission.storage.request();

    if (cameraStatus.isGranted || storageStatus.isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ImageScannerScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera and storage permissions are required')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PDF Merger & Scanner")),
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
            const Divider(height: 40),
            ElevatedButton.icon(
              onPressed: startImageScanning,
              icon: const Icon(Icons.scanner),
              label: const Text("Scan Images to PDF"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const Divider(height: 40),
            ElevatedButton(
              onPressed: lockPDF,
              child: const Text("🔒 Lock PDF"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: unlockPDF,
              child: const Text("🔓 Unlock PDF"),
            ),
            ElevatedButton(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf'],
                  allowMultiple: false,
                  withData: true,
                );
                if (result != null && result.files.single.bytes != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AnnotateSignScreen(pdfBytes: result.files.single.bytes!),
                    ),
                  );
                }
              },
              child: const Text("✍️ Annotate & Sign PDF"),
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

class ImageScannerScreen extends StatefulWidget {
  const ImageScannerScreen({super.key});

  @override
  State<ImageScannerScreen> createState() => _ImageScannerScreenState();
}

class _ImageScannerScreenState extends State<ImageScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<ProcessedImage> _images = [];
  bool _isProcessing = false;

  // One global filter for all pages
  ImageFilter _globalFilter = ImageFilter.none;

  Future<void> _pickImageFromCamera() async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 90,
    );

    if (shot != null) {
      // Crop right after taking a picture
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: shot.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.blue,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
            // In v8+, aspect presets live INSIDE platform UI settings:
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.square,
            ],
          ),
        ],
      );

      if (cropped != null) {
        await _processImage(XFile(cropped.path));
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 90,
    );
    for (final image in images) {
      await _processImage(image);
    }
  }

  Future<void> _processImage(XFile imageFile) async {
    setState(() => _isProcessing = true);
    try {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Image file is empty');
      }
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Failed to decode image');
      }
      setState(() {
        _images.add(ProcessedImage(
          originalBytes: bytes,
          decoded: decoded,
        ));
      });
    } catch (e) {
      debugPrint('Error processing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Uint8List _getFilteredImageBytes(ProcessedImage item) {
    try {
      // Safest clone: re-decode from original bytes (avoids mutating shared buffer)
      img.Image filtered = img.decodeImage(item.originalBytes)!;

      switch (_globalFilter) {
        case ImageFilter.blackAndWhite:
          filtered = img.grayscale(filtered);
          // Adjust contrast a bit for crisper B&W
          filtered = img.adjustColor(filtered, contrast: 1.35);
          break;
        case ImageFilter.sepia:
          filtered = img.sepia(filtered);
          break;
        case ImageFilter.highContrast:
          filtered = img.grayscale(filtered); // first make B&W
          filtered = img.adjustColor(filtered, contrast: 1.5, brightness: 1.0);

          break;
        case ImageFilter.none:
        default:
        // No changes
          break;
      }

      return Uint8List.fromList(img.encodePng(filtered));
    } catch (e) {
      debugPrint('Filter error: $e');
      return item.originalBytes;
    }
  }

  Future<void> _createPDF() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No images to create PDF')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final sf.PdfDocument document = sf.PdfDocument();

      for (final pageImage in _images) {
        final bytes = _getFilteredImageBytes(pageImage);
        final sf.PdfBitmap bitmap = sf.PdfBitmap(bytes);

        final sf.PdfPage page = document.pages.add();
        final Size pageSize = page.getClientSize();

        final double imageAspect = bitmap.width / bitmap.height;
        final double pageAspect = pageSize.width / pageSize.height;

        double drawW, drawH;
        if (imageAspect > pageAspect) {
          drawW = pageSize.width;
          drawH = pageSize.width / imageAspect;
        } else {
          drawH = pageSize.height;
          drawW = pageSize.height * imageAspect;
        }

        final double x = (pageSize.width - drawW) / 2;
        final double y = (pageSize.height - drawH) / 2;

        page.graphics.drawImage(
          bitmap,
          Rect.fromLTWH(x, y, drawW, drawH),
        );
      }

      final List<int> bytes = await document.save();
      document.dispose();

      final downloadsDir = Directory('/storage/emulated/0/Download');
      final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ PDF saved: ${file.path}')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  String _filterLabel(ImageFilter f) {
    switch (f) {
      case ImageFilter.none:
        return 'Original';
      case ImageFilter.blackAndWhite:
        return 'B&W';
      case ImageFilter.sepia:
        return 'Sepia';
      case ImageFilter.highContrast:
        return 'High Contrast';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scanner (${_images.length} images)'),
        actions: [
          if (_images.isNotEmpty)
            DropdownButton<ImageFilter>(
              value: _globalFilter,
              underline: const SizedBox(),
              items: ImageFilter.values
                  .map((f) => DropdownMenuItem(
                value: f,
                child: Text(_filterLabel(f)),
              ))
                  .toList(),
              onChanged: (f) {
                if (f != null) setState(() => _globalFilter = f);
              },
            ),
          if (_images.isNotEmpty)
            TextButton(
              onPressed: _isProcessing ? null : _createPDF,
              child: const Text(
                'Create PDF',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: _isProcessing
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing...'),
          ],
        ),
      )
          : _images.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.scanner, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No images scanned yet',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Use the camera or gallery buttons below',
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _images.length,
        itemBuilder: (_, i) {
          final bytes = _getFilteredImageBytes(_images[i]);
          return Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
                IconButton(
                  onPressed: () => _removeImage(i),
                  icon: const Icon(Icons.delete, color: Colors.red),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FloatingActionButton.extended(
            onPressed: _isProcessing ? null : _pickImageFromCamera,
            heroTag: "camera",
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
          ),
          FloatingActionButton.extended(
            onPressed: _isProcessing ? null : _pickImageFromGallery,
            heroTag: "gallery",
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
          ),
        ],
      ),
    );
  }
}

enum ImageFilter { none, blackAndWhite, sepia, highContrast }

class ProcessedImage {
  final Uint8List originalBytes;
  final img.Image decoded;

  ProcessedImage({
    required this.originalBytes,
    required this.decoded,
  });
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
      final pdfDocument = await pdfx.PdfDocument.openData(widget.pdfBytes);

      for (int i = 0; i < document.pages.count && i < pdfDocument.pagesCount; i++) {
        try {
          final page = await pdfDocument.getPage(i + 1);
          final pageImage = await page.render(
            width: 200,
            height: 280,
            format: pdfx.PdfPageImageFormat.png,
          );
          await page.close();

          if (mounted && pageImage != null && pageImage.bytes.isNotEmpty) {
            setState(() {
              pageImages[i] = pageImage.bytes;
            });
          }
        } catch (pageError) {
          debugPrint('Error rendering page ${i + 1}: $pageError');
        }
      }
      await pdfDocument.close();
    } catch (e) {
      debugPrint('Error generating page previews: $e');
    } finally {
      if (mounted) {
        setState(() => isLoadingImages = false);
      }
    }
  }

  Future<void> deleteSelectedPages() async {
    final toDelete = <int>[];
    for (int i = 0; i < selectedPages.length; i++) {
      if (selectedPages[i]) toDelete.add(i);
    }

    if (toDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pages selected")),
      );
      return;
    }

    if (toDelete.length >= document.pages.count) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot delete all pages. At least one page must remain.")),
      );
      return;
    }

    try {
      final sf.PdfDocument newDocument = sf.PdfDocument();
      sf.PdfSection? section;

      for (int i = 0; i < document.pages.count; i++) {
        if (!selectedPages[i]) {
          final sf.PdfTemplate template = document.pages[i].createTemplate();

          if (section == null || section.pageSettings.size != template.size) {
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ New PDF saved at: $outPath')),
      );
      Navigator.pop(context);
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
    final selectedCount = selectedPages.where((s) => s).length;

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
                        color: selectedPages[index] ? Colors.red : Colors.black,
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

/// ---------- Annotate & Sign screen with overlays, direct page drawing ----------
class OverlayItem {
  final Uint8List bytes;
  final Offset position; // PDF coordinates (we use approximate mapping based on preview)
  final Size size; // PDF coordinate size
  OverlayItem({required this.bytes, required this.position, required this.size});
}

class AnnotateSignScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  const AnnotateSignScreen({super.key, required this.pdfBytes});

  @override
  State<AnnotateSignScreen> createState() => _AnnotateSignScreenState();
}

class _AnnotateSignScreenState extends State<AnnotateSignScreen> {
  late sf.PdfDocument document; // in-memory editable PDF
  pdfx.PdfDocument? pdfViewDoc; // for page previews
  final List<Uint8List?> pageImages = [];
  bool isLoading = true;

  // Overlays per page index (temporary until user saves)
  final Map<int, List<OverlayItem>> _overlays = {};

  // Page view controller for single-page view (makes overlays easier)
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Drawing state
  bool _isDrawing = false;
  final GlobalKey<SfSignaturePadState> _drawKey = GlobalKey();

  // Signature key for dialog (sign)
  final GlobalKey<SfSignaturePadState> _sigKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    document = sf.PdfDocument(inputBytes: widget.pdfBytes);
    _loadPreviews();
  }

  Future<void> _loadPreviews() async {
    pdfViewDoc = await pdfx.PdfDocument.openData(widget.pdfBytes);
    pageImages.clear();
    for (int i = 0; i < (pdfViewDoc?.pagesCount ?? 0); i++) {
      final page = await pdfViewDoc!.getPage(i + 1);
      final img = await page.render(
        width: 1000, // high resolution for better preview
        height: 1400,
        format: pdfx.PdfPageImageFormat.png,
      );
      await page.close();
      pageImages.add(img?.bytes);
    }
    if (mounted) setState(() => isLoading = false);
  }

  @override
  void dispose() {
    document.dispose();
    pdfViewDoc?.close();
    _pageController.dispose();
    super.dispose();
  }

  // Helper to add overlay to a page (temporary)
  void _addOverlayToPage(int pageIndex, Uint8List bytes,
      {Offset position = Offset.zero, Size? size}) {
    final s = size ?? const Size(200, 80);
    final item = OverlayItem(bytes: bytes, position: position, size: s);
    _overlays.putIfAbsent(pageIndex, () => []);
    _overlays[pageIndex]!.add(item);
    setState(() {}); // refresh overlays on screen
  }

  // Signature: open dialog, let user draw signature, then add overlay to current page
  Future<void> _showSignatureDialogAndAdd() async {
    final Uint8List? sigBytes = await showDialog<Uint8List?>(
      context: context,
      builder: (_) {
        final GlobalKey<SfSignaturePadState> localSigKey = GlobalKey();
        return AlertDialog(
          title: const Text('Draw Signature'),
          content: SizedBox(
            height: 220,
            child: SfSignaturePad(
              key: localSigKey,
              backgroundColor: Colors.grey[200]!,
              strokeColor: Colors.black,
              minimumStrokeWidth: 2,
              maximumStrokeWidth: 4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => localSigKey.currentState?.clear(),
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ui.Image? image = await localSigKey.currentState?.toImage();
                if (image != null) {
                  final ByteData? bd = await image.toByteData(format: ui.ImageByteFormat.png);
                  if (bd != null) {
                    Navigator.pop(context, bd.buffer.asUint8List());
                    return;
                  }
                }
                Navigator.pop(context, null);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (sigBytes != null) {
      // Add overlay centered near bottom of page preview
      // Convert preview coordinate assumptions to overlay position.
      final previewWidth = _previewSizeForPage(_currentPage).width;
      final previewHeight = _previewSizeForPage(_currentPage).height;
      final pos = Offset(previewWidth * 0.3, previewHeight * 0.7);
      final size = Size(previewWidth * 0.4, previewHeight * 0.12);

      _addOverlayToPage(_currentPage, sigBytes, position: pos, size: size);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signature added (not saved)')));
    }
  }

  // Toggle draw mode: when active a transparent signature pad is placed on top of the page preview
  void _toggleDrawMode() {
    setState(() {
      _isDrawing = !_isDrawing;
      // Clear internal pad strokes when entering drawing mode to start fresh
      if (_isDrawing) {
        _drawKey.currentState?.clear();
      }
    });
  }

  // Finalize drawing: capture pad as image and add as overlay
  Future<void> _finalizeDrawingForCurrentPage() async {
    final ui.Image? drawnImg = await _drawKey.currentState?.toImage(pixelRatio: 2.0);
    if (drawnImg == null) {
      setState(() => _isDrawing = false);
      return;
    }
    final ByteData? bd = await drawnImg.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) {
      setState(() => _isDrawing = false);
      return;
    }
    final bytes = bd.buffer.asUint8List();

    // Overlay full-area drawing scaled to preview
    final previewSize = _previewSizeForPage(_currentPage);
    _addOverlayToPage(_currentPage, bytes, position: Offset.zero, size: previewSize);

    setState(() {
      _isDrawing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drawing added (not saved)')));
  }

  // Save: write all overlays into the PDF (burn them to pages) and save file
  Future<void> _saveAnnotatedPDF() async {
    try {
      // For each page overlays, map overlay preview coords to PDF page coords.
      for (final entry in _overlays.entries) {
        final pageIndex = entry.key; // zero-based
        final overlaysForPage = entry.value;
        if (pageIndex >= document.pages.count) continue;

        final pdfPage = document.pages[pageIndex];
        final pageSize = pdfPage.getClientSize(); // PDF page logical size

        // get preview size to compute scale between preview image and PDF page
        final previewSize = _previewSizeForPage(pageIndex);

        // scale factors: preview -> pdf
        final sx = pageSize.width / previewSize.width;
        final sy = pageSize.height / previewSize.height;

        for (final ov in overlaysForPage) {
          final pdfX = ov.position.dx * sx;
          final pdfY = ov.position.dy * sy;
          final pdfW = ov.size.width * sx;
          final pdfH = ov.size.height * sy;

          final bmp = sf.PdfBitmap(ov.bytes);
          pdfPage.graphics.drawImage(bmp, Rect.fromLTWH(pdfX, pdfY, pdfW, pdfH));
        }
      }

      final List<int> newBytes = await document.save();
      final downloadsDir = Directory('/storage/emulated/0/Download');
      final outPath =
          '${downloadsDir.path}/annotated_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outFile = File(outPath);
      await outFile.writeAsBytes(newBytes, flush: true);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✍️ Saved annotated PDF at: $outPath')));

      // Optionally clear overlays after saving (keep as persisted state if you like)
      _overlays.clear();
      setState(() {});
    } catch (e, st) {
      debugPrint('Error saving annotated PDF: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error saving annotated PDF')));
    }
  }

  // compute preview size for given page (we used fixed render in _loadPreviews)
  Size _previewSizeForPage(int pageIndex) {
    // We rendered with width:1000 height:1400. If pageImages are null, return defaults.
    if (pageImages.isEmpty || pageImages[pageIndex] == null) {
      return const Size(1000, 1400);
    }
    final bytes = pageImages[pageIndex]!;
    // we don't decode dimensions here; we used fixed render size so return those:
    return const Size(1000, 1400);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotate & Sign'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAnnotatedPDF,
            tooltip: 'Save annotated PDF',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // page indicator + toolbar (simple)
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text('Page ${_currentPage + 1}/${pageImages.length}'),
                const Spacer(),
                IconButton(
                  icon: Icon(_isDrawing ? Icons.check : Icons.brush),
                  tooltip: _isDrawing ? 'Finish Drawing' : 'Draw on page',
                  onPressed: () {
                    if (_isDrawing) {
                      _finalizeDrawingForCurrentPage();
                    } else {
                      _toggleDrawMode();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.border_color),
                  tooltip: 'Add signature (dialog)',
                  onPressed: _showSignatureDialogAndAdd,
                ),
                IconButton(
                  icon: const Icon(Icons.post_add),
                  tooltip: 'Add note (popup annotation)',
                  onPressed: () async {
                    // Add a popup note overlay - we store it as a small blue box overlay for preview,
                    // and on save we'll also write a PdfPopupAnnotation into the PDF page.
                    // For simplicity we add a visual overlay and also add a PdfPopupAnnotation to document,
                    // but NOT save the document until user presses Save (so preview+save behavior matches).
                    const noteText = 'Note';
                    // small blue marker overlay
                    final marker = await _makeNoteMarkerBytes();
                    final previewSize = _previewSizeForPage(_currentPage);
                    final pos = Offset(previewSize.width * 0.05, previewSize.height * 0.05);
                    final size = Size(previewSize.width * 0.06, previewSize.width * 0.06);
                    _addOverlayToPage(_currentPage, marker, position: pos, size: size);

                    // Add actual PDF popup annotation into in-memory document (still not saved to disk).
                    try {
                      final page = document.pages[_currentPage];
                      final rect = Rect.fromLTWH(50, 50, 20, 20); // PDF coordinates approximate
                      final popup = sf.PdfPopupAnnotation(rect, 'Note content');
                      popup.color = sf.PdfColor(0, 0, 255);
                      page.annotations.add(popup);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note added (not saved)')));
                    } catch (e) {
                      debugPrint('Error adding popup annotation: $e');
                    }
                  },
                ),
              ],
            ),
          ),

          // Page view with overlayed temporary items & drawing pad when active
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: pageImages.length,
              onPageChanged: (idx) => setState(() => _currentPage = idx),
              itemBuilder: (ctx, index) {
                final bytes = pageImages[index];
                if (bytes == null) return const SizedBox();
                final previewSize = _previewSizeForPage(index);

                return InteractiveViewer(
                  child: Stack(
                    children: [
                      // base PDF page preview
                      Center(
                        child: Image.memory(bytes),
                      ),

                      // overlays for this page
                      if (_overlays.containsKey(index))
                        ..._overlays[index]!.map((ov) {
                          return Positioned(
                            left: ov.position.dx,
                            top: ov.position.dy,
                            child: Image.memory(
                              ov.bytes,
                              width: ov.size.width,
                              height: ov.size.height,
                            ),
                          );
                        }).toList(),

                      // drawing pad overlay when drawing on current page
                      if (_isDrawing && index == _currentPage)
                        Positioned.fill(
                          child: Container(
                            color: Colors.transparent,
                            child: SfSignaturePad(
                              key: _drawKey,
                              backgroundColor: Colors.transparent,
                              strokeColor: Colors.red,
                              minimumStrokeWidth: 2,
                              maximumStrokeWidth: 4,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // Floating actions: previous/next page and shortcuts
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // prev page
          FloatingActionButton(
            heroTag: 'prev',
            mini: true,
            child: const Icon(Icons.chevron_left),
            onPressed: () {
              final prev = (_currentPage - 1).clamp(0, pageImages.length - 1);
              _pageController.animateToPage(prev, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            },
          ),
          const SizedBox(height: 8),
          // next page
          FloatingActionButton(
            heroTag: 'next',
            mini: true,
            child: const Icon(Icons.chevron_right),
            onPressed: () {
              final next = (_currentPage + 1).clamp(0, pageImages.length - 1);
              _pageController.animateToPage(next, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
            },
          ),
          const SizedBox(height: 12),
          // open signature dialog
          FloatingActionButton.extended(
            heroTag: 'sigFab',
            label: const Text('Sign'),
            icon: const Icon(Icons.edit),
            onPressed: _showSignatureDialogAndAdd,
          ),
          const SizedBox(height: 8),
          // toggle draw
          FloatingActionButton.extended(
            heroTag: 'drawFab',
            label: Text(_isDrawing ? 'Finish' : 'Draw'),
            icon: Icon(_isDrawing ? Icons.check : Icons.brush),
            onPressed: () {
              if (_isDrawing) {
                _finalizeDrawingForCurrentPage();
              } else {
                _toggleDrawMode();
              }
            },
          ),
          const SizedBox(height: 8),
          // Save (duplicate in app bar)
          FloatingActionButton.extended(
            heroTag: 'saveFab',
            label: const Text('Save'),
            icon: const Icon(Icons.save),
            onPressed: _saveAnnotatedPDF,
          ),
        ],
      ),
    );
  }

  // small helper to create a simple note marker PNG bytes (blue circle) to use as visual overlay
  Future<Uint8List> _makeNoteMarkerBytes() async {
    final recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const size = 80.0;
    final paint = Paint()..color = Colors.blue;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }
}