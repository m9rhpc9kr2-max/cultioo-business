import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/services/gemini_document_detector.dart';
import 'driver_selfie_analysis_page.dart';
import '../../../shared/widgets/trade_republic_tap.dart';

/// Step 6: Face Verification
/// 
/// Takes a selfie and uses Gemini AI to:
/// 1. Verify liveness (real person, not a photo)
/// 2. Compare face with ID document photo from Step 2
class DriverStep6FaceVerification extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const DriverStep6FaceVerification({
    super.key,
    required this.initialData,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<DriverStep6FaceVerification> createState() =>
      _DriverStep6FaceVerificationState();
}

class _DriverStep6FaceVerificationState
    extends State<DriverStep6FaceVerification> with TickerProviderStateMixin {
  // Selfie image
  File? _selfieImage;

  // Camera
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  List<CameraDescription> _cameras = [];
  String _cameraError = '';
  bool _isInitializingCamera = false;

  // Face detection state
  bool _isFaceDetected = false;
  bool _isCountingDown = false;
  int _countdown = 0;
  bool _showCaptureSuccess = false;

  // Modal state setter
  StateSetter? _modalSetState;
  bool _isModalActive = false;

  /// Safe wrapper — only calls _modalSetState when the sheet is still alive
  void _updateModal(VoidCallback fn) {
    if (_isModalActive && _modalSetState != null) {
      _modalSetState!(() => fn());
    }
  }

  // Animations
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;
  bool _animationsInitialized = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();
    _rotationAnimation = Tween<double>(begin: 0.0, end: 2 * pi).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
    _animationsInitialized = true;
  }

  /// Initialize front camera for selfie
  /// Camera permission was already granted in steps 2-5,
  /// so we just initialize directly like the other steps.
  Future<void> _initializeFrontCamera() async {
    if (_isInitializingCamera || _isCameraInitialized) return;

    try {
      if (mounted) {
        setState(() {
          _isInitializingCamera = true;
          _cameraError = '';
        });
      }

      // Get available cameras with timeout
      try {
        _cameras = await availableCameras().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception('Camera discovery timeout');
          },
        );
      } catch (e) {
        print('❌ Failed to get cameras: $e');
        if (mounted) {
          setState(() {
            _cameraError = AppLocalizations.of(context)?.couldNotAccessCamera ?? AppLocalizations.of(context)!.tr('Could not access camera. Please check permissions.');
            _isInitializingCamera = false;
          });
          _updateModal(() {});
        }
        return;
      }

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = AppLocalizations.of(context)?.noCamerasFound ?? AppLocalizations.of(context)!.tr('No cameras found on this device');
            _isInitializingCamera = false;
          });
          _updateModal(() {});
        }
        return;
      }

      // Find front camera
      CameraDescription? frontCamera;
      for (final camera in _cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }
      frontCamera ??= _cameras.first;

      try {
        await _cameraController?.dispose();
      } catch (_) {}

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      // Initialize with timeout
      await _cameraController!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Camera initialization timeout');
        },
      );

      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _isInitializingCamera = false;
        });

        _updateModal(() {});
      }
    } catch (e) {
      print('❌ Camera error: $e');
      if (mounted) {
        setState(() {
          _cameraError = AppLocalizations.of(context)?.couldNotAccessCamera ??
              AppLocalizations.of(context)?.cameraInitFailed ?? AppLocalizations.of(context)!.tr('Camera initialization failed. Please try again.');
          _isInitializingCamera = false;
        });
        _updateModal(() {});
      }
    }
  }

  /// Take selfie photo — flips the image horizontally so it's not mirrored
  Future<void> _takeSelfie() async {
    if (_cameraController == null || !_isCameraInitialized) return;

    try {
      HapticFeedback.heavyImpact();
      final XFile photo = await _cameraController!.takePicture();

      // Show success flash
      _showCaptureSuccess = true;
      _updateModal(() {});
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // Flip the image horizontally (front camera saves mirrored)
      final File flippedFile = await _flipImageHorizontally(File(photo.path));

      // 1. Stop showing the camera preview BEFORE disposing
      _isCameraInitialized = false;
      _updateModal(() {});

      // 2. Dispose camera before closing sheet
      await _cameraController?.dispose();
      _cameraController = null;
      _isInitializingCamera = false;

      // 3. Close the bottom sheet — null out FIRST to prevent further calls
      _isModalActive = false;
      _showCaptureSuccess = false;
      _modalSetState = null;
      if (mounted) Navigator.pop(context);

      // 4. Update parent state & navigate
      setState(() {
        _selfieImage = flippedFile;
      });
      _navigateToAnalysis(flippedFile);
    } catch (e) {
      print('❌ Selfie capture error: $e');
      _showCaptureSuccess = false;
      _resetFaceDetection();
      if (mounted) {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.failedToCaptureSelfie ?? AppLocalizations.of(context)!.tr('Failed to capture selfie. Please try again.'),
          type: NotificationType.error,
        );
      }
    }
  }

  /// Flip image horizontally so front-camera selfie looks natural
  Future<File> _flipImageHorizontally(File original) async {
    try {
      final bytes = await original.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return original;

      final flipped = img.flipHorizontal(decoded);
      final encoded = img.encodeJpg(flipped, quality: 92);

      final flippedPath = original.path.replaceAll('.jpg', '_flipped.jpg');
      final flippedFile = File(flippedPath);
      await flippedFile.writeAsBytes(encoded);

      // Clean up original
      try { await original.delete(); } catch (_) {}

      return flippedFile;
    } catch (e) {
      print('⚠️ Image flip failed, using original: $e');
      return original;
    }
  }

  /// Start continuous Gemini face scanning
  void _startFaceScan() {
    _continuousFaceScan();
  }

  void _continuousFaceScan() {
    if (!mounted || !_isCameraInitialized || !_isModalActive) return;

    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted || !_isCameraInitialized || _isCountingDown || _cameraController == null || !_isModalActive) return;

      print('🔍 Gemini: Scanning for face...');
      final bool faceInFrame = await GeminiDocumentDetector.detectFace(
        cameraController: _cameraController!,
      );

      if (!mounted || !_isCameraInitialized || !_isModalActive) return;

      if (faceInFrame && !_isFaceDetected) {
        print('✅ Gemini: Face detected — starting countdown!');
        _startFaceCountdown();
      } else if (!faceInFrame && _isFaceDetected && !_isCountingDown) {
        print('❌ Gemini: Face lost');
        _resetFaceDetection();
        _continuousFaceScan();
      } else if (!_isCountingDown) {
        _continuousFaceScan();
      }
    });
  }

  void _startFaceCountdown() {
    setState(() {
      _isFaceDetected = true;
      _countdown = 3;
      _isCountingDown = true;
    });
    _updateModal(() {});

    HapticFeedback.lightImpact();
    print('📸 Face countdown: 3...');
    _runFaceCountdown();
  }

  void _runFaceCountdown() {
    if (!mounted || !_isCountingDown || !_isModalActive) return;

    if (_countdown <= 0) {
      print('📸 Gemini: Countdown done — auto-capture!');
      _takeSelfie();
      return;
    }

    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted || !_isCountingDown || !_isModalActive) return;

      // Gemini re-check at countdown == 2
      if (_countdown == 2 && _cameraController != null && _isCameraInitialized) {
        print('🔍 Gemini: Re-checking face still in frame...');
        final bool stillThere = await GeminiDocumentDetector.detectFace(
          cameraController: _cameraController!,
        );

        if (!mounted || !_isCountingDown || !_isModalActive) return;

        if (!stillThere) {
          print('❌ Gemini: Face moved during countdown — canceling!');
          _resetFaceDetection();
          _continuousFaceScan();
          return;
        }
      }

      if (!mounted || !_isCountingDown || !_isModalActive) return;

      HapticFeedback.selectionClick();
      setState(() {
        _countdown = _countdown - 1;
      });
      _updateModal(() {});

      print('📸 Face countdown: $_countdown...');
      _runFaceCountdown();
    });
  }

  void _resetFaceDetection() {
    if (mounted) {
      setState(() {
        _isFaceDetected = false;
        _countdown = 0;
        _isCountingDown = false;
      });
    }
    _updateModal(() {});
  }

  /// Navigate to the full-screen analysis page that runs AI verification
  Future<void> _navigateToAnalysis(File selfieFile) async {
    final result = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (_) => DriverSelfieAnalysisPage(
          selfieImage: selfieFile,
          frontImageUrl: widget.initialData['frontImageUrl'],
          backImageUrl: widget.initialData['backImageUrl'],
          expectedFirstName: widget.initialData['firstName'],
          expectedLastName: widget.initialData['lastName'],
          expectedDob: widget.initialData['birthdate'],
        ),
      ),
    );

    if (!mounted) return;

    if (result == true) {
      // Verification passed → proceed to next step
      widget.initialData['selfieImagePath'] = selfieFile.path;
      widget.initialData['faceVerified'] = true;
      widget.onNext();
    } else {
      // Failed or dismissed → reset for retry
      setState(() {
        _selfieImage = null;
      });
    }
  }

  /// Show selfie camera bottom sheet
  void _showSelfieCamera() {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);

    // Dispose previous camera & reset state
    _cameraController?.dispose();
    _cameraController = null;
    _isCameraInitialized = false;
    _isInitializingCamera = false;
    _isModalActive = false;
    _resetFaceDetection();
    _showCaptureSuccess = false;

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          _modalSetState = setModalState;
          _isModalActive = true;

          // Start camera initialization
          if (!_isCameraInitialized && !_isInitializingCamera) {
            Future.microtask(() async {
              await _initializeFrontCamera();
              if (mounted && _modalSetState != null) {
                _modalSetState!(() {});
                // Start Gemini face scanning
                _startFaceScan();
              }
            });
          }

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                const DragHandle(),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          CupertinoIcons.person_crop_circle,
                          size: 20,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)?.takeASelfie ?? AppLocalizations.of(context)!.tr('Take a Selfie'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    AppLocalizations.of(context)?.lookDirectlyAtCamera ?? AppLocalizations.of(context)!.tr('Look directly at the camera. Make sure your face is well lit.'),
                    style: TextStyle(
                      fontSize: 14,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Camera preview
                Expanded(
                  child: _isCameraInitialized
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Camera preview — FittedBox cover keeps aspect ratio
                              FittedBox(
                                fit: BoxFit.cover,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox(
                                  width: _cameraController!.value.previewSize!.height,
                                  height: _cameraController!.value.previewSize!.width,
                                  child: Transform.flip(
                                    flipX: true,
                                    child: CameraPreview(_cameraController!),
                                  ),
                                ),
                              ),

                              // Soft vignette
                              Container(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.3),
                                    ],
                                    radius: 0.85,
                                  ),
                                ),
                              ),

                              // Modern animated face oval (CustomPainter)
                              if (_animationsInitialized)
                              AnimatedBuilder(
                                animation: Listenable.merge(
                                  [_rotationAnimation, _rippleAnimation],
                                ),
                                builder: (context, child) => CustomPaint(
                                  size: Size.infinite,
                                  painter: _FaceOvalPainter(
                                    rotation: _rotationAnimation.value,
                                    ripple: (_isFaceDetected && !_showCaptureSuccess)
                                        ? _rippleAnimation.value
                                        : 0.0,
                                    faceDetected: _isFaceDetected,
                                    showSuccess: _showCaptureSuccess,
                                  ),
                                ),
                              ),

                              // Countdown — big glowing floating number
                              if (_isCountingDown && _countdown > 0)
                                Center(
                                  child: TweenAnimationBuilder<double>(
                                    key: ValueKey(_countdown),
                                    tween: Tween(begin: 1.6, end: 1.0),
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.elasticOut,
                                    builder: (context, scale, child) {
                                      return Transform.scale(
                                        scale: scale,
                                        child: Text(
                                          '$_countdown',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 90,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -4,
                                            shadows: [
                                              Shadow(
                                                color: Colors.greenAccent
                                                    .withOpacity(0.9),
                                                blurRadius: 32,
                                              ),
                                              Shadow(
                                                color: Colors.greenAccent
                                                    .withOpacity(0.4),
                                                blurRadius: 64,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                              // Capture success flash
                              if (_showCaptureSuccess)
                                AnimatedOpacity(
                                  opacity: _showCaptureSuccess ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    color: Colors.white,
                                    child: Center(
                                      child: Icon(
                                        CupertinoIcons.checkmark_circle_fill,
                                        size: 64,
                                        color: Colors.greenAccent.shade700,
                                      ),
                                    ),
                                  ),
                                ),

                              // Status pill at bottom
                              Positioned(
                                bottom: 20,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Container(
                                      key: ValueKey(_isFaceDetected ? 'detected' : 'scanning'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _isFaceDetected
                                            ? Colors.greenAccent.shade700.withOpacity(0.85)
                                            : Colors.black.withOpacity(0.55),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: _isFaceDetected
                                              ? Colors.greenAccent.withOpacity(0.3)
                                              : Colors.white.withOpacity(0.1),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isFaceDetected
                                                ? CupertinoIcons.checkmark_shield
                                                : CupertinoIcons.viewfinder,
                                            color: Colors.white.withOpacity(0.9),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _isFaceDetected
                                                ? (AppLocalizations.of(context)?.faceDetectedHoldStill ?? AppLocalizations.of(context)!.tr('Face detected — hold still'))
                                                : (AppLocalizations.of(context)?.positionYourFace ?? AppLocalizations.of(context)!.tr('Position your face in the oval')),
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.95),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CultiooLoadingIndicator(size: 40),
                              const SizedBox(height: 16),
                              Text(
                                _cameraError.isNotEmpty
                                    ? _cameraError
                                    : AppLocalizations.of(context)
                                            ?.initializingCamera ?? AppLocalizations.of(context)!.tr('Initializing Camera...'),
                                style: TextStyle(
                                  color:
                                      (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      // Null out modal refs FIRST — prevents any pending async from calling setState on disposed widget
      _isModalActive = false;
      _modalSetState = null;
      _cameraController?.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
      _isInitializingCamera = false;
      _resetFaceDetection();
      _showCaptureSuccess = false;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    _rippleController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);
    final loc = AppLocalizations.of(context);

    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              primary: false,
              padding: EdgeInsets.fromLTRB(
                24,
                MediaQuery.of(context).padding.top + 20,
                24,
                MediaQuery.of(context).padding.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader(isLight, loc),

                  const SizedBox(height: 40),

                  // Selfie section
                  _buildSelfieSection(isLight, loc),

                  const SizedBox(height: 40),

                  // Navigation buttons
                  Row(
                    children: [
                      // Back button
                      SizedBox(
                        height: 52,
                        width: 52,
                        child: TradeRepublicButton.icon(
                          icon: const Icon(CupertinoIcons.chevron_back,
                              size: 18),
                          onPressed: widget.onBack,
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Take Selfie button
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: TradeRepublicButton(
                            label: loc?.takeASelfie ?? AppLocalizations.of(context)!.tr('Take a Selfie'),
                            icon: const Icon(CupertinoIcons.camera, size: 18),
                            onPressed: _showSelfieCamera,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isLight, AppLocalizations? loc) {
    return Center(
      child: Column(
        children: [
          // Animated face icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    CupertinoIcons.person_crop_circle_badge_checkmark,
                    color: isLight ? Colors.white : Colors.black,
                    size: 40,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            loc?.identityVerification ?? AppLocalizations.of(context)!.tr('Identity Verification'),
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${AppLocalizations.of(context)?.stepXofY ?? AppLocalizations.of(context)!.tr('Step')} 6 ${AppLocalizations.of(context)?.ofLabel ?? AppLocalizations.of(context)!.tr('of')} 10 — ${AppLocalizations.of(context)?.aiVerificationLabel ?? AppLocalizations.of(context)!.tr('AI Verification')}',
            style: TextStyle(
              color:
                  (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            loc?.weVerifyYourIdentity ?? AppLocalizations.of(context)!.tr('We use AI to verify your identity matches your documents.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfieSection(bool isLight, AppLocalizations? loc) {
    return Column(
      children: [
        // Selfie preview area
        TradeRepublicTap(
          onTap: _showSelfieCamera,
          child: Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                width: 1.5,
              ),
            ),
            child: _selfieImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(27),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Show the taken selfie (normal orientation)
                        Image.file(
                          _selfieImage!,
                          fit: BoxFit.cover,
                        ),
                        // Retake overlay
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.camera_rotate,
                                  color: Colors.white.withOpacity(0.9),
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  loc?.retake ?? AppLocalizations.of(context)!.tr('Retake'),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated face silhouette
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 80,
                              height: 100,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.15),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Icon(
                                CupertinoIcons.person_fill,
                                size: 40,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.15),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        loc?.takeASelfie ?? AppLocalizations.of(context)!.tr('Take a Selfie'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          loc?.selfieInstructions ?? AppLocalizations.of(context)!.tr('Tap to open the camera and take a clear selfie for face matching'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.45),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Modern face-scan oval painter
// ─────────────────────────────────────────────────────────────

class _FaceOvalPainter extends CustomPainter {
  final double rotation;
  final double ripple;
  final bool faceDetected;
  final bool showSuccess;

  const _FaceOvalPainter({
    required this.rotation,
    required this.ripple,
    required this.faceDetected,
    required this.showSuccess,
  });

  static const double _ovalW = 200;
  static const double _ovalH = 264;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final ovalRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: _ovalW,
      height: _ovalH,
    );

    // ── 1. Dark vignette mask with oval cutout ──────────────────
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color =
            Colors.black.withOpacity(faceDetected || showSuccess ? 0.38 : 0.52),
    );
    // Punch a transparent oval hole through the mask
    canvas.drawOval(ovalRect.inflate(1), Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    // ── 2. Success state ───────────────────────────────────────
    if (showSuccess) {
      final glow = Paint()
        ..color = Colors.greenAccent.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawOval(ovalRect, glow);
      final solid = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawOval(ovalRect, solid);
      _drawCornerBrackets(canvas, ovalRect, Colors.greenAccent);
      return;
    }

    // ── 3. Face detected: glowing oval + ripple rings ──────────
    if (faceDetected) {
      for (int i = 0; i < 3; i++) {
        final delay = i / 3.0;
        final t = ((ripple - delay) * 1.5).clamp(0.0, 1.0);
        if (t > 0) {
          canvas.drawOval(
            ovalRect.inflate(t * 40),
            Paint()
              ..color = Colors.greenAccent.withOpacity((1 - t) * 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
      // Glow border
      canvas.drawOval(
        ovalRect,
        Paint()
          ..color = Colors.greenAccent.withOpacity(0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawOval(
        ovalRect,
        Paint()
          ..color = Colors.greenAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      _drawCornerBrackets(canvas, ovalRect, Colors.greenAccent);
      return;
    }

    // ── 4. Scanning: dashed oval + dual rotating arcs ──────────
    _drawDashedOval(
        canvas, ovalRect, Colors.white.withOpacity(0.28), 1.8, 10, 7);

    // Primary sweep arc
    const sweepLen = 1.1; // radians
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: rotation - sweepLen,
        endAngle: rotation,
        colors: [Colors.transparent, Colors.white.withOpacity(0.95)],
        tileMode: TileMode.clamp,
        transform: GradientRotation(rotation - sweepLen),
      ).createShader(ovalRect);
    canvas.drawArc(ovalRect, rotation - sweepLen, sweepLen, false, sweepPaint);

    // Secondary faint arc 180° behind
    final r2 = rotation + pi;
    final sweepPaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: r2 - sweepLen,
        endAngle: r2,
        colors: [Colors.transparent, Colors.white.withOpacity(0.35)],
        tileMode: TileMode.clamp,
        transform: GradientRotation(r2 - sweepLen),
      ).createShader(ovalRect);
    canvas.drawArc(
        ovalRect, r2 - sweepLen, sweepLen, false, sweepPaint2);

    _drawCornerBrackets(canvas, ovalRect, Colors.white.withOpacity(0.6));
  }

  void _drawDashedOval(Canvas canvas, Rect rect, Color color,
      double strokeWidth, double dashLen, double gapLen) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final metric = (Path()..addOval(rect)).computeMetrics().first;
    double d = 0;
    while (d < metric.length) {
      canvas.drawPath(metric.extractPath(d, d + dashLen), paint);
      d += dashLen + gapLen;
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 24.0;
    const crv = 11.0;
    final l = rect.left + 4;
    final t = rect.top + 12;
    final r = rect.right - 4;
    final b = rect.bottom - 12;

    // Top-left
    canvas.drawLine(Offset(l, t + crv + len), Offset(l, t + crv), paint);
    canvas.drawLine(Offset(l + crv, t), Offset(l + crv + len, t), paint);
    // Top-right
    canvas.drawLine(Offset(r, t + crv), Offset(r, t + crv + len), paint);
    canvas.drawLine(Offset(r - crv, t), Offset(r - crv - len, t), paint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - crv), Offset(l, b - crv - len), paint);
    canvas.drawLine(Offset(l + crv, b), Offset(l + crv + len, b), paint);
    // Bottom-right
    canvas.drawLine(Offset(r, b - crv), Offset(r, b - crv - len), paint);
    canvas.drawLine(Offset(r - crv, b), Offset(r - crv - len, b), paint);
  }

  @override
  bool shouldRepaint(_FaceOvalPainter old) =>
      old.rotation != rotation ||
      old.ripple != ripple ||
      old.faceDetected != faceDetected ||
      old.showSuccess != showSuccess;
}
