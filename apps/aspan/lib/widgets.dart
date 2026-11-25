// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data.dart';
import 'design.dart';

/// One rule in a list: name, one line of status, and a compact progress ring.
class RuleRow extends StatelessWidget {
  final SpanStore store;
  final Json rule;
  final VoidCallback onTap;
  final void Function(Offset position)? onMenu;
  final Widget? leading, trailing;
  final bool first, last, selected;

  /// Extra left inset for members shown under a merged entry.
  final double indent;
  const RuleRow({
    super.key,
    required this.store,
    required this.rule,
    required this.onTap,
    this.onMenu,
    this.leading,
    this.trailing,
    this.first = false,
    this.last = false,
    this.selected = false,
    this.indent = 0,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final v = store.view(rule['id'] as String), phase = v['phase'] as String;
    final days = v['remaining_days'] as int?;
    final account = v['account'] as Map?;
    final flagged = actionPhases.contains(phase) || phase == 'reminder';
    final accent = flagged
        ? phaseColor(context, phase)
        : theme.colorScheme.primary;
    final tags = rule['tags'] as List;
    final firstTag = tags.isEmpty
        ? null
        : store.state['tags'][tags.first]?['name'];
    final balance = account == null
        ? null
        : '${account['formatted']} ${unitLabel(account['unit'])}';
    final ended = rule['schedule'] != null && v['planned'] == null;
    final status = days != null
        ? phase == 'grace' || phase == 'processing'
              ? '${phaseLabel(phase)} · ${relativeDays(days)}'
              : relativeDays(days)
        : balance ?? (ended ? tr('周期已结束') : null);
    final meta = [
      if (v['planned'] != null)
        friendlyDate(v['planned'] as String, weekday: false),
      if (balance != null && days != null) balance,
      if (firstTag != null) '#$firstTag',
    ].join(' · ');
    final progress = (v['time_progress'] ?? account?['progress']) as num?;
    final leadSpace = 16.0 + indent;
    return Semantics(
      selected: selected,
      child: GroupedTile(
        first: first,
        last: last,
        selected: selected,
        onTap: onTap,
        onMenu: onMenu,
        indent: leadSpace,
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: math.max(0, leadSpace - 12)),
              leading!,
            ] else
              SizedBox(width: leadSpace),
            Expanded(
              child: MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rule['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (status != null || meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (status != null)
                                TextSpan(
                                  text: status,
                                  style: TextStyle(
                                    color: flagged ? accent : null,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (status != null && meta.isNotEmpty)
                                const TextSpan(text: '   '),
                              if (meta.isNotEmpty)
                                TextSpan(
                                  text: meta,
                                  style: TextStyle(color: colors.muted),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                      // Dated rules show the phased timeline; balance-only
                      // rules show how much of the reference remains.
                      if (v['time_progress'] != null) ...[
                        const SizedBox(height: 8),
                        TimelineBar(
                          compact: true,
                          segments: v['segments'] == null
                              ? null
                              : object(v['segments']),
                          progress: (v['time_progress'] as num).toDouble(),
                          remainingDays: days,
                          graceDays:
                              rule['reminder']?['grace_days'] as int? ?? 0,
                          color: accent,
                        ),
                      ] else if (progress != null) ...[
                        const SizedBox(height: 8),
                        ProgressBar(
                          value: progress.toDouble(),
                          color: accent,
                          label: tr('资源剩余比例'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            trailing ?? const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// Compact pill that completes the current period from a list row.
class CompleteButton extends StatelessWidget {
  final VoidCallback onPressed;
  const CompleteButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
    child: Tooltip(
      message: tr('完成本期'),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: SpanColors.of(context).fill,
          minimumSize: const Size(56, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
          textStyle: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 14),
        ),
        child: Text(tr('完成')),
      ),
    ),
  );
}

/// A merged entry: a summary row whose members can unfold beneath it.
class GroupRow extends StatelessWidget {
  final SpanStore store;
  final Json group;
  final List<Json> members;
  final bool expanded, first, last, dimmed;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final void Function(Offset position)? onMenu;
  final Widget? trailing;
  const GroupRow({
    super.key,
    required this.store,
    required this.group,
    required this.members,
    required this.expanded,
    required this.onTap,
    this.onToggle,
    this.onMenu,
    this.trailing,
    this.first = false,
    this.last = false,
    this.dimmed = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final shared = [
      for (final aid in group['accounts'] as List)
        '${store.accountView(aid as String)['formatted']} ${unitLabel(store.accountView(aid)['unit'])}',
    ];
    final urgent = members
        .map((m) => store.view(m['id'] as String)['phase'] as String)
        .where(actionPhases.contains)
        .length;
    final meta = [
      tr('{n} 条规则', {'n': members.length}),
      if (shared.isNotEmpty) shared.join(' / '),
    ].join(' · ');
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: dimmed ? .4 : 1,
      child: GroupedTile(
        first: first,
        last: last && !expanded,
        onTap: onTap,
        onMenu: onMenu,
        indent: 52,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(
              Icons.layers_outlined,
              size: 24,
              color: urgent > 0
                  ? warningColor(context)
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (urgent > 0)
                              TextSpan(
                                text: '${tr('{n} 条需处理', {'n': urgent})}   ',
                                style: TextStyle(
                                  color: warningColor(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            TextSpan(text: meta),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: colors.muted,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onToggle != null)
              IconButton(
                key: ValueKey('toggle-${group['id']}'),
                tooltip: expanded ? tr('收起成员') : tr('展开成员'),
                onPressed: onToggle,
                icon: AnimatedRotation(
                  turns: expanded ? .25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.chevron_right, color: colors.muted),
                ),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Thin rounded progress bar used in list rows.
class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final String label;
  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${(value * 100).round()}%',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 4,
        color: color,
        backgroundColor: SpanColors.of(context).fill,
      ),
    ),
  );
}

/// Phase timeline: real-proportion segments (normal → reminder → event →
/// processing window), separated by small gaps and filled up to today.
/// Values come from Rust. The compact form is used in list rows; the full
/// form adds a marker for today.
class TimelineBar extends StatelessWidget {
  final Json? segments;
  final double progress;
  final int? remainingDays;
  final int graceDays;
  final Color color;
  final bool compact;
  const TimelineBar({
    super.key,
    required this.segments,
    required this.progress,
    required this.remainingDays,
    required this.graceDays,
    required this.color,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final n = (segments?['normal'] as num? ?? 1).toDouble();
    final r = (segments?['reminder'] as num? ?? 0).toDouble();
    final g = (segments?['grace'] as num? ?? 0).toDouble();
    final event = (n + r).clamp(0.0, 1.0);
    final days = remainingDays ?? 0;
    final position = days >= 0
        ? progress * event
        : g > 0 && graceDays > 0
        ? event + (-days / graceDays).clamp(0.0, 1.0) * g
        : 1.0;
    final colors = SpanColors.of(context);
    return Semantics(
      label: tr('时间进度'),
      value: '${(progress * 100).round()}%',
      child: SizedBox(
        height: compact ? 5 : 14,
        width: double.infinity,
        child: CustomPaint(
          painter: _TimelinePainter(
            normal: n,
            reminder: r,
            grace: g,
            position: position.clamp(0.0, 1.0),
            fill: color,
            track: colors.fill,
            reminderTint: Theme.of(context).colorScheme.primary,
            graceTint: warningColor(context),
            marker: compact ? null : colors.panel,
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final double normal, reminder, grace, position;
  final Color fill, track, reminderTint, graceTint;
  final Color? marker;
  _TimelinePainter({
    required this.normal,
    required this.reminder,
    required this.grace,
    required this.position,
    required this.fill,
    required this.track,
    required this.reminderTint,
    required this.graceTint,
    required this.marker,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final h = marker == null ? size.height : 6.0;
    final top = (size.height - h) / 2;
    final radius = Radius.circular(h / 2);
    const gap = 3.0;
    final parts = [
      (normal, track),
      (reminder, reminderTint.withValues(alpha: .25)),
      (grace, graceTint.withValues(alpha: .3)),
    ].where((p) => p.$1 > 0).toList();
    final usable = size.width - gap * (parts.length - 1);
    final reached = position * usable;
    var x = 0.0, done = 0.0;
    for (final (fraction, tint) in parts) {
      final w = fraction * usable;
      final piece = RRect.fromLTRBR(x, top, x + w, top + h, radius);
      canvas.drawRRect(piece, Paint()..color = tint);
      final filled = (reached - done).clamp(0.0, w);
      if (filled > 0) {
        canvas.save();
        canvas.clipRRect(piece);
        canvas.drawRect(
          Rect.fromLTWH(x, top, filled, h),
          Paint()..color = fill,
        );
        canvas.restore();
      }
      x += w + gap;
      done += w;
    }
    if (marker != null) {
      // Map the position back onto the gapped bar.
      var cx = reached, acc = 0.0;
      for (var i = 0; i < parts.length; i++) {
        acc += parts[i].$1 * usable;
        if (reached <= acc || i == parts.length - 1) {
          cx = reached + gap * i;
          break;
        }
      }
      cx = cx.clamp(7.0, size.width - 7);
      canvas.drawCircle(
        Offset(cx, size.height / 2),
        7,
        Paint()..color = marker!,
      );
      canvas.drawCircle(
        Offset(cx, size.height / 2),
        4.5,
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.position != position ||
      old.normal != normal ||
      old.reminder != reminder ||
      old.grace != grace ||
      old.fill != fill ||
      old.track != track ||
      old.marker != marker;
}
