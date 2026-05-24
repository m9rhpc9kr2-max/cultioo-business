import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Service that uses Google Gemini Vision API to detect documents
/// (ID cards, driver's licenses) in camera frames.
class GeminiDocumentDetector {
  static const String _apiKey = 'AIzaSyD9Amsf0p7-a4BQgPBpIybuzevv-dHMroE';

  static GenerativeModel? _cachedModel;
  static bool _isAnalyzing = false;

  /// Cached singleton — avoid creating a new model object on every scan
  static GenerativeModel get model {
    _cachedModel ??= GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.0,
        maxOutputTokens: 10,
      ),
    );
    return _cachedModel!;
  }

  /// Resize image to max 512px on the longest side before sending to Gemini.
  /// This dramatically reduces API latency and prevents UI lag.
  static Future<Uint8List> _resizeForApi(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      const maxDim = 512;
      if (decoded.width <= maxDim && decoded.height <= maxDim) return bytes;
      final scale = maxDim / min(decoded.width, decoded.height).toDouble();
      final resized = img.copyResize(
        decoded,
        width: (decoded.width * scale).round(),
        height: (decoded.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
    } catch (_) {
      return bytes;
    }
  }

  /// Detect whether a document is visible in the camera frame.
  ///
  /// [cameraController] - The active camera controller to capture a frame from.
  /// [documentType] - One of: 'id_front', 'id_back', 'license_front', 'license_back'
  ///
  /// Returns `true` if a document is detected in the frame, `false` otherwise.
  static Future<bool> detectDocument({
    required CameraController cameraController,
    required String documentType,
  }) async {
    // Prevent concurrent analysis calls
    if (_isAnalyzing) {
      print('🔍 Gemini: Already analyzing, skipping...');
      return false;
    }

    _isAnalyzing = true;

    try {
      // Capture a frame from the camera
      final XFile frame = await cameraController.takePicture();
      final Uint8List rawBytes = await File(frame.path).readAsBytes();
      final Uint8List imageBytes = await _resizeForApi(rawBytes);

      // Clean up the temp file
      try {
        await File(frame.path).delete();
      } catch (_) {}

      // Build the prompt based on document type
      final String docDescription = _getDocDescription(documentType);

      final prompt = '''Look at this camera image. Is there a $docDescription clearly visible and positioned within the center area of the image? 
Answer ONLY "yes" or "no". Nothing else.''';

      // Send to Gemini Vision
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ Gemini: Analysis timed out');
          throw Exception('Gemini timeout');
        },
      );

      final String? answer = response.text?.trim().toLowerCase();
      final bool detected = answer == 'yes';

      print('🤖 Gemini: $docDescription detected = $detected (raw: "$answer")');

      _isAnalyzing = false;
      return detected;
    } catch (e) {
      print('❌ Gemini detection error: $e');
      _isAnalyzing = false;
      return false;
    }
  }

  /// Get human-readable document description for the prompt
  static String _getDocDescription(String documentType) {
    switch (documentType) {
      case 'id_front':
        return 'government-issued ID card (front side)';
      case 'id_back':
        return 'government-issued ID card (back side)';
      case 'license_front':
        return "driver's license (front side)";
      case 'license_back':
        return "driver's license (back side)";
      default:
        return 'identification document';
    }
  }

  /// Detect whether a human face is clearly visible and centered in the frame.
  ///
  /// Used for the selfie step — checks that the person's face is well-positioned.
  /// Returns `true` if a face is properly positioned, `false` otherwise.
  static Future<bool> detectFace({
    required CameraController cameraController,
  }) async {
    if (_isAnalyzing) {
      print('🔍 Gemini: Already analyzing, skipping...');
      return false;
    }

    _isAnalyzing = true;

    try {
      final XFile frame = await cameraController.takePicture();
      final Uint8List rawBytes = await File(frame.path).readAsBytes();
      final Uint8List imageBytes = await _resizeForApi(rawBytes);

      try {
        await File(frame.path).delete();
      } catch (_) {}

      const prompt = '''Analyze this image carefully. Answer ONLY "yes" if ALL of the following are true:
1. There is exactly ONE real, live human face (not a photo, not a painting, not a drawing)
2. The face clearly shows eyes, nose and mouth
3. The face occupies at least 25% of the image area
4. The face is roughly centered in the image
5. The image is NOT a blank wall, ceiling, floor, object, or anything other than a close-up human face

If ANY condition is NOT met (e.g. wall, object, no face, obscured face, photo of a photo), answer "no".
Answer ONLY "yes" or "no". Nothing else.''';

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ Gemini: Face analysis timed out');
          throw Exception('Gemini timeout');
        },
      );

      final String? answer = response.text?.trim().toLowerCase();
      final bool detected = answer == 'yes';

      print('🤖 Gemini: Face detected = $detected (raw: "$answer")');

      _isAnalyzing = false;
      return detected;
    } catch (e) {
      print('❌ Gemini face detection error: $e');
      _isAnalyzing = false;
      return false;
    }
  }
}
