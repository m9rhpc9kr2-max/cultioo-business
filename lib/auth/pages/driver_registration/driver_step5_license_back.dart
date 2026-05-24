import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // For MediaType
import 'dart:convert';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../config/api_config.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/services/gemini_document_detector.dart';
import '../../../shared/widgets/trade_republic_tap.dart';


class DriverStep5LicenseBack extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const DriverStep5LicenseBack({
    super.key,
    required this.initialData,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<DriverStep5LicenseBack> createState() => _DriverStep5LicenseBackState();
}

class _DriverStep5LicenseBackState extends State<DriverStep5LicenseBack>
    with TickerProviderStateMixin {
  // Image file for back of driver's license
  File? _licenseBackImage;
  String? _licenseBackImageUrl; // URL from server after upload

  // Camera controller
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];
  String _cameraError = '';
  bool _isInitializingCamera = false;

  // License detection state
  bool _isLicenseDetected = false;
  int _countdown = 0;
  bool _isCountingDown = false;

  // Modal state setter for live updates
  StateSetter? _modalSetState;

  // Capture success animation
  bool _showCaptureSuccess = false;

  // Animation Controllers
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    print('📷 Step 6: initState() called - Initializing License Back page');
    _setupAnimations();
    _loadInitialData();
    // Camera will be initialized when modal opens
    print('📷 Step 6: initState() completed');
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut));

    _fadeController.forward();
  }

  void _loadInitialData() {
    // Load existing data if any
    final String? licenseBackPath = widget.initialData['licenseBackImagePath'];
    final String? licenseBackUrl = widget.initialData['licenseBackImageUrl'];

    if (licenseBackPath != null && licenseBackPath.isNotEmpty) {
      _licenseBackImage = File(licenseBackPath);
    }

    if (licenseBackUrl != null && licenseBackUrl.isNotEmpty) {
      _licenseBackImageUrl = licenseBackUrl;
    }
  }

  // Upload image to server
  Future<String?> _uploadImageToServer(
    File imageFile,
    String documentType) async {
    try {
      print('📤 Uploading $documentType image to server...');

      final String baseUrl = ApiConfig.baseUrl; // Backend URL from ApiConfig
      final uri = Uri.parse('$baseUrl/api/documents/upload-document');

      // Get username from initial data
      final username = widget.initialData['username'] ?? 'unknown';

      // Create multipart request
      var request = http.MultipartRequest('POST', uri);

      // Add fields
      request.fields['username'] = username;
      request.fields['documentType'] = documentType;

      // Add file with explicit content type
      var fileStream = http.ByteStream(imageFile.openRead());
      var fileLength = await imageFile.length();

      // Ensure filename has .jpg extension
      String filename = path.basename(imageFile.path);
      if (!filename.toLowerCase().endsWith('.jpg') &&
          !filename.toLowerCase().endsWith('.jpeg') &&
          !filename.toLowerCase().endsWith('.png')) {
        filename = '$filename.jpg';
      }

      var multipartFile = http.MultipartFile(
        'image',
        fileStream,
        fileLength,
        filename: filename,
        contentType: MediaType('image', 'jpeg'), // Explicit JPEG content type
      );
      request.files.add(multipartFile);

      print('📤 Sending upload request...');

      // Send request
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('📥 Upload response status: ${response.statusCode}');
      print('📥 Upload response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['data'] != null) {
          final String imageUrl = responseData['data']['url'];
          print('✅ Image uploaded successfully!');
          print('🌐 Image URL: $imageUrl');

          return imageUrl;
        }
      }

      print('❌ Upload failed: ${response.body}');
      return null;
    } catch (e) {
      print('❌ Upload error: $e');
      return null;
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera || _isCameraInitialized) {
      print('⚠️ Camera already initializing or initialized, skipping...');
      return;
    }

    try {
      print('🎥 Starting camera initialization...');

      if (mounted) {
        setState(() {
          _isInitializingCamera = true;
          _cameraError = '';
        });
      }

      try {
        _cameras = await availableCameras().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('❌ Camera discovery timeout');
            throw Exception('Camera discovery timeout');
          });
      } catch (e) {
        print('❌ Failed to get cameras: $e');
        if (mounted) {
          setState(() {
            _cameraError = AppLocalizations.of(context)?.couldNotAccessCamera ?? 'Could not access camera. Please check permissions.';
            _isInitializingCamera = false;
          });
        }
        return;
      }

      print('📷 Available cameras: ${_cameras.length}');

      if (_cameras.isEmpty) {
        print('❌ No cameras available');
        if (mounted) {
          setState(() {
            _cameraError = AppLocalizations.of(context)?.noCamerasFound ?? 'No cameras found on this device';
            _isInitializingCamera = false;
          });
        }
        return;
      }

      print('🎬 Initializing camera controller...');

      try {
        await _cameraController?.dispose();
      } catch (e) {
        print('⚠️ Error disposing old camera: $e');
      }

      _cameraController = CameraController(
        _cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg);

      try {
        await _cameraController!.initialize().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('❌ Camera initialization timeout');
            throw Exception('Camera initialization timeout');
          });
      } catch (e) {
        print('❌ Camera initialization failed: $e');
        if (mounted) {
          setState(() {
            _cameraError = AppLocalizations.of(context)?.cameraInitFailed ?? 'Camera initialization failed. Please try again.';
            _isInitializingCamera = false;
          });
        }
        return;
      }

      try {
        await _cameraController!.setFlashMode(FlashMode.off);
        print('✅ Camera initialized successfully with flash OFF');
      } catch (e) {
        print('⚠️ Could not set flash mode: $e');
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isInitializingCamera = false;
        });

        if (_modalSetState != null) {
          _modalSetState!(() {});
        }
      }

      print('✅ Camera fully initialized and ready!');
    } catch (e) {
      print('❌ Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _cameraError = AppLocalizations.of(context)?.cameraErrorRetry ?? 'Camera error. Please try again.';
          _isInitializingCamera = false;
        });

        if (_modalSetState != null) {
          _modalSetState!(() {});
        }
      }
    }
  }

  void _startRealisticLicenseDetection() {
    // Continuous AI scanning - check every 500ms for better responsiveness
    _continuousLicenseScan();
  }

  void _continuousLicenseScan() {
    if (!mounted || !_isCameraInitialized) return;

    // Check for license back in frame every 2 seconds (Gemini API call)
    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted && _isCameraInitialized && !_isCountingDown && _cameraController != null) {
        print('🔍 Gemini: Scanning for driver\'s license back in frame...');

        final bool licenseInFrame = await GeminiDocumentDetector.detectDocument(
          cameraController: _cameraController!,
          documentType: 'license_back');

        if (!mounted || !_isCameraInitialized) return;

        if (licenseInFrame && !_isLicenseDetected) {
          print('✅ Gemini: Driver\'s license back detected in frame - starting 5s countdown!');
          _startCountdown();
        } else if (!licenseInFrame && _isLicenseDetected && !_isCountingDown) {
          print('❌ Gemini: Driver\'s license back moved out of frame - stopping detection');
          _resetDetection();
          _continuousLicenseScan();
        } else if (!_isCountingDown) {
          _continuousLicenseScan();
        }
      }
    });
  }

  void _startCountdown() {
    setState(() {
      _isLicenseDetected = true;
      _countdown = 5;
      _isCountingDown = true;
    });

    // Also update modal immediately
    if (_modalSetState != null) {
      _modalSetState!(() {});
    }

    print('AI: Starting modern countdown from 5...');
    _runCountdownTimer();
  }

  void _runCountdownTimer() {
    if (!mounted || !_isCountingDown) return;

    print(
      '🕐 Modern Countdown: $_countdown seconds remaining - UPDATING MODAL!');

    // Check if countdown finished
    if (_countdown <= 0) {
      print('📸 Gemini: Countdown finished - taking back photo!');
      _autoCapture();
      return;
    }

    // Continue countdown after 1 second with modal state update
    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted && _isCountingDown) {
        // Gemini re-check: verify document is still in frame every 2 seconds
        if (_countdown % 2 == 0 && _cameraController != null && _isCameraInitialized) {
          print('🔍 Gemini: Re-checking license back still in frame...');
          final bool stillInFrame = await GeminiDocumentDetector.detectDocument(
            cameraController: _cameraController!,
            documentType: 'license_back');

          if (!mounted || !_isCountingDown) return;

          if (!stillInFrame) {
            print('❌ Gemini: License back moved during countdown - canceling!');
            _resetDetection();
            _continuousLicenseScan();
            return;
          }
        }

        if (!mounted || !_isCountingDown) return;

        setState(() {
          _countdown = _countdown - 1;
        });

        // CRITICAL: Also update modal state if it exists
        if (_modalSetState != null) {
          _modalSetState!(() {
            // This triggers modal rebuild with new countdown value
          });
        }

        // Add vibration effect for last 3 seconds
        if (_countdown <= 3) {
          print('⚡ Final countdown VISIBLE: $_countdown');
        }

        _runCountdownTimer(); // Recursively call for next second
      }
    });
  }

  // Reset detection state
  void _resetDetection() {
    setState(() {
      _isLicenseDetected = false;
      _countdown = 0;
      _isCountingDown = false;
    });

    // Also update modal
    if (_modalSetState != null) {
      _modalSetState!(() {});
    }
  }

  Future<void> _autoCapture() async {
    try {
      if (_cameraController != null && _isCameraInitialized) {
        print('AI: Taking full license back camera photo...');

        // EXTRA SICHERHEIT: Flash nochmal deaktivieren vor Foto
        await _cameraController!.setFlashMode(FlashMode.off);
        print('Flash confirmed OFF before taking photo');

        // Auto-capture with AI detection
        final XFile photo = await _cameraController!.takePicture();

        print('AI: Analyzing and cropping to license back area only...');
        // Crop the photo to ONLY the license back area (the rectangle)
        final File? croppedFile = await _cropImageToLicenseBackArea(
          File(photo.path));

        if (croppedFile != null) {
          HapticFeedback.heavyImpact();

          // Show capture success animation in camera modal
          _showCaptureSuccess = true;
          _modalSetState?.call(() {});

          // Let the user see the success animation
          await Future.delayed(const Duration(milliseconds: 1100));
          if (!mounted) return;

          setState(() {
            _licenseBackImage = croppedFile;
          });
          _resetDetection();
          _showCaptureSuccess = false;
          _modalSetState = null;

          Navigator.pop(context); // Close bottom sheet

          // Upload image to server and get URL
          print('📤 Uploading license back image to server...');
          final String? uploadedUrl = await _uploadImageToServer(
            croppedFile,
            'license_back');

          if (uploadedUrl != null) {
            setState(() {
              _licenseBackImageUrl = uploadedUrl;
            });

            // Show success notification
            TopNotification.show(
              context,
              message: AppLocalizations.of(context)?.driverLicenseBackUploaded ?? 'Driver\'s license back uploaded successfully!',
              type: NotificationType.success);

            // Save license back image data with URL
            widget.initialData.addAll({
              'licenseBackImagePath': _licenseBackImage?.path,
              'licenseBackImageUrl': uploadedUrl, // Server URL for verification
            });

            print('✅ Step 6: License back uploaded and saved');
            print('🌐 Image URL: $uploadedUrl');
          } else {
            // Upload failed
            TopNotification.show(
              context,
              message: AppLocalizations.of(context)?.failedToUploadLicenseBack ?? 'Failed to upload license back. Please try again.',
              type: NotificationType.error);

            // Clear the image so user can retry
            setState(() {
              _licenseBackImage = null;
            });
          }
        } else {
          // If cropping failed, don't save anything
          print('AI: Cropping failed, retrying detection...');
          _resetDetection();

          TopNotification.show(
            context,
            message: AppLocalizations.of(context)?.failedToProcessLicenseBackArea ?? 'Failed to process license back area. Please try again.',
            type: NotificationType.error);

          // Restart detection
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _continuousLicenseScan();
            }
          });
        }
      }
    } catch (e) {
      print('Error in auto-capture: $e');
      _resetDetection(); // Reset on error

      TopNotification.show(
        context,
        message: AppLocalizations.of(context)?.errorCapturingLicenseBack ?? 'Error capturing license back. Please try again.',
        type: NotificationType.error);

      // Restart detection cycle after error
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _continuousLicenseScan();
        }
      });
    }
  }

  Future<void> _pickImage(String type) async {
    print('Starting camera selection for license back side');
    _showCameraBottomSheet(type);
  }

  Future<File?> _cropImageToLicenseBackArea(File imageFile) async {
    try {
      print(
        'AI: Starting to crop license back image to rectangle area only...');

      // Read the image
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image != null) {
        print('AI: Loaded license back image ${image.width}x${image.height}');

        // Calculate EXACT license back frame dimensions matching our overlay painter
        // This ensures we crop exactly what's shown in the red/green rectangle
        final imageWidth = image.width;
        final imageHeight = image.height;

        // Match the overlay painter calculation exactly
        final frameWidth = (imageWidth * 0.75).round(); // 75% of image width
        final frameHeight = (frameWidth * 0.63)
            .round(); // License aspect ratio 1.6:1
        final frameLeft = ((imageWidth - frameWidth) / 2).round(); // Centered
        final frameTop = ((imageHeight - frameHeight) / 2).round(); // Centered

        // Ensure crop area is within image bounds (safety check)
        final cropLeft = frameLeft.clamp(0, imageWidth - frameWidth);
        final cropTop = frameTop.clamp(0, imageHeight - frameHeight);
        final cropWidth = frameWidth.clamp(
          10,
          imageWidth - cropLeft); // Minimum 10px
        final cropHeight = frameHeight.clamp(
          10,
          imageHeight - cropTop); // Minimum 10px

        print('AI: License back rectangle area calculated:');
        print('  - Frame: ${frameWidth}x$frameHeight');
        print('  - Position: ($cropLeft, $cropTop)');
        print('  - Final crop: ${cropWidth}x$cropHeight');

        // Crop ONLY the rectangle area - this is what the user sees in the frame
        final croppedImage = img.copyCrop(
          image,
          x: cropLeft,
          y: cropTop,
          width: cropWidth,
          height: cropHeight);

        print(
          'AI: Successfully cropped license back to rectangle. New size: ${croppedImage.width}x${croppedImage.height}');

        // Save the cropped rectangle as the final license back image
        final tempDir = await getTemporaryDirectory();
        final croppedPath = path.join(
          tempDir.path,
          'license_back_rectangle_${DateTime.now().millisecondsSinceEpoch}.jpg');

        final croppedFile = File(croppedPath);
        await croppedFile.writeAsBytes(
          img.encodeJpg(croppedImage, quality: 90)); // High quality for license

        print('AI: License back rectangle saved successfully to: $croppedPath');
        return croppedFile;
      } else {
        print('AI: Failed to decode license back image');
      }
    } catch (e) {
      print('AI: Error cropping to license back rectangle area: $e');
    }

    return null;
  }

  // Handle next button press
  void _handleNext() {
    print('📷 ========================================');
    print('📷 Step 6: CONTINUE BUTTON CLICKED!');
    print('📷 ========================================');
    print('📷 License back image exists: ${_licenseBackImage != null}');
    print('📷 License back image path: ${_licenseBackImage?.path}');
    print('📷 License back image URL: $_licenseBackImageUrl');

    if (_licenseBackImage != null) {
      print('📷 Saving license back data to initialData...');

      // Save license back image data with both path and URL
      widget.initialData.addAll({
        'licenseBackImagePath': _licenseBackImage?.path,
        'licenseBackImageUrl':
            _licenseBackImageUrl, // Include URL for backend verification
      });

      print('✅ Data saved successfully');
      print('📷 ========================================');
      print('📷 🎯 CALLING widget.onNext() to go to Step 7!');
      print('📷 widget.onNext reference: ${widget.onNext}');
      print('📷 ========================================');

      widget.onNext();

      print('📷 ========================================');
      print('📷 ✅ widget.onNext() CALLED - Should navigate to Step 7 now');
      print('📷 ========================================');
    } else {
      print('📷 ❌ VALIDATION FAILED: No license back image captured');
      TopNotification.show(
        context,
        message: AppLocalizations.of(context)?.pleaseCaptureDriverLicenseBack ?? 'Please capture the back of your driver\'s license',
        type: NotificationType.error);
    }
  }
  void _showCameraBottomSheet(String type) {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    _resetDetection();

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: true,
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          _modalSetState = setModalState;

          if (!_isCameraInitialized && !_isInitializingCamera) {
            Future.microtask(() async {
              await _initializeCamera();
              if (mounted && _modalSetState != null) {
                _modalSetState!(() {});
              }
              if (_isCameraInitialized) {
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  _startRealisticLicenseDetection();
                }
              }
            });
          }

          // ── Capture success ──
          if (_showCaptureSuccess) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.82,
              child: Column(
                children: [
                  const DragHandle(),
                  const Spacer(flex: 3),
                  // Gradient checkmark — spring scale
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF34C759), Color(0xFF30D158)]),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFF34C759).withOpacity(0.3),
                                blurRadius: 28,
                                spreadRadius: 6),
                            ]),
                          child: Icon(
                            CupertinoIcons.checkmark,
                            color: Colors.white,
                            size: 52)));
                    }),
                  SizedBox(height: 28),
                  // Title — slide up + fade
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (context, v, child) {
                      return Transform.translate(
                        offset: Offset(0, 14 * (1 - v)),
                        child: Opacity(opacity: v, child: child));
                    },
                    child: Text(
                      AppLocalizations.of(context)?.photoCaptured ??
                          'Photo Captured',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.5))),
                  SizedBox(height: 14),
                  // Processing row — fade in
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    builder: (context, v, child) {
                      return Opacity(opacity: v, child: child);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoActivityIndicator(
                          radius: 8,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.3)),
                        SizedBox(width: 10),
                        Text(
                          AppLocalizations.of(context)?.processingEllipsis ?? 'Processing...',
                          style: TextStyle(
                            fontSize: 15,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4),
                            letterSpacing: -0.2)),
                      ])),
                  const Spacer(flex: 4),
                ]));
          }

          // ── Camera scanner view ──
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                const DragHandle(),
                // Header
                Text(
                  AppLocalizations.of(context)?.positionYourLicenseBackSide ?? 'License — Back Side',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
                SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)?.aiCapturesAutomatically ?? 'AI captures automatically when ready',
                  style: TextStyle(
                    fontSize: 14,
                    color: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.4))),

                SizedBox(height: 16),

                // Camera area
                Expanded(
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        children: [
                          // Camera preview / placeholder
                          Positioned.fill(
                            child: _isCameraInitialized &&
                                    _cameraController != null
                                ? FittedBox(
                                    fit: BoxFit.cover,
                                    child: SizedBox(
                                      width: _cameraController!
                                              .value
                                              .previewSize
                                              ?.height ??
                                          1,
                                      height: _cameraController!
                                              .value
                                              .previewSize
                                              ?.width ??
                                          1,
                                      child: CameraPreview(
                                          _cameraController!)))
                                : Center(
                                    child: _cameraError.isNotEmpty
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                CupertinoIcons.camera_fill,
                                                size: 36,
                                                color: Colors.white
                                                    .withOpacity(0.3)),
                                              SizedBox(height: 16),
                                              Padding(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 32),
                                                child: Text(
                                                  _cameraError,
                                                  textAlign:
                                                      TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.5),
                                                    fontSize: 14))),
                                              SizedBox(height: 16),
                                              TradeRepublicButton(
                                                label: AppLocalizations.of(
                                                            context)
                                                        ?.retry ??
                                                    'Retry',
                                                height: 40,
                                                width: 120,
                                                showShadow: false,
                                                backgroundColor: Colors.white
                                                    .withOpacity(0.15),
                                                foregroundColor: Colors.white,
                                                onPressed: _initializeCamera),
                                            ])
                                        : const CupertinoActivityIndicator(
                                            radius: 14,
                                            color: Colors.white))),

                          // Corner brackets scanner overlay
                          CustomPaint(
                            size: Size.infinite,
                            painter: ScannerCornersPainter(
                              bracketColor: _isLicenseDetected
                                  ? const Color(0xFF34C759)
                                  : Colors.white.withOpacity(0.45),
                              isDetected: _isLicenseDetected)),

                          // Status pill
                          Positioned(
                            top: 20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _isLicenseDetected
                                      ? const Color(0xFF34C759)
                                          .withOpacity(0.9)
                                      : Colors.black.withOpacity(0.55),
                                  borderRadius:
                                      BorderRadius.circular(20)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _isLicenseDetected
                                            ? Colors.white
                                            : Colors.white
                                                .withOpacity(0.5),
                                        shape: BoxShape.circle)),
                                    SizedBox(width: 8),
                                    Text(
                                      _isCountingDown
                                          ? '${AppLocalizations.of(context)?.capturingInCountdown ?? 'Capturing in'} $_countdown...'
                                          : _isLicenseDetected
                                              ? AppLocalizations.of(context)?.licenseDetected ?? 'License Detected'
                                              : AppLocalizations.of(context)?.scanningEllipsis ?? 'Scanning...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2)),
                                  ])))),

                          // Countdown ring
                          if (_isCountingDown)
                            Positioned.fill(
                              child: Center(
                                child: Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withOpacity(0.65),
                                    shape: BoxShape.circle),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 84,
                                        height: 84,
                                        child:
                                            TweenAnimationBuilder<
                                                double>(
                                          tween: Tween(
                                              begin: 1.0, end: 0.0),
                                          duration:
                                              const Duration(
                                                  seconds: 5),
                                          builder:
                                              (context, value, _) {
                                            return CircularProgressIndicator(
                                              value: value,
                                              strokeWidth: 3,
                                              color: const Color(
                                                  0xFF34C759),
                                              backgroundColor: Colors
                                                  .white
                                                  .withOpacity(0.08),
                                              strokeCap:
                                                  StrokeCap.round);
                                          })),
                                      Text(
                                        '$_countdown',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 38,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: -1)),
                                    ])))),
                        ])))),

                SizedBox(height: 16),

                // Cancel button
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      MediaQuery.of(context).padding.bottom + 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.cancel ?? 'Cancel',
                      height: 50,
                      width: double.infinity,
                      isSecondary: true,
                      showShadow: false,
                      onPressed: () {
                        _resetDetection();
                        _modalSetState = null;
                        Navigator.pop(context);
                      }))),
              ]));
        }));
  }


  @override
  void dispose() {
    _fadeController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final bool isLight = appSettings.isLightMode(context);

    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + 20,
            24,
            MediaQuery.of(context).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(isLight),

              SizedBox(height: 40),

              // License back upload section
              _buildLicenseBackUploadSection(isLight),

              SizedBox(height: 40),

              // Navigation Buttons
              Row(
                children: [
                  // Back Button
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: TradeRepublicButton.icon(
                      icon: Icon(CupertinoIcons.chevron_back, size: 18),
                      onPressed: widget.onBack)),

                  SizedBox(width: 12),

                  // Continue Button - Full Width with Gradient
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: TradeRepublicButton(
                        label: _licenseBackImage != null
                            ? AppLocalizations.of(context)?.continueToVerification ?? 'Continue to Verification'
                            : AppLocalizations.of(context)?.uploadRequired ?? 'Upload Required',
                        icon: _licenseBackImage != null
                            ? Icon(CupertinoIcons.arrow_right, size: 18)
                            : null,
                        onPressed: _licenseBackImage != null
                            ? _handleNext
                            : null))),
                ]),
            ]))))));
  }

  Widget _buildHeader(bool isLight) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isLight ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(20)),
            child: Icon(
              CupertinoIcons.person_badge_plus,
              color: isLight ? Colors.white : Colors.black,
              size: 40)),
          SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)?.licenseBackSide ?? 'License Back Side',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(
            '${AppLocalizations.of(context)?.stepXofY ?? 'Step'} 5 ${AppLocalizations.of(context)?.ofLabel ?? 'of'} 10 - ${AppLocalizations.of(context)?.licenseBackLabel ?? 'License Back'}',
            style: TextStyle(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              fontSize: 16)),
        ]));
  }

  Widget _buildLicenseBackUploadSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            AppLocalizations.of(context)?.captureDriversLicenseBack ?? "Capture Back of Your Driver's License",
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700))),

        // Back of License
        _buildPhotoCapture(
          title: AppLocalizations.of(context)?.backOfDriversLicense ?? 'Back of Driver\'s License',
          subtitle: AppLocalizations.of(context)?.includeBarcodeEndorsements ?? 'Include barcode, endorsements and restrictions',
          image: _licenseBackImage,
          onTap: () => _pickImage('back'),
          isLight: isLight),
      ]);
  }

  Widget _buildPhotoCapture({
    required String title,
    required String subtitle,
    required File? image,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(20)),
        child: image != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Image.file(
                      image,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20)),
                        child: Icon(
                          CupertinoIcons.checkmark,
                          color: Colors.white,
                          size: 16))),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          AppLocalizations.of(context)?.tapToRetakePhoto ?? 'Tap to retake photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center))),
                  ]))
            : Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20)),
                      child: Icon(
                        CupertinoIcons.camera,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.6),
                        size: 24)),
                    SizedBox(height: 8),
                    Text(
                      title,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.6),
                        fontSize: 12)),
                    SizedBox(height: 8),
                    UnconstrainedBox(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.takePhoto ?? 'Take Photo',
                        onPressed: onTap)),
                  ]))));
  }
}

