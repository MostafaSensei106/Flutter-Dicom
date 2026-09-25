import 'package:flutter/material.dart';
import '../controller/dicom_controller.dart';
import '../shader/dicom_shader_painter.dart';

/// A production-ready, interactive widget for high-performance DICOM rendering.
class DicomViewer extends StatefulWidget {
  const DicomViewer({
    required this.controller,
    super.key,
    this.fit = BoxFit.contain,
  });

  final DicomController controller;
  final BoxFit fit;

  @override
  State<DicomViewer> createState() => _DicomViewerState();
}

class _DicomViewerState extends State<DicomViewer> {
  final TransformationController _transformController = TransformationController();
  Offset? _hoverPosition;
  String? _probeText;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if (scale != _currentScale) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  void _updateProbe(Offset localPosition, BoxConstraints constraints) {
    if (!widget.controller.hasData) return;
    
    final frame = widget.controller.currentFrame!;
    final meta = frame.metadata;
    final width = meta.width;
    final height = meta.height;

    // Convert local tap coordinate to image pixel coordinate.
    // The CustomPaint fills the constraints exactly.
    final double pixelX = (localPosition.dx / constraints.maxWidth) * width;
    final double pixelY = (localPosition.dy / constraints.maxHeight) * height;

    if (pixelX >= 0 && pixelX < width && pixelY >= 0 && pixelY < height) {
      final index = (pixelY.toInt() * width) + pixelX.toInt();
      if (index >= 0 && index < frame.pixelData.length) {
        final rawValue = frame.pixelData[index];
        final double hu = rawValue * meta.rescaleSlope + meta.rescaleIntercept;
        setState(() {
          _hoverPosition = localPosition;
          _probeText = 'HU: ${hu.toStringAsFixed(0)} (raw: $rawValue)\nX: ${pixelX.toInt()}, Y: ${pixelY.toInt()}';
        });
        return;
      }
    }
    setState(() {
      _probeText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (widget.controller.hasError) {
          return Center(
            child: Text(
              widget.controller.errorMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (!widget.controller.hasData) {
          return const Center(child: Text('No DICOM data loaded.'));
        }

        return Stack(
          children: [
            ClipRect(
              child: GestureDetector(
                onPanUpdate: (details) {
                  widget.controller.adjustWindowing(
                    deltaX: details.delta.dx,
                    deltaY: details.delta.dy,
                  );
                },
                onDoubleTap: widget.controller.resetWindowing,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.5,
                  maxScale: 10.0,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return MouseRegion(
                        onHover: (e) => _updateProbe(e.localPosition, constraints),
                        onExit: (_) => setState(() => _probeText = null),
                        child: GestureDetector(
                          onTapDown: (e) => _updateProbe(e.localPosition, constraints),
                          child: AspectRatio(
                            aspectRatio: widget.controller.currentFrame!.metadata.width / 
                                         widget.controller.currentFrame!.metadata.height,
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: CustomPaint(
                                painter: DicomShaderPainter(
                                  frameResult: widget.controller.currentFrame!,
                                  windowCenter: widget.controller.windowCenter!,
                                  windowWidth: widget.controller.windowWidth!,
                                  shader: widget.controller.shader!,
                                  rawTexture: widget.controller.rawTexture!,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                ),
              ),
            ),
            
            // Pixel Probe Overlay
            if (_probeText != null && _hoverPosition != null)
              Positioned(
                left: _hoverPosition!.dx + 15,
                top: _hoverPosition!.dy + 15,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      _probeText!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              
            // Scale Bar Overlay
            LayoutBuilder(
              builder: (context, constraints) {
                return Positioned(
                  bottom: 16,
                  right: 16,
                  child: _ScaleBar(
                    metadata: widget.controller.currentFrame!.metadata,
                    scale: _currentScale,
                    viewportWidth: constraints.maxWidth,
                  ),
                );
              }
            ),
          ],
        );
      },
    );
  }
}

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({
    required this.metadata, 
    required this.scale,
    required this.viewportWidth,
  });

  final dynamic metadata;
  final double scale;
  final double viewportWidth;

  @override
  Widget build(BuildContext context) {
    // Parse pixel spacing
    final spacingParts = metadata.pixelSpacing.split('\\');
    if (spacingParts.isEmpty || spacingParts[0].isEmpty) {
      return const SizedBox.shrink();
    }
    
    final pixelSpacing = double.tryParse(spacingParts[0]) ?? 1.0;
    if (pixelSpacing <= 0) return const SizedBox.shrink();

    // 1. Calculate how many logical pixels represent 1 mm on screen
    // The image width on screen (at scale 1.0) is viewportWidth.
    // The physical width of the image is metadata.width * pixelSpacing.
    final physicalImageWidthMm = metadata.width * pixelSpacing;
    final pixelsPerMm = (viewportWidth * scale) / physicalImageWidthMm;

    // 2. Choose a 'nice' real-world length for the scale bar (e.g. 50mm)
    final possibleLengthsMm = [1.0, 5.0, 10.0, 50.0, 100.0, 500.0];
    double chosenLengthMm = 50.0;
    
    // Find the largest nice length that fits within ~30% of the viewport width
    for (final length in possibleLengthsMm.reversed) {
      if ((length * pixelsPerMm) < (viewportWidth * 0.4)) {
        chosenLengthMm = length;
        break;
      }
    }

    final barWidthPx = chosenLengthMm * pixelsPerMm;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${chosenLengthMm.toInt()} mm',
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 12, 
            shadows: [Shadow(color: Colors.black, blurRadius: 4)]
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: barWidthPx,
          height: 2,
          color: Colors.white,
          // Add small end ticks
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(width: 2, height: 6, color: Colors.white),
              Container(width: 2, height: 6, color: Colors.white),
            ],
          ),
        ),
      ],
    );
  }
}
