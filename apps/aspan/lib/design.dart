// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'l10n/l10n.dart';
import 'palette.dart';

export 'l10n/l10n.dart';
export 'palette.dart';

// ---------------------------------------------------------------------------
// Spacing: page gutter 16, grouped cards with radius 12, 16pt row insets.
// ---------------------------------------------------------------------------
const gutter = 16.0;
const tabular = [FontFeature.tabularFigures()];

/// Messages from the Rust core are Simplified Chinese; [tr] translates the
/// static ones and passes messages with dynamic parts through unchanged.
String errorMessage(Object error) {
  if (error is AspanError) return tr(error.message);
  if (error is PlatformException) {
    return error.message ?? tr('文件操作失败，请重试');
  }
  if (error is FormatException) return error.message;
  if (error is StateError) return tr(error.message.toString());
  return tr('操作未完成，请检查文件或安装环境后重试');
}

// ---------------------------------------------------------------------------
// Business status vocabulary. Values come from Rust; Flutter only labels them.
// ---------------------------------------------------------------------------
String phaseLabel(String phase) => switch (phase) {
  'normal' => tr('待发生'),
  'reminder' => tr('提前提醒'),
  'due' => tr('今天处理'),
  'grace' => tr('处理窗口'),
  'overdue' => tr('已逾期'),
  'processing' => tr('处理中'),
  'idle' => tr('无待办周期'),
  _ => phase,
};

/// Count units are stored as the code `次`; other units are user text.
String unitLabel(Object? code) => tr(code == null ? '' : code.toString());

Color warningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFB340)
    : const Color(0xFFB05000);
Color successColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF5FD47A)
    : const Color(0xFF1E7B34);

Color phaseColor(BuildContext context, String phase) => switch (phase) {
  'overdue' => Theme.of(context).colorScheme.error,
  'due' || 'grace' || 'processing' => warningColor(context),
  'reminder' => Theme.of(context).colorScheme.primary,
  _ => SpanColors.of(context).muted,
};

/// Phases that ask the user to act now; ordered by urgency.
const actionPhases = ['overdue', 'due', 'grace', 'processing'];

List<(String, String, IconData)> get ruleIcons => [
  ('schedule', tr('时间'), Icons.timelapse_outlined),
  ('payments', tr('支付'), Icons.payments_outlined),
  ('resource', tr('资源'), Icons.toll_outlined),
  ('maintenance', tr('维护'), Icons.build_outlined),
  ('expiry', tr('有效期'), Icons.verified_user_outlined),
  ('medication', tr('吃药'), Icons.medication_outlined),
  ('task', tr('待办'), Icons.task_alt_outlined),
  ('birthday', tr('生日'), Icons.cake_outlined),
];
IconData ruleIcon(String? key) {
  final icons = ruleIcons;
  return icons.firstWhere((e) => e.$1 == key, orElse: () => icons.first).$3;
}

// ---------------------------------------------------------------------------
// Date display. Rust owns date arithmetic; these only format returned values.
// ---------------------------------------------------------------------------
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _weekday(int day) => switch (day) {
  DateTime.monday => tr('周一'),
  DateTime.tuesday => tr('周二'),
  DateTime.wednesday => tr('周三'),
  DateTime.thursday => tr('周四'),
  DateTime.friday => tr('周五'),
  DateTime.saturday => tr('周六'),
  _ => tr('周日'),
};

/// "11月23日 周一" / "Mon, Nov 23"; the year appears when it is not this year.
String friendlyDate(String? iso, {bool weekday = true}) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final month = uiLanguage == UiLanguage.en ? _months[d.month - 1] : d.month;
  final date = d.year == DateTime.now().year
      ? tr('{month}月{day}日', {'month': month, 'day': d.day})
      : tr('{year}年{month}月{day}日', {
          'year': d.year,
          'month': month,
          'day': d.day,
        });
  if (!weekday) return date;
  return tr('{date} {weekday}', {'date': date, 'weekday': _weekday(d.weekday)});
}

String relativeDays(int days) => switch (days) {
  0 => tr('今天'),
  1 => tr('明天'),
  -1 => tr('昨天'),
  > 1 => tr('{n} 天后', {'n': days}),
  _ => tr('逾期 {n} 天', {'n': -days}),
};

