import 'package:flutter/material.dart';
import '../clinic_model.dart';
import '../theme/app_theme.dart';

/// A map pin that reacts to hover (desktop/web) and tap (everywhere).
/// Hovering grows the dot and reveals the facility name; tapping opens
/// the full detail sheet with call / website / directions.
class MapMarker extends StatefulWidget {
  final Clinic clinic;
  final Color color;
  final VoidCallback onTap;

  const MapMarker({super.key, required this.clinic, required this.color, required this.onTap});

  @override
  State<MapMarker> createState() => _MapMarkerState();
}

class _MapMarkerState extends State<MapMarker> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    // Tooltip handles hover on web/desktop and long-press on touch devices,
    // so the name is reachable no matter the platform.
    return Tooltip(
      message: widget.clinic.name,
      waitDuration: const Duration(milliseconds: 150),
      textStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _hovering ? 1.35 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.withValues(alpha: _hovering ? 0.38 : 0.22),
                border: Border.all(color: c, width: _hovering ? 2.2 : 1.6),
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: _hovering ? 0.85 : 0.55),
                    blurRadius: _hovering ? 14 : 8,
                    spreadRadius: _hovering ? 2 : 1,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const LegendDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}

