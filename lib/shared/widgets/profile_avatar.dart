import 'package:material_ui/material_ui.dart';

import '../../core/services/supabase_storage_service.dart';

class ProfileAvatar extends StatefulWidget {
  final String name;
  final String? photoPath;
  final double radius;
  final Color backgroundColor;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.radius = 25,
    this.backgroundColor = const Color(0xFF7568F5),
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  late Future<String?> _photoUrlFuture;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.photoPath != widget.photoPath) {
      _loadPhoto();
    }
  }

  void _loadPhoto() {
    final path = widget.photoPath;

    if (path == null || path.isEmpty) {
      _photoUrlFuture = Future.value(null);
      return;
    }

    _photoUrlFuture = SupabaseStorageService.instance
        .getProfilePhotoUrl(path)
        .catchError((_) => '');
  }

  String _getInitial() {
    final name = widget.name.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  Widget _buildFallback() {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor.withValues(alpha: 0.5),
      child: Text(
        _getInitial(),
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.radius * 0.72,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photoPath == null || widget.photoPath!.isEmpty) {
      return _buildFallback();
    }

    return FutureBuilder<String?>(
      future: _photoUrlFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting ||
            url == null ||
            url.isEmpty) {
          return _buildFallback();
        }

        return ClipOval(
          child: SizedBox(
            width: widget.radius * 2,
            height: widget.radius * 2,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildFallback();
              },
            ),
          ),
        );
      },
    );
  }
}
