import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../model/health_record.dart';
import '../app_scope.dart';
import '../theme.dart';

/// Full-screen original pages: swipe between pages, pinch to zoom.
class OriginalsViewer extends StatefulWidget {
  const OriginalsViewer({super.key, required this.title, required this.pages, this.initial = 0});
  final String title;
  final List<Uint8List> pages;
  final int initial;
  @override
  State<OriginalsViewer> createState() => _OriginalsViewerState();
}

class _OriginalsViewerState extends State<OriginalsViewer> {
  late int _page = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: LT.primary,
        appBar: AppBar(
          backgroundColor: LT.primary,
          foregroundColor: LT.onDark,
          title: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('Page ${_page + 1} of ${widget.pages.length}', style: const TextStyle(color: LT.onDarkMuted, fontSize: 13)),
              ),
            ),
          ],
        ),
        body: PageView.builder(
          controller: PageController(initialPage: widget.initial),
          itemCount: widget.pages.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.memory(widget.pages[i], fit: BoxFit.contain, gaplessPlayback: true)),
          ),
        ),
      );
}

/// "Original report · 2 pages" with thumbnails, on a record's screen.
class OriginalsStrip extends StatelessWidget {
  const OriginalsStrip({super.key, required this.record});
  final HealthRecord record;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return FutureBuilder<List<Uint8List>>(
      future: s.originals(record),
      builder: (context, snap) {
        final pages = snap.data;
        if (pages == null) return const SizedBox.shrink();
        if (pages.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(record.attachmentId == null ? 'No original attached.' : 'The original is not on this phone.', style: LT.small),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: LT.surface,
            borderRadius: BorderRadius.circular(LT.radiusLg),
            child: InkWell(
              borderRadius: BorderRadius.circular(LT.radiusLg),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OriginalsViewer(title: record.title, pages: pages))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(pages.first, width: 64, height: 88, fit: BoxFit.cover, cacheWidth: 200),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Original ${record.kind == RecordKind.prescription ? 'prescription' : 'report'}', style: LT.label.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${pages.length} page${pages.length == 1 ? '' : 's'} · tap to view and zoom', style: LT.small),
                    ]),
                  ),
                  const Icon(LucideIcons.maximize2, size: 18, color: LT.ink3),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
