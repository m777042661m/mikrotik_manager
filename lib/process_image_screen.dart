import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ProcessImageScreen extends StatefulWidget {
  final String imagePath;
  final String prefix;
  final int length;
  final int total;

  const ProcessImageScreen({
    super.key,
    required this.imagePath,
    required this.prefix,
    required this.length,
    required this.total,
  });

  @override
  State<ProcessImageScreen> createState() => _ProcessImageScreenState();
}

class _ProcessImageScreenState extends State<ProcessImageScreen> {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  String _status = 'جاري معالجة الصورة...';

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _processImage() async {
    try {
      // Image is already cropped and rectified by the document scanner.
      // Read image from file
      final imageBytes = await File(widget.imagePath).readAsBytes();
      final originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        throw Exception("Failed to decode image");
      }

      // 1. Convert to grayscale
      setState(() {
        _status = 'تحويل الصورة إلى أبيض وأسود...';
      });
      final grayscaleImage = img.grayscale(originalImage);
      
      // 2. Adjust contrast
      setState(() {
        _status = 'تحسين وضوح الأرقام...';
      });
      final contrastImage = img.adjustColor(grayscaleImage, contrast: 1.5);

      // Save the processed image to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'processed_image.jpg');
      await File(tempPath).writeAsBytes(img.encodeJpg(contrastImage));

      // 3. Perform OCR on the processed image
      setState(() {
        _status = 'جاري استخراج الأرقام...';
      });
      final inputImage = InputImage.fromFilePath(tempPath);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final RegExp numberRegExp = RegExp(r'\d+');
      final Set<String> cardNumbers = {};

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final String cleanedLine = line.text.replaceAll(RegExp(r'[^0-9]'), '');
          final numbersInLine =
              numberRegExp.allMatches(cleanedLine).map((m) => m.group(0)!);

          for (String numberStr in numbersInLine) {
            if (numberStr.length == widget.length &&
                numberStr.startsWith(widget.prefix)) {
              cardNumbers.add(numberStr);
              if (cardNumbers.length >= widget.total) {
                break;
              }
            }
          }
          if (cardNumbers.length >= widget.total) break;
        }
        if (cardNumbers.length >= widget.total) break;
      }

      Navigator.pop(context, cardNumbers.toList());
    } catch (e) {
      print("Error processing image: $e");
      Navigator.pop(context, []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معالجة الصورة'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_status),
            const SizedBox(height: 10),
            const Text('العملية قد تستغرق بعض الوقت...'),
          ],
        ),
      ),
    );
  }
}