// Modern scanner overlay — Apple-style corner brackets
class ScannerCornersPainter extends CustomPainter {
  final Color bracketColor;
  final bool isDetected;

  ScannerCornersPainter({
    required this.bracketColor,
    this.isDetected = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Frame dimensions — must match crop calculations
    final frameWidth = size.width * 0.75;
    final frameHeight = frameWidth * 0.63;
    final frameLeft = (size.width - frameWidth) / 2;
    final frameTop = (size.height - frameHeight) / 2;
    final r = Rect.fromLTWH(frameLeft, frameTop, frameWidth, frameHeight);
    const radius = 16.0;

    // Dark overlay with rounded-rect cutout
    final cutout = RRect.fromRectAndRadius(r, const Radius.circular(radius));
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(cutout)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, Paint()..color = Colors.black.withOpacity(0.5));

    // Corner brackets
    final paint = Paint()
      ..color = bracketColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const cl = 30.0; // bracket arm length
    final corners = Path();

    // Top-left
    corners.moveTo(r.left, r.top + cl);
    corners.lineTo(r.left, r.top + radius);
    corners.quadraticBezierTo(r.left, r.top, r.left + radius, r.top);
    corners.lineTo(r.left + cl, r.top);
    // Top-right
    corners.moveTo(r.right - cl, r.top);
    corners.lineTo(r.right - radius, r.top);
    corners.quadraticBezierTo(r.right, r.top, r.right, r.top + radius);
    corners.lineTo(r.right, r.top + cl);
    // Bottom-left
    corners.moveTo(r.left, r.bottom - cl);
    corners.lineTo(r.left, r.bottom - radius);
    corners.quadraticBezierTo(r.left, r.bottom, r.left + radius, r.bottom);
    corners.lineTo(r.left + cl, r.bottom);
    // Bottom-right
    corners.moveTo(r.right - cl, r.bottom);
    corners.lineTo(r.right - radius, r.bottom);
    corners.quadraticBezierTo(r.right, r.bottom, r.right, r.bottom - radius);
    corners.lineTo(r.right, r.bottom - cl);

    canvas.drawPath(corners, paint);

    // Subtle glow when detected
    if (isDetected) {
      final glow = Paint()
        ..color = bracketColor.withOpacity(0.12)
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(corners, glow);
    }
  }

  @override
  bool shouldRepaint(covariant ScannerCornersPainter old) =>
      old.bracketColor != bracketColor || old.isDetected != isDetected;
}
