// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'palette.dart';

export 'palette.dart';

// ---------------------------------------------------------------------------
// Spacing: one 4-based scale. Page gutter 16, section gap 24, row gap 8.
// ---------------------------------------------------------------------------
const gutter = 16.0;

/// Clearance below the last row when a floating action button is shown.
const fabClearance = 88.0;

/// List padding that consumes the real bottom inset (system bar or the
/// floating navigation reported by the shell Scaffold) instead of hiding it.
EdgeInsets pagePadding(
  BuildContext context, {
  double top = 8,
  bool fab = false,
  double horizontal = gutter,
}) => EdgeInsets.fromLTRB(
  horizontal,
  top,
  horizontal,
  MediaQuery.paddingOf(context).bottom + (fab ? fabClearance : 32),
);

String errorMessage(Object error) {
  if (error is AspanError) return error.message;
  if (error is PlatformException) return error.message ?? '文件操作失败，请重试';
  if (error is FormatException) return error.message;
  if (error is StateError) return error.message.toString();
  return '操作未完成，请检查文件或安装环境后重试';
}

// ---------------------------------------------------------------------------
// Business status vocabulary. Values come from Rust; Flutter only labels them.
// ---------------------------------------------------------------------------
const phaseLabels = {
  'normal': '待发生',
  'reminder': '提前提醒',
  'due': '今天处理',
  'grace': '处理窗口',
  'overdue': '已逾期',
  'processing': '处理中',
  'idle': '无待办周期',
};

Color warningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFCF87)
    : const Color(0xFF835000);
Color successColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF8FD9A8)
    : const Color(0xFF1E6B3F);

Color phaseColor(BuildContext context, String phase) => switch (phase) {
  'overdue' => Theme.of(context).colorScheme.error,
  'due' || 'grace' || 'processing' => warningColor(context),
  'reminder' => Theme.of(context).colorScheme.primary,
  _ => SpanColors.of(context).muted,
};

/// Phases that ask the user to act now; ordered by urgency.
const actionPhases = ['overdue', 'due', 'grace', 'processing'];

const ruleIcons = [
  ('schedule', '时间', Icons.timelapse_outlined),
  ('payments', '支付', Icons.payments_outlined),
  ('resource', '资源', Icons.toll_outlined),
  ('maintenance', '维护', Icons.build_outlined),
  ('expiry', '有效期', Icons.verified_user_outlined),
  ('medication', '吃药', Icons.medication_outlined),
  ('task', '待办', Icons.task_alt_outlined),
  ('birthday', '生日', Icons.cake_outlined),
];
IconData ruleIcon(String? key) =>
    ruleIcons.firstWhere((e) => e.$1 == key, orElse: () => ruleIcons.first).$3;

// ---------------------------------------------------------------------------
// Date display. Rust owns date arithmetic; these only format returned values.
// ---------------------------------------------------------------------------
const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
String friendlyDate(String? iso, {bool weekday = true}) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final now = DateTime.now();
  final year = d.year == now.year ? '' : '${d.year}年';
  return '$year${d.month}月${d.day}日${weekday ? ' 周${_weekdays[d.weekday - 1]}' : ''}';
}

String relativeDays(int days) => switch (days) {
  0 => '今天',
  1 => '明天',
  -1 => '昨天',
  > 1 => '$days 天后',
  _ => '逾期 ${-days} 天',
};

String cycleLabel(Json? cycle) => switch (cycle?['kind']) {
  null => '无周期',
  'once' => '单次',
  'daily' => '每日',
  'weekly' => '每周',
  'monthly' => '每自然月',
  'yearly' => '每自然年',
  'interval' => '每 ${cycle!['days']} 天',
  'restart' => '完成后每 ${cycle!['days']} 天重新计时',
  'calendar' => '指定日期 ${(cycle!['dates'] as List?)?.length ?? 0} 个',
  _ => '${cycle!['kind']}',
};

