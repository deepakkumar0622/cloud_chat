import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:photo_view/photo_view.dart';

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.bytes,
    required this.fileName,
  });
  final Uint8List bytes;
  final String fileName;
  static const background = Color(0xFF101827);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: PhotoView(
        imageProvider: MemoryImage(bytes),
        backgroundDecoration: const BoxDecoration(color: background),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        initialScale: PhotoViewComputedScale.contained,
        loadingBuilder: (context, event) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF7568F5)),
        ),
      ),
    );
  }
}