String cycleLabel(Json? cycle) => switch (cycle?['kind']) {
  null => tr('无周期'),
  'once' => tr('单次'),
  'daily' => tr('每日'),
  'weekly' => tr('每周'),
  'monthly' => tr('每月'),
  'yearly' => tr('每年'),
  'interval' => tr('每 {n} 天', {'n': cycle!['days']}),
  'restart' => tr('完成后每 {n} 天', {'n': cycle!['days']}),
  'calendar' => tr('指定 {n} 个日期', {
    'n': (cycle!['dates'] as List?)?.length ?? 0,
  }),
  _ => '${cycle!['kind']}',
};

String reminderSummary(Json reminder) {
  final before = [...(reminder['before'] as List? ?? const [])]
    ..sort((a, b) => (b as int).compareTo(a as int));
  final grace = reminder['grace_days'] as int? ?? 0;
  final repeat = reminder['repeat_days'] as int?;
  final parts = [
    if (before.isNotEmpty)
      tr('提前 {days} 天', {
        // A single value keeps its number so English can choose "day".
        'days': before.length == 1 ? before.single : before.join(tr('、')),
      }),
    if (reminder['on_day'] == true) tr('当天'),
    if (grace > 0) tr('处理窗口 {n} 天', {'n': grace}),
    if (repeat != null) tr('每 {n} 天重复', {'n': repeat}),
  ];
  return parts.isEmpty ? tr('不提醒') : parts.join(' · ');
}

