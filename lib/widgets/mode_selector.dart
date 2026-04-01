import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/assistant_mode.dart';

class ModeSelector extends StatelessWidget {
  final AssistantMode currentMode;
  final ValueChanged<AssistantMode> onModeChanged;

  const ModeSelector(
      {super.key, required this.currentMode, required this.onModeChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: AssistantMode.values.length,
        itemBuilder: (context, index) {
          final mode = AssistantMode.values[index];
          final isSelected = mode == currentMode;

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onModeChanged(mode);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.withOpacity(0.3),
                      width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(mode.icon, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 4),
                    Text(mode.shortName,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