String reminderSummary(Json reminder) {
  final before = [...(reminder['before'] as List? ?? const [])]
    ..sort((a, b) => (b as int).compareTo(a as int));
  final grace = reminder['grace_days'] as int? ?? 0;
  final repeat = reminder['repeat_days'] as int?;
  final parts = [
    if (before.isNotEmpty) '提前 ${before.join('、')} 天',
    if (reminder['on_day'] == true) '当天',
    if (grace > 0) '处理窗口 $grace 天',
    if (repeat != null) '每 $repeat 天重复',
  ];
  return parts.isEmpty ? '不提醒' : parts.join(' · ');
}

/// Verbs follow the unit so a count card says "使用" and money says "扣费".
(String add, String consume) resourceVerbs(String? kind) => switch (kind) {
  'money' => ('充值', '扣费'),
  'count' => ('增加次数', '使用'),
  _ => ('增加', '消耗'),
};

// ---------------------------------------------------------------------------
// Feedback helpers.
// ---------------------------------------------------------------------------
void notify(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> perform(
  BuildContext context,
  Future<dynamic> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) notify(context, success);
  } catch (error) {
    if (context.mounted) notify(context, errorMessage(error));
  }
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String? label,
  String? helper,
  String action = '确定',
  TextInputType? keyboard,
}) => showDialog<String>(
  context: context,
  builder: (context) => TextControllerScope(
    initial: initial,
    builder: (context, controller) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final value = controller.text.trim();
            if (value.isEmpty) {
              setState(() => error = '请填写${label ?? '名称'}');
              return;
            }
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              autofocus: true,
              controller: controller,
              keyboardType: keyboard,
              decoration: InputDecoration(
                labelText: label ?? '名称',
                helperText: helper,
                errorText: error,
              ),
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(onPressed: submit, child: Text(action)),
            ],
          );
        },
      );
    },
  ),
);

class TextControllerScope extends StatefulWidget {
  final String initial;
  final Widget Function(BuildContext, TextEditingController) builder;
  const TextControllerScope({
    super.key,
    required this.initial,
    required this.builder,
  });
  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, controller);
}

/// Confirmation for irreversible or replacing operations. Destructive actions
/// name the consequence on the button instead of a generic "确认".
Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确认',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        );
      },
    ) ??
    false;

// ---------------------------------------------------------------------------
// Bottom sheets: one layout for every short task (event, resource, entry…).
// ---------------------------------------------------------------------------
Future<T?> showSpanSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );

class SheetBody extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> content;
  final List<Widget> actions;
  const SheetBody({
    super.key,
    required this.title,
    this.subtitle,
    this.content = const [],
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + media.viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            ...content,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline message box used for guidance, warnings and failed saves.
class Callout extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  const Callout(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      liveRegion: color != null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Structure.
// ---------------------------------------------------------------------------
class SectionHeader extends StatelessWidget {
  final String text;
  final String? note;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionHeader(
    this.text, {
    super.key,
    this.note,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 8),
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                note == null ? text : '$text  ·  $note',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A single grouped surface. Rows inside are separated by inset dividers;
/// panels are never nested.
class Panel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double dividerIndent;
  const Panel({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.dividerIndent = 56,
  });
  @override
  Widget build(BuildContext context) {
    final colors = SpanColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && dividerIndent >= 0) {
        rows.add(Divider(indent: dividerIndent, height: 1));
      }
      rows.add(children[i]);
    }
    return Material(
      color: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

class PhaseBadge extends StatelessWidget {
  final String phase;
  const PhaseBadge(this.phase, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = phase == 'normal' || phase == 'idle'
        ? SpanColors.of(context).muted
        : phaseColor(context, phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        phaseLabels[phase] ?? '未知阶段',
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Rounded square that carries a rule/category icon.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const IconTile(this.icon, {super.key, this.color, this.size = 36});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(size * .3),
        ),
        child: Icon(icon, size: size * .55, color: c),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Widget? action;
  const EmptyState(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(icon, size: 52, color: SpanColors.of(context).muted),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.5),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// Centers page content on wide screens without changing phone layout.
class Readable extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Readable({super.key, required this.child, this.maxWidth = 760});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

const tabular = [FontFeature.tabularFigures()];