/// Verbs follow the unit so a count card says "使用" and money says "扣费".
(String add, String consume) resourceVerbs(String? kind) => switch (kind) {
  'money' => (tr('充值'), tr('扣费')),
  'count' => (tr('增加次数'), tr('使用')),
  _ => (tr('增加'), tr('消耗')),
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

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.push<T>(context, MaterialPageRoute<T>(builder: (_) => page));

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  String? label,
  String? helper,
  String? action,
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
              setState(
                () => error = tr('请填写{label}', {'label': label ?? tr('名称')}),
              );
              return;
            }
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(title, textAlign: TextAlign.center),
            content: TextField(
              autofocus: true,
              controller: controller,
              keyboardType: keyboard,
              decoration: InputDecoration(
                hintText: label ?? tr('名称'),
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
                child: Text(tr('取消')),
              ),
              TextButton(
                onPressed: submit,
                child: Text(
                  action ?? tr('确定'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
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
  String? action,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('取消')),
          ),
          TextButton(
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action ?? tr('确认'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ) ??
    false;

// ---------------------------------------------------------------------------
// Page skeleton: a large title that folds into a translucent bar on scroll,
// grouped content centered on wide screens and an optional bottom toolbar.
// ---------------------------------------------------------------------------
class SpanPage extends StatefulWidget {
  final String title;
  final Widget? subtitle;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Widget? toolbar;

  /// Usually an [AddButton]; it floats above the toolbar and the page keeps
  /// room below the last row so the button never covers it.
  final Widget? floatingActionButton;
  final double maxWidth;
  final Key? titleKey;
  final Future<void> Function()? onRefresh;
  const SpanPage({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.leading,
    this.leadingWidth,
    this.actions = const [],
    this.toolbar,
    this.floatingActionButton,
    this.maxWidth = 720,
    this.titleKey,
    this.onRefresh,
  });
  @override
  State<SpanPage> createState() => _SpanPageState();
}

class _SpanPageState extends State<SpanPage> {
  final scroll = ScrollController();
  bool collapsed = false;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      final next = scroll.offset > 34;
      if (next != collapsed) setState(() => collapsed = next);
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final plain = MediaQuery.highContrastOf(context);
    return Scaffold(
      backgroundColor: colors.background,
      extendBody: true,
      bottomNavigationBar: keyboard ? null : widget.toolbar,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final inset = math.max(
            gutter,
            (constraints.maxWidth - widget.maxWidth) / 2,
          );
          Widget view = CustomScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 52,
                leading: widget.leading,
                leadingWidth: widget.leadingWidth,
                backgroundColor: Colors.transparent,
                shape: collapsed
                    ? Border(bottom: BorderSide(color: colors.line, width: .7))
                    : null,
                // The flexible space gets loose constraints; expand so the
                // fill covers the whole bar instead of collapsing to zero.
                flexibleSpace: SizedBox.expand(
                  key: const ValueKey('page-bar-fill'),
                  child: collapsed && !plain
                      ? ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: ColoredBox(color: colors.bar),
                          ),
                        )
                      : ColoredBox(color: colors.background),
                ),
                title: AnimatedOpacity(
                  opacity: collapsed ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                actions: [...widget.actions, const SizedBox(width: 6)],
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset + 4, 0, inset + 4, 6),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    key: widget.titleKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          style: theme.textTheme.headlineLarge,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle.merge(
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.muted,
                          ),
                          child: widget.subtitle!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              for (final sliver in widget.slivers)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: sliver,
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      MediaQuery.paddingOf(context).bottom +
                      (widget.floatingActionButton == null ? 32 : 88),
                ),
              ),
            ],
          );
          if (widget.onRefresh != null) {
            view = RefreshIndicator(
              onRefresh: widget.onRefresh!,
              edgeOffset: MediaQuery.paddingOf(context).top + 52,
              child: view,
            );
          }
          final fab = widget.floatingActionButton;
          if (fab == null || keyboard) return view;
          // The body padding already covers this page's toolbar and, on the
          // tabs, the shell's dock; a Scaffold FAB would only clear the former.
          final padding = MediaQuery.paddingOf(context);
          return Stack(
            children: [
              Positioned.fill(child: view),
              Positioned(
                right: padding.right + 20,
                bottom: padding.bottom + 16,
                child: fab,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Plain box children as one sliver.
Widget boxes(List<Widget> children) => SliverList.list(children: children);

/// Translucent bottom bar: an optional leading tool, a quiet center caption
/// (usually the item count) and the primary compose action on the right.
class SpanToolbar extends StatelessWidget {
  final Widget? leading, center, trailing;
  const SpanToolbar({super.key, this.leading, this.center, this.trailing});
  @override
  Widget build(BuildContext context) {
    final colors = SpanColors.of(context);
    final plain = MediaQuery.highContrastOf(context);
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: plain ? colors.background : colors.bar,
        border: Border(top: BorderSide(color: colors.line, width: .7)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: leading ?? const SizedBox.shrink(),
                  ),
                ),
                if (center != null)
                  DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 12.5),
                    child: center!,
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return ClipRect(
      child: BackdropFilter(
        enabled: !plain,
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: bar,
      ),
    );
  }
}

/// The round add button at the bottom right of list pages. AQ uses the same
/// button with the same icon for adding content.
class AddButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String? tooltip;
  const AddButton({super.key, required this.onPressed, this.tooltip});
  @override
  Widget build(BuildContext context) => FloatingActionButton(
    // Several pages can show one at a time (tabs share a route).
    heroTag: null,
    tooltip: tooltip ?? tr('新建规则'),
    onPressed: onPressed,
    child: const Icon(Icons.add, size: 28),
  );
}

/// Rounded, filled search field in the style of a system search bar.
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String> onChanged;
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint,
  });
  @override
  Widget build(BuildContext context) {
    final colors = SpanColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: hint ?? tr('搜索'),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
            prefixIcon: Icon(Icons.search, size: 20, color: colors.muted),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: tr('清除搜索'),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: Icon(Icons.cancel, size: 18, color: colors.muted),
                  ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

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
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + media.viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 18),
            ...content,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
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
          color: c.withValues(alpha: .1),
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
// Grouped lists.
// ---------------------------------------------------------------------------

