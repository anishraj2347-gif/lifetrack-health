import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';
import 'parts.dart';

/// The coffee-template "add a person" page: a full-width photo that fades
/// into the page, the title below it (never on the photo — contrast_test
/// reads text against solid colour), numbered sections, and the main
/// action in a white bar at the bottom like the template's detail screen.
class AddPersonScaffold extends StatelessWidget {
  const AddPersonScaffold({super.key, required this.photo, required this.eyebrow, required this.title, this.description, this.progress, required this.children, this.bottom});
  final String photo;
  final String eyebrow;
  final String title;
  final String? description;

  /// Optional step bar under the photo (onboarding).
  final Widget? progress;
  final List<Widget> children;

  /// The page's main action, kept in reach at the bottom.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final canPop = Navigator.of(context).canPop();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: 240,
            child: Stack(fit: StackFit.expand, children: [
              Appear(child: Image.asset(photo, fit: BoxFit.cover, excludeFromSemantics: true, cacheWidth: (width * dpr).round(), filterQuality: FilterQuality.medium)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.3, 0.75, 1],
                    colors: [Colors.black.withValues(alpha: 0.4), Colors.black.withValues(alpha: 0), LT.ground.withValues(alpha: 0.4), LT.ground],
                  ),
                ),
              ),
              if (canPop)
                Positioned(
                  left: 12,
                  top: MediaQuery.paddingOf(context).top + 8,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: CircleBorder(),
                    child: IconButton(
                      tooltip: 'Back',
                      icon: Icon(LucideIcons.arrowLeft, color: Colors.white, size: 22),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (progress != null) ...[progress!, SizedBox(height: 14)] else ...[Text(eyebrow, style: LT.eyebrow), SizedBox(height: 4)],
              Text(title, style: LT.hero),
              if (description != null) ...[SizedBox(height: 8), Text(description!, style: LT.lede)],
            ]),
          ),
          SizedBox(height: 8),
          ...children,
          SizedBox(height: 28),
        ]),
        bottomNavigationBar: bottom == null
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: LT.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: LT.dark ? 0.4 : 0.08), blurRadius: 20, offset: Offset(0, -4))],
                ),
                child: SafeArea(top: false, child: Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 12), child: bottom)),
              ),
      ),
    );
  }
}

/// One numbered part of an add page: the number turns into a caramel tick
/// once that part is done ("done / now" — never a health status).
class StepSection extends StatelessWidget {
  const StepSection({super.key, required this.number, required this.title, this.caption, required this.child, this.done = false, this.padChild = true});
  final int number;
  final String title;
  final String? caption;
  final Widget child;
  final bool done;

  /// False for children that bring their own side margins (DigiLockerStep).
  final bool padChild;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: done ? LT.accent : LT.raised, border: done ? null : Border.all(color: LT.rule)),
                child: done
                    ? Icon(LucideIcons.check, size: 16, color: LT.onAccent)
                    : Text('$number', style: TextStyle(fontFamily: LT.display, fontSize: 13, fontWeight: FontWeight.w600, color: LT.ink)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 3),
                  Text(title, style: LT.label.copyWith(fontWeight: FontWeight.w600, fontSize: 16)),
                  if (caption != null) ...[SizedBox(height: 2), Text(caption!, style: LT.small)],
                ]),
              ),
            ]),
          ),
          if (padChild) Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: child) else child,
        ]),
      );
}
