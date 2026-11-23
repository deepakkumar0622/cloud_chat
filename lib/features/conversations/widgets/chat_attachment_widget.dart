import 'package:material_ui/material_ui.dart';

class ChatAttachmentWidget extends StatelessWidget {
  const ChatAttachmentWidget({
    super.key,
    required this.child,
    required this.onTap,
    this.isOpening = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool isOpening;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isOpening ? null : onTap,
      child: Stack(
        children: [
          child,
          if (isOpening)
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
