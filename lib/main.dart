import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

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

  Future<void> startImageScanning() async {
    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    final storageStatus = await Permission.storage.request();

    if (cameraStatus.isGranted || storageStatus.isGranted) {
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
  List<ProcessedImage> _images = [];
  bool _isProcessing = false;

  Future<void> _pickImageFromCamera() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 90,
    );

    if (image != null) {
      await _processImage(image);
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

      final decodedImage = img.decodeImage(bytes);

      if (decodedImage != null && decodedImage.width > 0 && decodedImage.height > 0) {
        setState(() {
          _images.add(ProcessedImage(
            originalBytes: bytes,
            processedImage: decodedImage,
            currentFilter: ImageFilter.none,
          ));
        });
      } else {
        throw Exception('Failed to decode image or invalid dimensions');
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _applyFilter(int index, ImageFilter filter) {
    setState(() {
      _images[index].currentFilter = filter;
    });
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
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

      for (int i = 0; i < _images.length; i++) {
        final processedImageData = _getFilteredImageBytes(_images[i]);
        final sf.PdfBitmap bitmap = sf.PdfBitmap(processedImageData);

        final sf.PdfPage page = document.pages.add();
        final Size pageSize = page.getClientSize();

        // Calculate image dimensions to fit page
        final double imageAspectRatio = bitmap.width / bitmap.height;
        final double pageAspectRatio = pageSize.width / pageSize.height;

        double drawWidth, drawHeight;
        if (imageAspectRatio > pageAspectRatio) {
          drawWidth = pageSize.width;
          drawHeight = pageSize.width / imageAspectRatio;
        } else {
          drawHeight = pageSize.height;
          drawWidth = pageSize.height * imageAspectRatio;
        }

        final double x = (pageSize.width - drawWidth) / 2;
        final double y = (pageSize.height - drawHeight) / 2;

        page.graphics.drawImage(
          bitmap,
          Rect.fromLTWH(x, y, drawWidth, drawHeight),
        );
      }

      final List<int> bytes = await document.save();
      document.dispose();

      final downloadsDir = Directory('/storage/emulated/0/Download');
      final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ PDF saved: ${file.path}')),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating PDF: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Uint8List _getFilteredImageBytes(ProcessedImage processedImage) {
    try {
      // Create a copy of the original image
      img.Image filteredImage = img.Image.from(processedImage.processedImage);

      switch (processedImage.currentFilter) {
        case ImageFilter.blackAndWhite:
          filteredImage = img.grayscale(filteredImage);
          // Increase contrast for black and white
          filteredImage = img.contrast(filteredImage, contrast: 1.5);
          break;
        case ImageFilter.sepia:
          filteredImage = img.sepia(filteredImage);
          break;
        case ImageFilter.highContrast:
          filteredImage = img.contrast(filteredImage, contrast: 2.0);
          // Apply additional brightness adjustment by manipulating pixels
          filteredImage = img.adjustColor(filteredImage, brightness: 1.1);
          break;
        case ImageFilter.none:
        default:
        // No filter applied
          break;
      }

      return Uint8List.fromList(img.encodePng(filteredImage));
    } catch (e) {
      debugPrint('Error applying filter: $e');
      // Return original bytes if filter fails
      return processedImage.originalBytes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scanner (${_images.length} images)'),
        actions: [
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
            Text(
              'No images scanned yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the camera or gallery buttons below',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _images.length,
        itemBuilder: (context, index) {
          return _buildImageCard(index);
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

  Widget _buildImageCard(int index) {
    final processedImage = _images[index];

    // Use a fallback mechanism for image display
    Widget imageWidget;

    try {
      if (processedImage.currentFilter == ImageFilter.none) {
        // Show original image without processing to avoid errors
        imageWidget = Image.memory(
          processedImage.originalBytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } else {
        // Apply filter for preview
        final imageBytes = _getFilteredImageBytes(processedImage);
        imageWidget = Image.memory(
          imageBytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to original image if filter fails
            return Image.memory(
              processedImage.originalBytes,
              fit: BoxFit.contain,
            );
          },
        );
      }
    } catch (e) {
      debugPrint('Error building image widget: $e');
      imageWidget = const Center(
        child: Icon(Icons.error, color: Colors.red),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview
          SizedBox(
            height: 200,
            width: double.infinity,
            child: imageWidget,
          ),

          // Filter options
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Page ${index + 1} - Filters:',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ImageFilter.values.map((filter) {
                    final isSelected = processedImage.currentFilter == filter;
                    return FilterChip(
                      label: Text(_getFilterName(filter)),
                      selected: isSelected,
                      onSelected: (_) => _applyFilter(index, filter),
                      selectedColor: Colors.blue.withOpacity(0.3),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Current: ${_getFilterName(processedImage.currentFilter)}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    IconButton(
                      onPressed: () => _removeImage(index),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Remove image',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getFilterName(ImageFilter filter) {
    switch (filter) {
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
}

enum ImageFilter {
  none,
  blackAndWhite,
  sepia,
  highContrast,
}

class ProcessedImage {
  final Uint8List originalBytes;
  final img.Image processedImage;
  ImageFilter currentFilter;

  ProcessedImage({
    required this.originalBytes,
    required this.processedImage,
    required this.currentFilter,
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
      final sf.PdfDocument newDocument = sf.PdfDocument();
      sf.PdfSection? section;

      for (int i = 0; i < document.pages.count; i++) {
        if (!selectedPages[i]) {
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