/// Section title. Lists use a bold title ("需要处理"); forms and settings use
/// a quiet caption above the card.
class SectionHeader extends StatelessWidget {
  final String text;
  final String? note;
  final Widget? trailing;
  final bool large;
  const SectionHeader(
    this.text, {
    super.key,
    this.note,
    this.trailing,
    this.large = true,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: large
          ? const EdgeInsets.fromLTRB(4, 22, 0, 8)
          : const EdgeInsets.fromLTRB(16, 22, 8, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  text: text,
                  children: [
                    if (note != null)
                      TextSpan(
                        text: '  $note',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: large
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.titleSmall,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Quiet explanation below a card.
class SectionFooter extends StatelessWidget {
  final String text;
  const SectionFooter(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// A single grouped card. Rows inside are separated by inset hairlines.
class Panel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double dividerIndent;
  const Panel({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.dividerIndent = 16,
  });
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && dividerIndent >= 0) {
        rows.add(Divider(indent: dividerIndent, height: 1));
      }
      rows.add(children[i]);
    }
    return Material(
      color: SpanColors.of(context).panel,
      borderRadius: BorderRadius.circular(12),
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

/// One row of a grouped card built lazily: it draws its own share of the
/// card (rounded at the ends) and the hairline below it.
class GroupedTile extends StatelessWidget {
  final Widget child;
  final bool first, last, selected;
  final VoidCallback? onTap;
  final void Function(Offset position)? onMenu;
  final double indent;
  const GroupedTile({
    super.key,
    required this.child,
    this.first = false,
    this.last = false,
    this.selected = false,
    this.onTap,
    this.onMenu,
    this.indent = 16,
  });
  @override
  Widget build(BuildContext context) {
    final colors = SpanColors.of(context);
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? 12 : 0),
      bottom: Radius.circular(last ? 12 : 0),
    );
    return Material(
      color: selected ? colors.soft : colors.panel,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onLongPressStart: onMenu == null
                ? null
                : (d) => onMenu!(d.globalPosition),
            onSecondaryTapDown: onMenu == null
                ? null
                : (d) => onMenu!(d.globalPosition),
            child: InkWell(onTap: onTap, child: child),
          ),
          if (!last) Divider(indent: indent, height: 1),
        ],
      ),
    );
  }
}

/// Builds grouped tiles for [items] with first/last flags.
List<Widget> groupedTiles<T>(
  List<T> items,
  Widget Function(T item, bool first, bool last) build,
) => [
  for (var i = 0; i < items.length; i++)
    build(items[i], i == 0, i == items.length - 1),
];

/// Settings-style row: label on the left, value and disclosure on the right.
class ValueRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? color, valueColor;
  const ValueRow(
    this.label, {
    super.key,
    this.value,
    this.trailing,
    this.icon,
    this.onTap,
    bool? chevron,
    this.color,
    this.valueColor,
  }) : chevron = chevron ?? onTap != null;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 22,
                    color: color ?? theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final labelText = Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: color,
                        ),
                      );
                      if (value == null || value!.isEmpty) return labelText;
                      // The label keeps its natural width (up to ~60%); the
                      // value takes the rest and hugs the trailing edge.
                      return Row(
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * .62,
                            ),
                            child: labelText,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              value!,
                              textAlign: TextAlign.end,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: valueColor ?? colors.muted,
                                fontFeatures: tabular,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                ?trailing,
                if (chevron)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.muted.withValues(alpha: .7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings-style switch row.
class SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Key? switchKey;
  const SwitchRow(
    this.label, {
    super.key,
    required this.value,
    required this.onChanged,
    this.switchKey,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Switch(key: switchKey, value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded square that carries a rule/category icon.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const IconTile(this.icon, {super.key, this.color, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Icon(icon, size: size * .58, color: c),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  const EmptyState(
    this.title, {
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colors.muted.withValues(alpha: .55)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Chip label that stays readable on the accent fill when selected.
class SpanChipLabel extends StatelessWidget {
  final String text;
  final bool selected;
  const SpanChipLabel(this.text, {super.key, required this.selected});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: selected
        ? TextStyle(color: Theme.of(context).colorScheme.onPrimary)
        : null,
  );
}

/// Positions a popup menu at a global point (long press or right click).
Future<T?> showMenuAt<T>(
  BuildContext context,
  Offset position,
  List<PopupMenuEntry<T>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// One row of a [showContextMenu] panel.
class MenuAction<T> {
  final T value;
  final String label;
  final IconData icon;
  final bool destructive, enabled;
  const MenuAction(
    this.value,
    this.label,
    this.icon, {
    this.destructive = false,
    this.enabled = true,
  });
}

/// Long-press / right-click menu: a frosted panel beside the press point with
/// the subject's name as a gray header, then groups of actions with the icon
/// in front. Put a destructive action in its own last group. AQ draws its
/// context menus with the same layout.
Future<T?> showContextMenu<T>(
  BuildContext context,
  Offset position, {
  String? title,
  required List<List<MenuAction<T>>> sections,
}) {
  HapticFeedback.selectionClick();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('关闭菜单'),
    barrierColor: Colors.black.withValues(alpha: .12),
    // Reduced motion: the menu fades in without growing.
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, _) {
      final media = MediaQuery.of(context);
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeIn,
      );
      return CustomSingleChildLayout(
        delegate: _ContextMenuLayout(position, media.padding),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(
              begin: media.disableAnimations ? 1.0 : .92,
              end: 1.0,
            ).animate(curved),
            child: _ContextMenuPanel<T>(title: title, sections: sections),
          ),
        ),
      );
    },
  );
}

class _ContextMenuLayout extends SingleChildLayoutDelegate {
  final Offset position;
  final EdgeInsets padding;
  const _ContextMenuLayout(this.position, this.padding);
  static const margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.min(260, constraints.maxWidth - margin * 2),
          constraints.maxHeight - padding.vertical - margin * 2,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    double place(double at, double extent, double min, double max) {
      // Open toward the free side of the press point, then keep it on screen.
      final start = at + extent > max ? at - extent : at;
      return start.clamp(min, math.max(min, max - extent));
    }

    return Offset(
      place(
        position.dx,
        child.width,
        padding.left + margin,
        size.width - padding.right - margin,
      ),
      place(
        position.dy,
        child.height,
        padding.top + margin,
        size.height - padding.bottom - margin,
      ),
    );
  }

  @override
  bool shouldRelayout(_ContextMenuLayout old) =>
      old.position != position || old.padding != padding;
}

class _ContextMenuPanel<T> extends StatelessWidget {
  final String? title;
  final List<List<MenuAction<T>>> sections;
  const _ContextMenuPanel({required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final contrast = MediaQuery.highContrastOf(context);
    final dark = theme.brightness == Brightness.dark;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: contrast ? colors.line : colors.line.withValues(alpha: .6),
        width: contrast ? 1 : .5,
      ),
    );
    final groups = [
      for (final s in sections)
        if (s.isNotEmpty) s,
    ];
    final rows = <Widget>[
      if (title != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 10),
          child: Text(
            title!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Divider(height: .5, thickness: .5, color: colors.line),
      ],
      for (final (g, group) in groups.indexed) ...[
        if (g > 0)
          ColoredBox(
            color: colors.line.withValues(alpha: .45),
            child: const SizedBox(height: 6),
          ),
        for (final (i, action) in group.indexed) ...[
          if (i > 0)
            Divider(
              height: .5,
              thickness: .5,
              indent: 48,
              color: colors.line.withValues(alpha: .7),
            ),
          _ContextMenuRow<T>(action),
        ],
      ],
    ];
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .35 : .1),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          enabled: !contrast,
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: colors.panel.withValues(alpha: contrast ? 1 : .86),
            shape: shape,
            child: IntrinsicWidth(
              stepWidth: 56,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextMenuRow<T> extends StatelessWidget {
  final MenuAction<T> action;
  const _ContextMenuRow(this.action);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = SpanColors.of(context).muted;
    final color = !action.enabled
        ? muted.withValues(alpha: .6)
        : action.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return InkWell(
      onTap: action.enabled
          ? () => Navigator.pop<T>(context, action.value)
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46, minWidth: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(action.icon, size: 20, color: color),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  action.label,
                  style: theme.textTheme.bodyLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menu row with an icon on the right, as in system context menus.
PopupMenuItem<T> menuItem<T>(
  T value,
  String label,
  IconData icon, {
  bool destructive = false,
  bool enabled = true,
  Key? key,
}) => PopupMenuItem<T>(
  key: key,
  value: value,
  enabled: enabled,
  child: Builder(
    builder: (context) {
      final color = destructive ? Theme.of(context).colorScheme.error : null;
      return Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
          const SizedBox(width: 16),
          Icon(icon, size: 20, color: color),
        ],
      );
    },
  ),
);
