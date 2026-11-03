// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'data.dart';
import 'design.dart';

/// Shared frame for list strips: one surface, one radius, one selection style.
class StripFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final bool selected, dimmed;
  const StripFrame({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dimmed = false,
  });
  @override
  Widget build(BuildContext context) {
    final colors = SpanColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: dimmed ? .45 : 1,
        child: Material(
          color: selected ? colors.soft : colors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? primary : colors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, onLongPress: onLongPress, child: child),
        ),
      ),
    );
  }
}

/// Compact horizontal strip: icon · name · next date · status · one bar.
class RuleTile extends StatelessWidget {
  final SpanStore store;
  final Json rule;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selected, dimmed, dense;
  const RuleTile({
    super.key,
    required this.store,
    required this.rule,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.dimmed = false,
    this.dense = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final v = store.view(rule['id'] as String), phase = v['phase'] as String;
    final days = v['remaining_days'] as int?;
    final account = v['account'] as Map?;
    final urgent = actionPhases.contains(phase);
    final accent = urgent || phase == 'reminder'
        ? phaseColor(context, phase)
        : theme.colorScheme.primary;
    final firstTag = (rule['tags'] as List).isEmpty
        ? null
        : store.state['tags'][(rule['tags'] as List).first]?['name'];
    final balance = account == null
        ? null
        : '${account['formatted']} ${account['unit']}';
    final ended = rule['schedule'] != null && v['planned'] == null;
    final meta = [
      if (v['planned'] != null) friendlyDate(v['planned'] as String),
      if (ended) '周期已结束',
      if (balance != null && days != null) balance,
      if (firstTag != null) '#$firstTag',
    ].join('  ·  ');
    final progress = (v['time_progress'] ?? account?['progress']) as num?;
    final status = days != null ? relativeDays(days) : balance;
    final showPhase = const ['reminder', 'grace', 'processing'].contains(phase);
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: StripFrame(
          onTap: onTap,
          onLongPress: onLongPress,
          selected: selected,
          dimmed: dimmed,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, dense ? 8 : 11, 8, dense ? 8 : 11),
            child: Row(
              children: [
                IconTile(ruleIcon(rule['icon'] as String?), color: accent),
                const SizedBox(width: 12),
                Expanded(
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
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (progress != null && !dense) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          label: v['time_progress'] != null ? '时间进度' : '资源剩余比例',
                          value: '${(progress * 100).round()}%',
                          child: LinearProgressIndicator(
                            value: progress.toDouble(),
                            minHeight: 3,
                            color: accent,
                            backgroundColor: colors.soft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (status != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          color: urgent ? accent : null,
                          fontFeatures: tabular,
                        ),
                      ),
                      if (showPhase) ...[
                        const SizedBox(height: 2),
                        Text(
                          phaseLabels[phase]!,
                          style: TextStyle(
                            fontSize: 12,
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                if (trailing != null) trailing! else const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A merged entry: summary strip plus optional inline members.
class GroupTile extends StatelessWidget {
  final SpanStore store;
  final Json group;
  final List<Json> members;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final Widget Function(Json member) memberBuilder;
  final bool dimmed;
  final Widget? trailing;
  const GroupTile({
    super.key,
    required this.store,
    required this.group,
    required this.members,
    required this.expanded,
    required this.onTap,
    required this.memberBuilder,
    this.onToggle,
    this.dimmed = false,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shared = [
      for (final aid in group['accounts'] as List)
        '${store.accountView(aid as String)['formatted']} ${store.accountView(aid)['unit']}',
    ];
    final urgent = members
        .map((m) => store.view(m['id'] as String)['phase'] as String)
        .where(actionPhases.contains)
        .length;
    final meta = [
      '${members.length} 条规则',
      if (shared.isNotEmpty) '共享 ${shared.join(' / ')}',
      if (urgent > 0) '$urgent 条需处理',
    ].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: StripFrame(
            onTap: onTap,
            dimmed: dimmed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
              child: Row(
                children: [
                  IconTile(
                    Icons.layers_outlined,
                    color: urgent > 0
                        ? warningColor(context)
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
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
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (onToggle != null)
                    IconButton(
                      key: ValueKey('toggle-${group['id']}'),
                      tooltip: expanded ? '收起成员' : '展开成员',
                      onPressed: onToggle,
                      icon: AnimatedRotation(
                        turns: expanded ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.expand_more),
                      ),
                    ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: SpanColors.of(context).line,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        children: [for (final m in members) memberBuilder(m)],
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Phase timeline: real-proportion segments (normal → reminder → event →
/// processing window) with a marker for today. Values come from Rust.
class TimelineBar extends StatelessWidget {
  final Json? segments;
  final double progress;
  final int? remainingDays;
  final int graceDays;
  final Color color;
  const TimelineBar({
    super.key,
    required this.segments,
    required this.progress,
    required this.remainingDays,
    required this.graceDays,
    required this.color,
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
      label: '时间进度',
      value: '${(progress * 100).round()}%',
      child: SizedBox(
        height: 16,
        width: double.infinity,
        child: CustomPaint(
          painter: _TimelinePainter(
            normal: n,
            reminder: r,
            grace: g,
            position: position.clamp(0.0, 1.0),
            event: event,
            fill: color,
            track: colors.soft,
            reminderTint: Theme.of(context).colorScheme.primary,
            graceTint: warningColor(context),
            marker: colors.panel,
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final double normal, reminder, grace, position, event;
  final Color fill, track, reminderTint, graceTint, marker;
  _TimelinePainter({
    required this.normal,
    required this.reminder,
    required this.grace,
    required this.position,
    required this.event,
    required this.fill,
    required this.track,
    required this.reminderTint,
    required this.graceTint,
    required this.marker,
  });
  @override
  void paint(Canvas canvas, Size size) {
    const h = 6.0;
    final top = (size.height - h) / 2;
    final bar = RRect.fromLTRBR(
      0,
      top,
      size.width,
      top + h,
      const Radius.circular(3),
    );
    canvas.save();
    canvas.clipRRect(bar);
    var x = 0.0;
    for (final (fraction, color) in [
      (normal, track),
      (reminder, reminderTint.withValues(alpha: .28)),
      (grace, graceTint.withValues(alpha: .32)),
    ]) {
      final w = fraction * size.width;
      canvas.drawRect(Rect.fromLTWH(x, top, w, h), Paint()..color = color);
      x += w;
    }
    canvas.drawRect(
      Rect.fromLTWH(0, top, position * size.width, h),
      Paint()..color = fill,
    );
    canvas.restore();
    if (grace > 0 && event < 1) {
      final ex = event * size.width;
      canvas.drawRect(
        Rect.fromLTWH(ex - 1, top - 3, 2, h + 6),
        Paint()..color = graceTint,
      );
    }
    final cx = (position * size.width).clamp(6.0, size.width - 6);
    canvas.drawCircle(Offset(cx, size.height / 2), 6, Paint()..color = marker);
    canvas.drawCircle(Offset(cx, size.height / 2), 4, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.position != position ||
      old.normal != normal ||
      old.reminder != reminder ||
      old.grace != grace ||
      old.fill != fill ||
      old.track != track;
}

/// Bounds constructed rows while keeping every retained record accessible.
class PagedItems extends StatefulWidget {
  final List<Json> items;
  final Widget Function(Json) itemBuilder;
  const PagedItems({super.key, required this.items, required this.itemBuilder});
  @override
  State<PagedItems> createState() => _PagedItemsState();
}

class _PagedItemsState extends State<PagedItems> {
  int page = 0;
  static const pageSize = 50;
  @override
  Widget build(BuildContext context) {
    final pages = (widget.items.length / pageSize).ceil().clamp(1, 1 << 31);
    final current = page.clamp(0, pages - 1);
    final rows = [
      for (final item in widget.items.skip(current * pageSize).take(pageSize))
        widget.itemBuilder(item),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(children: rows),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一页',
                  onPressed: current == 0
                      ? null
                      : () => setState(() => page = current - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${current + 1} / $pages 页 · 共 ${widget.items.length} 条',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: '下一页',
                  onPressed: current + 1 >= pages
                      ? null
                      : () => setState(() => page = current + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
