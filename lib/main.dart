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

class AnnotateSignScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  const AnnotateSignScreen({super.key, required this.pdfBytes});

  @override
  State<AnnotateSignScreen> createState() => _AnnotateSignScreenState();
}

class _AnnotateSignScreenState extends State<AnnotateSignScreen> {
  late sf.PdfDocument document;
  pdfx.PdfDocument? pdfViewDoc;
  final List<Uint8List?> pageImages = [];
  bool isLoading = true;
  final GlobalKey<SfSignaturePadState> _sigKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    document = sf.PdfDocument(inputBytes: widget.pdfBytes);
    _loadPreviews();
  }

  Future<void> _loadPreviews() async {
    pdfViewDoc = await pdfx.PdfDocument.openData(widget.pdfBytes);
    for (int i = 0; i < (pdfViewDoc?.pagesCount ?? 0); i++) {
      final page = await pdfViewDoc!.getPage(i + 1);
      final img = await page.render(
        width: 300,
        height: 400,
        format: pdfx.PdfPageImageFormat.png,
      );
      await page.close();
      pageImages.add(img?.bytes);
    }
    if (mounted) setState(() => isLoading = false);
  }

  // Add signature bytes to first page (or change target page/position as needed)
  Future<void> _addSignatureFromBytes(Uint8List data) async {
    try {
      final sigImg = sf.PdfBitmap(data);
      final page = document.pages[0]; // first page
      // Draw image at chosen position:
      page.graphics.drawImage(sigImg, const Rect.fromLTWH(100, 500, 200, 80));
      await _saveAnnotatedPDF();
    } catch (e) {
      debugPrint('Error adding signature: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding signature: $e')),
        );
      }
    }
  }

  // Highlight implemented as a semi-opaque rectangle overlay to avoid API overload ambiguity
  Future<void> _highlightText() async {
    try {
      final page = document.pages[0];
      final Rect highlightBounds = const Rect.fromLTWH(50, 600, 200, 20);

      // draw semi-transparent rectangle (visual highlight)
      page.graphics.drawRectangle(
        brush: sf.PdfSolidBrush(sf.PdfColor(255, 255, 0, 120)),
        bounds: highlightBounds,
      );

      await _saveAnnotatedPDF();
    } catch (e) {
      debugPrint('Error adding highlight: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding highlight: $e')),
        );
      }
    }
  }

  Future<void> _addNote() async {
    try {
      final page = document.pages[0];
      final note = sf.PdfPopupAnnotation(
        const Rect.fromLTWH(50, 650, 20, 20),
        'This is a note',
      );
      note.color = sf.PdfColor(0, 0, 255);
      page.annotations.add(note);

      await _saveAnnotatedPDF();
    } catch (e) {
      debugPrint('Error adding note: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding note: $e')),
        );
      }
    }
  }

  Future<void> _saveAnnotatedPDF() async {
    final newBytes = await document.save();
    final downloadsDir = Directory('/storage/emulated/0/Download');
    final outPath =
        '${downloadsDir.path}/annotated_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outFile = File(outPath);
    await outFile.writeAsBytes(newBytes, flush: true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✍️ Saved annotated PDF at: $outPath')),
    );
  }

  @override
  void dispose() {
    document.dispose();
    pdfViewDoc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Annotate & Sign"),
        actions: [
          IconButton(
            icon: const Icon(Icons.brush),
            onPressed: _highlightText,
          ),
          IconButton(
            icon: const Icon(Icons.note_add),
            onPressed: _addNote,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAnnotatedPDF,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: pageImages.length,
        itemBuilder: (_, i) {
          return Card(
            margin: const EdgeInsets.all(8),
            child: pageImages[i] != null
                ? Image.memory(pageImages[i]!)
                : const SizedBox(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Show signature dialog. Capture signature BEFORE closing the dialog.
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Sign PDF"),
              content: SizedBox(
                height: 200,
                child: SfSignaturePad(
                  key: _sigKey,
                  backgroundColor: Colors.grey[200]!,
                  strokeColor: Colors.black,
                  minimumStrokeWidth: 2,
                  maximumStrokeWidth: 4,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // clear current strokes
                    _sigKey.currentState?.clear();
                  },
                  child: const Text("Clear"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Capture signature image while dialog is still open
                    final ui.Image? signatureImage = await _sigKey.currentState?.toImage();
                    if (signatureImage != null) {
                      final ByteData? bdata = await signatureImage.toByteData(format: ui.ImageByteFormat.png);                      if (bdata != null) {
                        final bytes = bdata.buffer.asUint8List();
                        await _addSignatureFromBytes(bytes);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Failed to capture signature bytes')),
                          );
                        }
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No signature drawn')),
                        );
                      }
                    }
                    Navigator.pop(context); // close dialog after capturing
                  },
                  child: const Text("Add Signature"),
                ),
              ],
            ),
          );
        },
        label: const Text("Sign"),
        icon: const Icon(Icons.edit),
      ),
    );
  }
}