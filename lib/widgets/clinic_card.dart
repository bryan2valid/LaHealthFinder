import 'package:flutter/material.dart';
import '../clinic_model.dart';
import '../theme/app_theme.dart';

/// The directions button on each clinic card. On hover it fills in,
/// glows, and the arrow nudges up-and-right in the direction it points —
/// a small bit of motion that signals "this takes you somewhere."
class DirectionsArrow extends StatefulWidget {
  final VoidCallback onTap;
  const DirectionsArrow({super.key, required this.onTap});

  @override
  State<DirectionsArrow> createState() => _DirectionsArrowState();
}

class _DirectionsArrowState extends State<DirectionsArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: _hovering ? 0.28 : 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: _hovering ? 0.75 : 0.0),
            ),
            boxShadow: _hovering
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            offset: _hovering ? const Offset(0.09, -0.09) : Offset.zero,
            child: const Icon(Icons.north_east_rounded, color: AppColors.accent, size: 18),
          ),
        ),
      ),
    );
  }
}

class ClinicCard extends StatefulWidget {
  final Clinic clinic;
  final double? distanceMiles;
  final bool bestMatch;
  final VoidCallback onDirections;
  final VoidCallback onTap;

  const ClinicCard({
    super.key,
    required this.clinic,
    required this.distanceMiles,
    this.bestMatch = false,
    required this.onDirections,
    required this.onTap,
  });

  @override
  State<ClinicCard> createState() => _ClinicCardState();
}

class _ClinicCardState extends State<ClinicCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final clinic = widget.clinic;
    final distanceMiles = widget.distanceMiles;
    final bestMatch = widget.bestMatch;
    final onDirections = widget.onDirections;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hovering ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hovering ? AppColors.accent.withValues(alpha: 0.45) : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clinic.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${clinic.parish} Parish · ${clinic.languagesSpoken}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (distanceMiles != null) ...[
                      const SizedBox(width: 6),
                      Text('· ~${distanceMiles.toStringAsFixed(1)} mi',
                          style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 13,
                        color: clinic.rating != null ? AppColors.wellness : AppColors.textFaint),
                    const SizedBox(width: 3),
                    Text(
                      clinic.rating != null ? clinic.rating!.toStringAsFixed(1) : 'No rating',
                      style: TextStyle(
                        color: clinic.rating != null ? AppColors.textSecondary : AppColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (bestMatch)
                      const TagPill(label: 'BEST MATCH', color: AppColors.accent, icon: Icons.check_circle_rounded),
                    TagPill(label: clinic.type.label.toUpperCase(), color: AppColors.textSecondary),
                    if (clinic.hasER)
                      const TagPill(label: 'ER', color: AppColors.critical, icon: Icons.emergency_rounded),
                    if (clinic.isStrokeCenter)
                      const TagPill(label: 'STROKE CTR', color: AppColors.critical),
                    if (clinic.offersMentalHealth)
                      const TagPill(label: 'MENTAL HEALTH', color: AppColors.wellness),
                    if (clinic.servesVeterans)
                      const TagPill(label: 'VETERAN CARE', color: AppColors.coverage, icon: Icons.military_tech_rounded),
                    if (!clinic.hasRealLocation)
                      const TagPill(label: 'NO LOCATION DATA', color: AppColors.textFaint),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DirectionsArrow(onTap: onDirections),
        ],
      ),
    ),
    ),
    );
  }
}
