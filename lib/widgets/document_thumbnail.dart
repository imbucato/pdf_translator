import 'dart:io';

import 'package:flutter/material.dart';

class DocumentThumbnail extends StatelessWidget {
  final String documentType;
  final String? thumbnailPath;

  const DocumentThumbnail({
    super.key,
    required this.documentType,
    this.thumbnailPath,
  });

  bool get _isPdf => documentType.toLowerCase() == 'pdf';

  @override
  Widget build(BuildContext context) {
    final path = thumbnailPath;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(path),
          width: 44,
          height: 58,
          cacheWidth: (44 * devicePixelRatio).round(),
          cacheHeight: (58 * devicePixelRatio).round(),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildPlaceholder(context),
        ),
      );
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 44,
      height: 58,
      decoration: BoxDecoration(
        color: _isPdf
            ? colorScheme.errorContainer
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 7,
            top: 7,
            child: Icon(
              _isPdf ? Icons.picture_as_pdf : Icons.menu_book,
              color: _isPdf
                  ? colorScheme.onErrorContainer
                  : colorScheme.onSecondaryContainer,
              size: 22,
            ),
          ),
          Positioned(
            left: 7,
            right: 7,
            bottom: 8,
            child: Text(
              _isPdf ? 'PDF' : 'EPUB',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _isPdf
                    ? colorScheme.onErrorContainer
                    : colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
