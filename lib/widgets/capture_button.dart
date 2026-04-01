import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CaptureButton extends StatelessWidget {
  final bool isProcessing;
  final bool isListening;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  const CaptureButton({
    super.key,
    this.isProcessing = false,
    this.isListening = false,
    required this.onPressed,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isProcessing
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onPressed();
            },
      onLongPress: () {
        HapticFeedback.heavyImpact();
        onLongPress();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isListening ? 100 : 88,
        height: isListening ? 100 : 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening
              ? Colors.red
              : isProcessing
                  ? Colors.grey
                  : Theme.of(context).primaryColor,
          boxShadow: [
            BoxShadow(
              color: (isListening ? Colors.red : Theme.of(context).primaryColor)
                  .withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: isProcessing
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 4))
              : Icon(isListening ? Icons.mic : Icons.camera_alt,
                  size: 44, color: Colors.white),
        ),
      ),
    );
  }
}
