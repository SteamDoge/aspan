// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'data.dart';
import 'design.dart';
import 'editor.dart';
import 'widgets.dart';

void openRule(BuildContext context, SpanStore store, String id) =>
    push(context, RuleDetail(store: store, id: id));
void openGroup(BuildContext context, SpanStore store, String id) =>
    push(context, GroupDetail(store: store, id: id));
void openAccount(
  BuildContext context,
  SpanStore store,
  String id, {
  String? rule,
}) => push(context, AccountDetail(store: store, id: id, rule: rule));

String statusLabel(String value) => switch (value) {
  'pending' => tr('待处理'),
  'processing' => tr('处理中'),
  'completed' => tr('已完成'),
  'skipped' => tr('已跳过'),
  'failed' => tr('已失败或放弃'),
  _ => value,
};
String actionLabel(String value) => switch (value) {
  'create_rule' => tr('创建规则'),
  'edit_rule' => tr('编辑规则'),
  'copy' => tr('完整复制'),
  'merge' => tr('合并规则'),
  'event' => tr('处理周期事件'),
  'resource' => tr('记录资源变化'),
  'correct_entry' => tr('纠正流水'),
  'delete_rule' => tr('删除规则'),
  'configure_account' => tr('账户设置'),
  _ => value,
};

/// Rust records event status in its enum spelling and fixed details in
/// Chinese; show both in the interface language.
String historyDetail(Json h) {
  final detail = h['detail'] as String? ?? '';
  if (detail.startsWith('{')) return '';
  return tr(detail)
      .replaceAll('Completed', statusLabel('completed'))
      .replaceAll('Processing', statusLabel('processing'))
      .replaceAll('Skipped', statusLabel('skipped'))
      .replaceAll('Failed', statusLabel('failed'))
      .replaceAll('Pending', statusLabel('pending'));
}

Widget historyRow(BuildContext context, Json h) {
  final detail = historyDetail(h);
  return ListTile(
    title: Text(actionLabel(h['action'] as String)),
    subtitle: Text(
      detail.isEmpty
          ? friendlyDate(h['date'] as String)
          : '${friendlyDate(h['date'] as String)} · $detail',
    ),
  );
}

List<Json> historyOf(SpanStore store, String id) =>
    (store.state['history'] as List)
        .map(object)
        .where((h) => h['subject'] == id)
        .toList()
        .reversed
        .toList();

/// A long record list on its own page, built lazily row by row.
class RecordsPage extends StatelessWidget {
  final String title;
  final SpanStore store;
  final List<Json> Function() items;
  final Widget Function(BuildContext, Json) row;
  final void Function(BuildContext, Json)? onTap;
  const RecordsPage({
    super.key,
    required this.title,
    required this.store,
    required this.items,
    required this.row,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final list = items();
      return SpanPage(
        title: title,
        subtitle: Text(tr('{n} 条', {'n': list.length})),
        slivers: [
          boxes([const SizedBox(height: 12)]),
          if (list.isEmpty)
            boxes([EmptyState(tr('暂无记录'), icon: Icons.history)])
          else
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => GroupedTile(
                first: i == 0,
                last: i == list.length - 1,
                onTap: onTap == null ? null : () => onTap!(context, list[i]),
                child: row(context, list[i]),
              ),
            ),
        ],
      );
    },
  );
}

class RuleDetail extends StatelessWidget {
  final SpanStore store;
  final String id;
  const RuleDetail({super.key, required this.store, required this.id});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final r = store.state['rules'][id];
      if (r == null || r['deleted'] == true) {
        return Scaffold(
          appBar: AppBar(),
          body: EmptyState(tr('规则已移入历史'), icon: Icons.history),
        );
      }
      final theme = Theme.of(context);
      final rule = object(r),
          v = store.view(id),
          aid = rule['account'] as String?;
      final phase = v['phase'] as String;
      final days = v['remaining_days'] as int?;
      final flagged = actionPhases.contains(phase) || phase == 'reminder';
      final accent = flagged
          ? phaseColor(context, phase)
          : theme.colorScheme.primary;
      final schedule = rule['schedule'] as Map?;
      final group = rule['group'] == null
          ? null
          : store.state['groups'][rule['group']];
      final project = rule['project'] == null
          ? null
          : store.state['projects'][rule['project']]?['name'];
      List<Json> occurrences() =>
          objects(store.state['occurrences'])
              .where((o) => o['rule'] == id)
              .toList()
            ..sort(
              (a, b) =>
                  b['planned'].toString().compareTo(a['planned'].toString()),
            );
      final occurrenceCount = occurrences().length;
      final historyCount = historyOf(store, id).length;
      final completeLabel = rule['reset'] != null
          ? tr('完成并恢复额度')
          : rule['change'] != null
          ? tr('完成并记账')
          : tr('完成本期');
      final graceDays = rule['reminder']['grace_days'] as int? ?? 0;
      final location = [
        project ?? tr('未归类'),
        for (final t in rule['tags'] as List)
          '#${store.state['tags'][t]?['name'] ?? ''}',
      ].join('  ');

      final children = <Widget>[
        const SizedBox(height: 12),
        if (v['planned'] != null)
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            dividerIndent: -1,
            children: [
              Text(
                relativeDays(days!),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: flagged ? accent : null,
                  fontFeatures: tabular,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (const ['reminder', 'grace', 'processing'].contains(phase))
                    phaseLabel(phase),
                  friendlyDate(v['planned'] as String),
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SpanColors.of(context).muted,
                ),
              ),
              const SizedBox(height: 16),
              TimelineBar(
                segments: v['segments'] == null ? null : object(v['segments']),
                progress: (v['time_progress'] as num? ?? 0).toDouble(),
                remainingDays: days,
                graceDays: graceDays,
                color: accent,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    tr('已过 {percent}%', {
                      'percent': (((v['time_progress'] as num?) ?? 0) * 100)
                          .round(),
                    }),
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      v['next_reminder'] == null
                          ? tr('本期无后续提醒')
                          : tr('下次提醒 {date}', {
                              'date': friendlyDate(
                                v['next_reminder'] as String,
                                weekday: false,
                              ),
                            }),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('complete-event'),
                      onPressed: () =>
                          eventSheet(context, store, rule, 'completed'),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(completeLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: SpanColors.of(context).fill,
                    borderRadius: BorderRadius.circular(12),
                    child: PopupMenuButton<String>(
                      key: const ValueKey('period-menu'),
                      tooltip: tr('本期其他处理'),
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      onSelected: (s) => eventSheet(context, store, rule, s),
                      itemBuilder: (_) => [
                        if (phase != 'processing')
                          menuItem(
                            'processing',
                            tr('标记处理中'),
                            Icons.pending_outlined,
                          ),
                        menuItem('skipped', tr('跳过本期'), Icons.redo_rounded),
                        menuItem('failed', tr('失败或放弃'), Icons.cancel_outlined),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          )
        else if (schedule != null)
          Callout(tr('周期已结束'), icon: Icons.event_busy_outlined),
        if (schedule != null) ...[
          SectionHeader(tr('周期'), large: false),
          Panel(
            children: [
              ValueRow(tr('重复'), value: cycleLabel(object(schedule['cycle']))),
              ValueRow(
                tr('提醒'),
                value: reminderSummary(object(rule['reminder'])),
              ),
              ValueRow(
                tr('起算'),
                value: friendlyDate(
                  schedule['anchor'] as String?,
                  weekday: false,
                ),
              ),
            ],
          ),
        ],
        if (group != null) ...[
          SectionHeader(tr('合并条目'), large: false),
          Panel(
            children: [
              ValueRow(
                group['name'] as String,
                icon: Icons.layers_outlined,
                onTap: () => openGroup(context, store, group['id'] as String),
              ),
            ],
          ),
        ],
        if (aid != null) ...[
          SectionHeader(group == null ? tr('资源') : tr('共享资源'), large: false),
          ResourceCard(store: store, account: aid, rule: id),
        ],
        if ((rule['notes'] as String).isNotEmpty) ...[
          SectionHeader(tr('备注'), large: false),
          Panel(
            padding: const EdgeInsets.all(16),
            children: [
              SelectableText(
                rule['notes'] as String,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ],
        SectionHeader(tr('记录'), large: false),
        Panel(
          children: [
            ValueRow(
              tr('周期记录'),
              key: const ValueKey('open-occurrences'),
              value: '$occurrenceCount',
              onTap: () => push(
                context,
                RecordsPage(
                  title: tr('周期记录'),
                  store: store,
                  items: occurrences,
                  row: occurrenceRow,
                ),
              ),
            ),
            ValueRow(
              tr('操作历史'),
              key: const ValueKey('open-history'),
              value: '$historyCount',
              onTap: () => push(
                context,
                RecordsPage(
                  title: tr('操作历史'),
                  store: store,
                  items: () => historyOf(store, id),
                  row: historyRow,
                ),
              ),
            ),
          ],
        ),
      ];
      return SpanPage(
        title: rule['name'] as String,
        subtitle: Text(location),
        maxWidth: 680,
        actions: [
          TextButton(
            key: const ValueKey('edit-rule'),
            onPressed: () => openCreator(context, store, rule: rule),
            child: Text(tr('编辑')),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('rule-menu'),
            tooltip: tr('更多'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) => switch (action) {
              'copy' => copyEntry(context, store, id),
              'move' => perform(context, () => moveEntry(context, store, rule)),
              'template' => saveAsTemplate(context, store, rule),
              'delete' => deleteRule(context, store, id),
              _ => null,
            },
            itemBuilder: (_) => [
              menuItem('copy', tr('完整复制'), Icons.copy_outlined),
              menuItem('template', tr('存为模板'), Icons.bookmark_add_outlined),
              if (group == null)
                menuItem('move', tr('移动到…'), Icons.folder_outlined),
              const PopupMenuDivider(),
              menuItem(
                'delete',
                tr('删除规则'),
                Icons.delete_outline,
                destructive: true,
              ),
            ],
          ),
        ],
        slivers: [boxes(children)],
      );
    },
  );
}

Widget occurrenceRow(BuildContext context, Json o) {
  final status = o['status'] as String;
  final color = switch (status) {
    'completed' => successColor(context),
    'processing' => warningColor(context),
    'failed' => Theme.of(context).colorScheme.error,
    _ => SpanColors.of(context).muted,
  };
  final icon = switch (status) {
    'completed' => Icons.check_circle,
    'processing' => Icons.pending,
    'skipped' => Icons.redo_rounded,
    'failed' => Icons.cancel,
    _ => Icons.radio_button_unchecked,
  };
  final windowEnd = o['window_end'] != o['planned'];
  final detail = [
    if (o['actual'] != null)
      tr('实际 {date}', {
        'date': friendlyDate(o['actual'] as String, weekday: false),
      }),
    if (o['completed'] != null)
      tr('处理于 {date}', {
        'date': friendlyDate(o['completed'] as String, weekday: false),
      }),
    if (windowEnd)
      tr('窗口至 {date}', {
        'date': friendlyDate(o['window_end'] as String, weekday: false),
      }),
  ].join(' · ');
  return ListTile(
    leading: Icon(icon, color: color, size: 22),
    title: Text(friendlyDate(o['planned'] as String)),
    subtitle: Text(
      detail.isEmpty ? statusLabel(status) : '${statusLabel(status)} · $detail',
    ),
  );
}

/// Long-press / right-click actions for a rule row.
Future<void> ruleMenu(
  BuildContext context,
  SpanStore store,
  Json rule,
  Offset position, {
  VoidCallback? onSelect,
}) async {
  final id = rule['id'] as String;
  final planned = store.view(id)['planned'];
  final action = await showContextMenu<String>(
    context,
    position,
    title: rule['name'] as String?,
    sections: [
      [
        if (planned != null)
          MenuAction('complete', tr('完成本期'), Icons.check_circle_outline),
        MenuAction('copy', tr('完整复制'), Icons.copy_outlined),
        if (onSelect != null)
          MenuAction('select', tr('选择'), Icons.checklist_rounded),
      ],
      [
        if (rule['group'] == null)
          MenuAction('move', tr('移动到…'), Icons.drive_file_move_outlined),
      ],
      [MenuAction('delete', tr('删除'), Icons.delete_outline, destructive: true)],
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'complete':
      await eventSheet(context, store, rule, 'completed');
    case 'move':
      await perform(context, () => moveEntry(context, store, rule));
    case 'copy':
      await copyEntry(context, store, id);
    case 'select':
      onSelect?.call();
    case 'delete':
      await deleteRule(context, store, id, leave: false);
  }
}

/// Long-press / right-click actions for a merged entry row.
Future<void> groupMenu(
  BuildContext context,
  SpanStore store,
  Json group,
  Offset position,
) async {
  final id = group['id'] as String;
  final action = await showContextMenu<String>(
    context,
    position,
    title: group['name'] as String?,
    sections: [
      [
        MenuAction('open', tr('打开'), Icons.layers_outlined),
        MenuAction('copy', tr('完整复制'), Icons.copy_outlined),
      ],
      [MenuAction('move', tr('移动到…'), Icons.drive_file_move_outlined)],
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      openGroup(context, store, id);
    case 'move':
      await perform(context, () => moveEntry(context, store, object(group)));
    case 'copy':
      await copyEntry(context, store, id);
  }
}

Future<void> copyEntry(BuildContext context, SpanStore store, String id) async {
  final isGroup = store.state['groups'][id] != null;
  try {
    final response = await store.mutate('copy', {'id': id});
    if (!context.mounted) return;
    final copy = response['result'] as String;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isGroup ? tr('已复制全部成员、账户与历史') : tr('已完整复制，副本拥有独立账户与历史'),
          ),
          action: SnackBarAction(
            label: tr('查看'),
            onPressed: () => isGroup
                ? openGroup(context, store, copy)
                : openRule(context, store, copy),
          ),
        ),
      );
  } catch (error) {
    if (context.mounted) notify(context, errorMessage(error));
  }
}

Future<void> deleteRule(
  BuildContext context,
  SpanStore store,
  String id, {
  bool leave = true,
}) => perform(context, () async {
  final baseRevision = store.revision;
  if (!await confirm(
    context,
    tr('删除这条规则？'),
    tr('已发生的流水会保留。此操作无法撤销。'),
    action: tr('删除'),
    destructive: true,
  )) {
    return;
  }
  await store.mutate('delete_rule', {'id': id}, baseRevision: baseRevision);
  if (context.mounted) {
    if (leave) Navigator.pop(context);
    notify(context, tr('规则已删除，流水保留'));
  }
});

/// Asks first: a cancelled dialog writes nothing and reports nothing.
Future<void> saveAsTemplate(
  BuildContext context,
  SpanStore store,
  Json rule,
) async {
  final baseRevision = store.revision;
  final name = await askText(
    context,
    tr('存为我的模板'),
    initial: rule['name'] as String,
    label: tr('模板名称'),
    action: tr('保存'),
  );
  if (name == null || !context.mounted) return;
  await perform(context, () async {
    final aid = rule['account'] as String?;
    final precision = aid == null
        ? 0
        : store.state['accounts'][aid]['unit']['precision'] as int;
    final config = object(rule)
      ..remove('id')
      ..remove('group')
      ..remove('account')
      ..remove('order')
      ..remove('deleted');
    config['change'] = rule['change'] == null
        ? null
        : formatUnits(rule['change'] as int, precision);
    config['reset'] = rule['reset'] == null
        ? null
        : formatUnits(rule['reset'] as int, precision);
    if (aid != null) {
      final ac = store.state['accounts'][aid];
      config['new_account'] = {
        'name': name,
        'unit': ac['unit'],
        'initial': '0',
        'reference': ac['reference'] == null
            ? null
            : formatUnits(ac['reference'] as int, precision),
        'low': ac['low'] == null
            ? null
            : formatUnits(ac['low'] as int, precision),
      };
    }
    await store.mutate('save_template', {
      'name': name,
      'config': config,
    }, baseRevision: baseRevision);
  }, success: tr('已存为模板，新建规则时可直接使用'));
}

/// One sheet for every period decision; shows exactly what will be recorded.
Future<void> eventSheet(
  BuildContext context,
  SpanStore store,
  Json rule,
  String status,
) async {
  final baseRevision = store.revision;
  final planned = store.view(rule['id'] as String)['planned'] as String?;
  if (planned == null) return;
  final today = DateTime.now();
  final anchor = DateTime.parse(rule['schedule']['anchor'] as String);
  if (dateOnly(today).compareTo(dateOnly(anchor)) < 0) {
    notify(context, tr('周期尚未开始；请在起点当天之后处理，或先编辑起点'));
    return;
  }
  final aid = rule['account'] as String?;
  final account = aid == null ? null : store.state['accounts'][aid];
  final unit = unitLabel(account?['unit']['code'] as String? ?? '');
  final precision = account?['unit']['precision'] as int? ?? 0;
  final change = rule['change'] as int?, reset = rule['reset'] as int?;
  final effect = account == null
      ? null
      : reset != null
      ? tr('同时恢复额度到 {amount} {unit}', {
          'amount': formatUnits(reset, precision),
          'unit': unit,
        })
      : change != null
      ? tr('同时记录 {amount} {unit}', {
          'amount': '${change > 0 ? '+' : ''}${formatUnits(change, precision)}',
          'unit': unit,
        })
      : null;
  String actual = dateOnly(today);
  bool record = true;
  bool busy = false;
  String? error;
  final (title, action) = switch (status) {
    'completed' => (tr('完成本期'), tr('完成')),
    'processing' => (tr('标记处理中'), tr('标记处理中')),
    'skipped' => (tr('跳过本期'), tr('跳过')),
    _ => (tr('失败或放弃'), tr('确认放弃')),
  };
  final accepted = await showSpanSheet<bool>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) => SheetBody(
        title: title,
        subtitle: '${rule['name']} · ${friendlyDate(planned)}',
        content: [
          if (error != null) ...[
            Callout(
              error!,
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
          ],
          if (status == 'completed')
            Panel(
              children: [
                ListTile(
                  key: const ValueKey('actual-date'),
                  title: Text(tr('实际发生日期')),
                  trailing: Text(
                    actual == dateOnly(today) ? tr('今天') : friendlyDate(actual),
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onTap: busy
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(actual),
                            firstDate: anchor,
                            lastDate: today,
                          );
                          if (d != null && context.mounted) {
                            setState(() => actual = dateOnly(d));
                          }
                        },
                ),
                if (effect != null)
                  SwitchListTile(
                    title: Text(effect),
                    value: record,
                    onChanged: busy ? null : (v) => setState(() => record = v),
                  ),
              ],
            )
          else if (effect != null && status != 'processing')
            SectionFooter(tr('不产生资源流水。')),
        ],
        actions: [
          OutlinedButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            key: const ValueKey('confirm-event'),
            onPressed: busy
                ? null
                : () async {
                    if (busy) return;
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await store.mutate('event', {
                        'rule': rule['id'],
                        'planned': planned,
                        'actual': actual,
                        'status': status,
                        'record': record,
                      }, baseRevision: baseRevision);
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() {
                          busy = false;
                          error = errorMessage(e);
                        });
                      }
                    }
                  },
            child: Text(busy ? tr('正在保存…') : action),
          ),
        ],
      ),
    ),
  );
  if (accepted == true && context.mounted) {
    final next = store.view(rule['id'] as String)['planned'] as String?;
    notify(
      context,
      status == 'processing'
          ? tr('已标记处理中')
          : next == null
          ? tr('本期已结束，没有下一期')
          : tr('本期已结束 · 下次 {date}', {'date': friendlyDate(next)}),
    );
  }
}

/// Balance summary with the two most common operations inline.
class ResourceCard extends StatelessWidget {
  final SpanStore store;
  final String account;
  final String? rule;
  const ResourceCard({
    super.key,
    required this.store,
    required this.account,
    this.rule,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final ac = store.state['accounts'][account];
    final v = store.accountView(account);
    final p = ac['unit']['precision'] as int;
    final (add, consume) = resourceVerbs(ac['unit']['kind'] as String?);
    return Panel(
      dividerIndent: -1,
      children: [
        InkWell(
          onTap: () => openAccount(context, store, account, rule: rule),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ac['name'] as String,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: v['formatted'] as String,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontSize: 26,
                                fontFeatures: tabular,
                                color: v['low'] == true
                                    ? warningColor(context)
                                    : null,
                              ),
                            ),
                            TextSpan(
                              text: '  ${unitLabel(v['unit'])}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(tr('明细'), style: theme.textTheme.bodySmall),
                Icon(Icons.chevron_right, color: colors.muted),
              ],
            ),
          ),
        ),
        if (v['progress'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (v['progress'] as num).toDouble(),
                  color: v['low'] == true ? warningColor(context) : null,
                ),
                const SizedBox(height: 6),
                Text(
                  tr('剩余 {percent}% · 参考总量 {total}', {
                    'percent': ((v['progress'] as num) * 100).round(),
                    'total': formatUnits(ac['reference'] as int, p),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (v['low'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              tr('已低于提醒阈值 {amount} {unit}', {
                'amount': formatUnits(ac['low'] as int, p),
                'unit': unitLabel(v['unit']),
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: warningColor(context),
              ),
            ),
          ),
        if (ac['archived'] != true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        resourceSheet(context, store, account, 'add', rule),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(add),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        resourceSheet(context, store, account, 'consume', rule),
                    icon: const Icon(Icons.remove, size: 18),
                    label: Text(consume),
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: 6),
      ],
    );
  }
}

class GroupDetail extends StatelessWidget {
  final SpanStore store;
  final String id;
  const GroupDetail({super.key, required this.store, required this.id});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final g = store.state['groups'][id];
      if (g == null || g['deleted'] == true) {
        return Scaffold(
          appBar: AppBar(),
          body: EmptyState(
            tr('合并条目已变回普通规则'),
            icon: Icons.layers_clear_outlined,
          ),
        );
      }
      final members = store.ordered(
        store.rules.where((r) => r['group'] == id).toList(),
      );
      final project = g['project'] == null
          ? tr('未归类')
          : store.state['projects'][g['project']]?['name'] ?? tr('未归类');
      final tags = [
        for (final tid in store.snapshot['group_tags'][id] as List)
          '#${store.state['tags'][tid]['name']}',
      ];
      final historyCount = historyOf(store, id).length;
      final children = <Widget>[
        if ((g['accounts'] as List).isNotEmpty) ...[
          SectionHeader(tr('共享资源'), large: false),
          for (final aid in g['accounts'] as List) ...[
            ResourceCard(store: store, account: aid as String),
            const SizedBox(height: 8),
          ],
        ],
        SectionHeader(tr('成员'), note: '${members.length}', large: false),
        ...groupedTiles(
          members,
          (r, f, l) => RuleRow(
            store: store,
            rule: r,
            first: f,
            last: l,
            onTap: () => openRule(context, store, r['id'] as String),
          ),
        ),
        if ((g['archived_accounts'] as List).isNotEmpty) ...[
          SectionHeader(tr('合并前账本'), large: false),
          Panel(
            children: [
              for (final aid in g['archived_accounts'] as List)
                ValueRow(
                  store.state['accounts'][aid]['name'] as String,
                  value:
                      '${store.accountView(aid as String)['formatted']} ${unitLabel(store.accountView(aid)['unit'])}',
                  onTap: () => openAccount(context, store, aid),
                ),
            ],
          ),
          SectionFooter(tr('不计入共享余额。')),
        ],
        SectionHeader(tr('记录'), large: false),
        Panel(
          children: [
            ValueRow(
              tr('操作历史'),
              value: '$historyCount',
              onTap: () => push(
                context,
                RecordsPage(
                  title: tr('操作历史'),
                  store: store,
                  items: () => historyOf(store, id),
                  row: historyRow,
                ),
              ),
            ),
          ],
        ),
      ];
      return SpanPage(
        title: g['name'] as String,
        subtitle: Text([project, ...tags].join('  ')),
        maxWidth: 680,
        actions: [
          PopupMenuButton<String>(
            tooltip: tr('更多'),
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) => switch (action) {
              'rename' => perform(context, () async {
                final baseRevision = store.revision;
                final name = await askText(
                  context,
                  tr('重命名合并条目'),
                  initial: g['name'] as String,
                  action: tr('保存'),
                );
                if (name != null) {
                  await store.mutate('rename_group', {
                    'id': id,
                    'name': name,
                  }, baseRevision: baseRevision);
                }
              }),
              'move' => perform(
                context,
                () => moveEntry(context, store, object(g)),
              ),
              'copy' => copyEntry(context, store, id),
              'split' => splitGuide(context, store, id),
              _ => null,
            },
            itemBuilder: (_) => [
              menuItem('rename', tr('重命名'), Icons.drive_file_rename_outline),
              menuItem('move', tr('移动到…'), Icons.folder_outlined),
              menuItem('copy', tr('完整复制'), Icons.copy_outlined),
              menuItem('split', tr('如何拆分'), Icons.call_split),
            ],
          ),
        ],
        slivers: [boxes(children)],
      );
    },
  );
}

/// Splitting is deliberately composed from copy + delete so that both halves
/// keep complete, independent ledgers. Guide the user instead of hiding it.
Future<void> splitGuide(
  BuildContext context,
  SpanStore store,
  String id,
) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('拆分合并条目'), textAlign: TextAlign.center),
      content: Text(
        tr(
          '1. 完整复制此合并条目\n2. 在原条目中删除不需要的成员\n3. 在副本中删除另一部分成员\n\n只剩一个成员时会自动变回普通规则，余额与流水保留。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('关闭')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            tr('完整复制'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) await copyEntry(context, store, id);
}

class AccountDetail extends StatelessWidget {
  final SpanStore store;
  final String id;
  final String? rule;
  const AccountDetail({
    super.key,
    required this.store,
    required this.id,
    this.rule,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = SpanColors.of(context);
      final ac = store.state['accounts'][id],
          v = store.accountView(id),
          p = ac['unit']['precision'] as int;
      final archived = ac['archived'] == true;
      final (add, consume) = resourceVerbs(ac['unit']['kind'] as String?);
      final users = store.rules.where((r) => r['account'] == id).toList();
      final entries =
          objects(store.state['ledger'])
              .where((e) => e['account'] == id)
              .toList()
            ..sort((a, b) {
              final c = b['date'].toString().compareTo(a['date'].toString());
              return c == 0
                  ? a['id'].toString().compareTo(b['id'].toString())
                  : c;
            });
      final unit = unitLabel(v['unit']);
      final facts = [
        if (v['progress'] != null)
          tr('剩余 {percent}% · 参考总量 {total} {unit}', {
            'percent': ((v['progress'] as num) * 100).round(),
            'total': formatUnits(ac['reference'] as int, p),
            'unit': unit,
          }),
        if (ac['low'] != null)
          v['low'] == true
              ? tr('低于 {amount} {unit} 时提醒 · 已低于', {
                  'amount': formatUnits(ac['low'] as int, p),
                  'unit': unit,
                })
              : tr('低于 {amount} {unit} 时提醒', {
                  'amount': formatUnits(ac['low'] as int, p),
                  'unit': unit,
                }),
        if (users.length > 1)
          tr('共享：{names}', {'names': users.map((r) => r['name']).join(tr('、'))})
        else if (users.isNotEmpty)
          tr('关联：{names}', {'names': users.single['name']}),
      ];
      final hero = Panel(
        padding: const EdgeInsets.all(16),
        dividerIndent: -1,
        children: [
          Text(
            archived ? tr('归档账本 · 不计入当前共享余量') : tr('当前余量'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: v['formatted'] as String,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 36,
                    fontFeatures: tabular,
                    color: v['low'] == true ? warningColor(context) : null,
                  ),
                ),
                TextSpan(
                  text: '  $unit',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (v['progress'] != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (v['progress'] as num).toDouble(),
              minHeight: 6,
              color: v['low'] == true ? warningColor(context) : null,
            ),
          ],
          for (final f in facts) ...[
            const SizedBox(height: 6),
            Text(f, style: theme.textTheme.bodySmall),
          ],
          if (!archived) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        resourceSheet(context, store, id, 'add', rule),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(add),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        resourceSheet(context, store, id, 'consume', rule),
                    icon: const Icon(Icons.remove, size: 18),
                    label: Text(consume),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(12),
                  child: PopupMenuButton<String>(
                    tooltip: tr('更多账户操作'),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    onSelected: (value) => value == 'set'
                        ? resourceSheet(context, store, id, 'set', rule)
                        : forecastSheet(context, store, id),
                    itemBuilder: (_) => [
                      menuItem('set', tr('修正当前余量'), Icons.tune),
                      menuItem('forecast', tr('查看预测'), Icons.insights_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      );
      return SpanPage(
        title: ac['name'] as String,
        maxWidth: 680,
        actions: [
          if (!archived)
            IconButton(
              tooltip: tr('账户设置'),
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => accountOptionsSheet(context, store, object(ac)),
            ),
        ],
        slivers: [
          boxes([
            const SizedBox(height: 12),
            hero,
            SectionHeader(tr('流水'), note: '${entries.length}', large: false),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(tr('暂无流水。'), style: theme.textTheme.bodySmall),
              ),
          ]),
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => GroupedTile(
              first: i == 0,
              last: i == entries.length - 1,
              onTap: () => entrySheet(
                context,
                store,
                entries[i],
                p,
                v['unit'] as String,
              ),
              child: ledgerRow(context, store, entries[i], p),
            ),
          ),
        ],
      );
    },
  );
}

/// The user's note; fixed notes written by the core are translated.
String entryNote(Json entry) {
  final note = entry['note'] as String;
  return entry['source'] == 'manual'
      ? note.replaceFirst(RegExp(r'^(add|consume|set):-?\d+:'), '')
      : tr(note);
}

String sourceLabel(String source) => switch (source) {
  'initial' => tr('初始基准'),
  'manual' => tr('手动记录'),
  'confirmed' => tr('事件确认'),
  'correction' => tr('纠正替代'),
  'correction_reverse' => tr('纠正反向'),
  _ => source,
};

Widget ledgerRow(BuildContext context, SpanStore store, Json e, int precision) {
  final delta = e['delta'] as int;
  final corrected = e['corrected_by'] != null;
  final note = entryNote(e);
  final rule = e['rule'] == null ? null : store.state['rules'][e['rule']];
  final muted = SpanColors.of(context).muted;
  return ListTile(
    title: Text(
      note.isNotEmpty ? note : sourceLabel(e['source'] as String),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: corrected
          ? TextStyle(decoration: TextDecoration.lineThrough, color: muted)
          : null,
    ),
    subtitle: Text(
      [
        friendlyDate(e['date'] as String, weekday: false),
        if (note.isNotEmpty) sourceLabel(e['source'] as String),
        if (rule != null) rule['name'],
        if (corrected) tr('已纠正'),
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(
      '${delta > 0 ? '+' : ''}${formatUnits(delta, precision)}',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
        color: corrected
            ? muted
            : delta >= 0
            ? successColor(context)
            : null,
      ),
    ),
  );
}

Future<void> entrySheet(
  BuildContext context,
  SpanStore store,
  Json e,
  int precision,
  String unit,
) async {
  final delta = e['delta'] as int;
  final correctable =
      e['corrected_by'] == null && e['source'] != 'correction_reverse';
  final rule = e['rule'] == null ? null : store.state['rules'][e['rule']];
  final correct = await showSpanSheet<bool>(
    context,
    (context) => SheetBody(
      title:
          '${delta > 0 ? '+' : ''}${formatUnits(delta, precision)} ${unitLabel(unit)}',
      subtitle:
          '${friendlyDate(e['date'] as String)} · ${sourceLabel(e['source'] as String)}',
      content: [
        Panel(
          children: [
            if (entryNote(e).isNotEmpty)
              ValueRow(tr('备注'), value: entryNote(e)),
            if (rule != null)
              ValueRow(tr('关联规则'), value: rule['name'] as String),
            if (e['origin'] != null)
              ValueRow(tr('来源记录'), value: '${e['origin']}'),
            if (e['corrected_by'] != null) ListTile(title: Text(tr('已纠正'))),
            if (e['source'] == 'correction_reverse')
              ListTile(
                title: Text(tr('系统反向流水')),
                subtitle: Text(tr('不能再次纠正；如需更改，请纠正对应的替代流水')),
              ),
            if (entryNote(e).isEmpty &&
                rule == null &&
                e['origin'] == null &&
                correctable)
              ListTile(title: Text(tr('没有附加信息'))),
          ],
        ),
      ],
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('关闭')),
        ),
        if (correctable)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('纠正此流水')),
          ),
      ],
    ),
  );
  if (correct == true && context.mounted) {
    await correctSheet(context, store, e, precision, unit);
  }
}

/// Shared form state for sheets that commit inside the sheet, so a failure
/// keeps the user's input on screen next to the error.
class _SheetForm extends StatefulWidget {
  /// key, label, initial value, required.
  final List<(String, String, String, bool)> fields;
  final String title, action;
  final String? subtitle, note, suffix;
  final Future<String?> Function(Map<String, String>) submit;
  const _SheetForm({
    required this.fields,
    required this.title,
    required this.action,
    required this.submit,
    this.subtitle,
    this.note,
    this.suffix,
  });
  @override
  State<_SheetForm> createState() => _SheetFormState();
}

class _SheetFormState extends State<_SheetForm> {
  late final controllers = {
    for (final f in widget.fields) f.$1: TextEditingController(text: f.$3),
  };
  bool busy = false;
  final errors = <String, String?>{};
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run() async {
    if (busy) return;
    final values = {
      for (final e in controllers.entries) e.key: e.value.text.trim(),
    };
    errors.clear();
    for (final f in widget.fields) {
      if (f.$4 && values[f.$1]!.isEmpty) {
        errors[f.$1] = tr('请填写{label}', {'label': f.$2});
      }
    }
    if (errors.isNotEmpty) {
      setState(() {});
      return;
    }
    setState(() => busy = true);
    try {
      final message = await widget.submit(values);
      if (mounted) Navigator.pop(context, message);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          errors[widget.fields.first.$1] = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = SpanColors.of(context).panel;
    return SheetBody(
      title: widget.title,
      subtitle: widget.subtitle,
      content: [
        for (var i = 0; i < widget.fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          TextField(
            key: ValueKey('sheet-${widget.fields[i].$1}'),
            controller: controllers[widget.fields[i].$1],
            autofocus: i == 0,
            keyboardType: i == 0 && widget.suffix != null
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : TextInputType.text,
            style: i == 0 && widget.suffix != null
                ? const TextStyle(fontSize: 20, fontFeatures: tabular)
                : null,
            decoration: InputDecoration(
              labelText: widget.fields[i].$2,
              fillColor: panel,
              suffixText: i == 0 ? widget.suffix : null,
              errorText: errors[widget.fields[i].$1],
            ),
            onChanged: (_) {
              if (errors.isNotEmpty) setState(errors.clear);
            },
            onSubmitted: (_) => run(),
          ),
        ],
        if (widget.note != null) SectionFooter(widget.note!),
      ],
      actions: [
        OutlinedButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        FilledButton(
          key: const ValueKey('sheet-submit'),
          onPressed: busy ? null : run,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.action),
        ),
      ],
    );
  }
}

Future<void> resourceSheet(
  BuildContext context,
  SpanStore store,
  String aid,
  String action,
  String? rule,
) async {
  final baseRevision = store.revision;
  // One key per opened sheet: a retried or double submit replays, never doubles.
  final key = operationKey();
  final ac = store.state['accounts'][aid];
  final v = store.accountView(aid);
  final (add, consume) = resourceVerbs(ac['unit']['kind'] as String?);
  final title = switch (action) {
    'add' => add,
    'consume' => consume,
    _ => tr('修正当前余量'),
  };
  final unit = unitLabel(v['unit']);
  final message = await showSpanSheet<String>(
    context,
    (_) => _SheetForm(
      title: title,
      subtitle: tr('{name} · 当前 {amount} {unit}', {
        'name': ac['name'],
        'amount': v['formatted'],
        'unit': unit,
      }),
      action: action == 'set' ? tr('修正') : title,
      suffix: unit,
      note: action == 'set' ? tr('将追加一条差额流水使余量等于输入值；原有流水保留。') : null,
      fields: [
        (
          'amount',
          action == 'set' ? tr('正确的当前余量') : tr('数量'),
          action == 'consume' && ac['unit']['kind'] == 'count' ? '1' : '',
          true,
        ),
        ('note', tr('备注（可选）'), '', false),
      ],
      submit: (values) async {
        await store.mutate('resource', {
          'account': aid,
          'rule': rule,
          'action': action,
          'amount': values['amount'],
          'key': key,
          if (values['note']!.isNotEmpty) 'note': values['note'],
        }, baseRevision: baseRevision);
        final now = store.accountView(aid);
        return tr('已记录 · 当前 {amount} {unit}', {
          'amount': now['formatted'],
          'unit': unitLabel(now['unit']),
        });
      },
    ),
  );
  if (message != null && context.mounted) notify(context, message);
}

Future<void> correctSheet(
  BuildContext context,
  SpanStore store,
  Json entry,
  int precision,
  String unit,
) async {
  final baseRevision = store.revision;
  final message = await showSpanSheet<String>(
    context,
    (_) => _SheetForm(
      title: tr('纠正流水'),
      subtitle: tr('原记录 {amount} {unit} · {date}', {
        'amount': formatUnits(entry['delta'] as int, precision),
        'unit': unitLabel(unit),
        'date': friendlyDate(entry['date'] as String),
      }),
      action: tr('提交纠正'),
      suffix: unitLabel(unit),
      note: tr('原流水保留，将追加一条反向流水和一条替代流水。'),
      fields: [
        (
          'delta',
          tr('正确的变化值（扣减为负数）'),
          formatUnits(entry['delta'] as int, precision),
          true,
        ),
        ('reason', tr('纠正原因'), '', true),
      ],
      submit: (values) async {
        await store.mutate('correct_entry', {
          'id': entry['id'],
          'delta': values['delta'],
          'reason': values['reason'],
        }, baseRevision: baseRevision);
        return tr('已纠正，原记录保留');
      },
    ),
  );
  if (message != null && context.mounted) notify(context, message);
}

Future<void> forecastSheet(
  BuildContext context,
  SpanStore store,
  String id,
) => perform(context, () async {
  final forecast = await store.read('forecast', {'account': id});
  if (!context.mounted) return;
  final unit = unitLabel(store.accountView(id)['unit']);
  await showSpanSheet<void>(
    context,
    (context) => SheetBody(
      title: tr('余量预测'),
      subtitle: tr('预测只读，不会记账。'),
      content: [
        if ((forecast['events'] as List).isEmpty)
          Callout(tr('没有固定的扣费或恢复计划，无法估算。'))
        else
          Panel(
            children: [
              for (final e in forecast['events'] as List)
                ListTile(
                  title: Text(
                    '${friendlyDate(e['planned'] as String)} · ${store.state['rules'][e['rule']]?['name'] ?? ''}',
                  ),
                  subtitle: Text(
                    tr('变化 {delta} {unit} · 预计余量 {balance} {unit}', {
                      'delta': e['delta'],
                      'balance': e['balance'],
                      'unit': unit,
                    }),
                  ),
                  trailing: e['insufficient'] == true
                      ? Text(
                          tr('可能不足'),
                          style: TextStyle(color: warningColor(context)),
                        )
                      : null,
                ),
            ],
          ),
      ],
    ),
  );
});

Future<void> accountOptionsSheet(
  BuildContext context,
  SpanStore store,
  Json account,
) async {
  final baseRevision = store.revision;
  final p = account['unit']['precision'] as int;
  final message = await showSpanSheet<String>(
    context,
    (_) => _SheetForm(
      title: tr('账户设置'),
      action: tr('保存'),
      fields: [
        ('name', tr('账户名称'), account['name'] as String, true),
        (
          'reference',
          tr('参考总量（可留空）'),
          account['reference'] == null
              ? ''
              : formatUnits(account['reference'] as int, p),
          false,
        ),
        (
          'low',
          tr('低于此值时提醒（可留空）'),
          account['low'] == null ? '' : formatUnits(account['low'] as int, p),
          false,
        ),
      ],
      submit: (values) async {
        await store.mutate('configure_account', {
          'id': account['id'],
          'name': values['name'],
          'reference': values['reference']!.isEmpty
              ? null
              : values['reference'],
          'low': values['low']!.isEmpty ? null : values['low'],
        }, baseRevision: baseRevision);
        return tr('账户设置已保存');
      },
    ),
  );
  if (message != null && context.mounted) notify(context, message);
}

Future<void> moveEntry(
  BuildContext context,
  SpanStore store,
  Json entry,
) async {
  final baseRevision = store.revision;
  if (entry['group'] != null) {
    notify(context, tr('成员随所属合并条目一起移动，请在合并条目中操作'));
    return;
  }
  final current = entry['project'] as String?;
  final project = await showSpanSheet<String>(
    context,
    (context) => SheetBody(
      title: tr('移动到'),
      subtitle: entry['name'] as String,
      content: [
        Panel(
          dividerIndent: 52,
          children: [
            for (final (id, name) in [
              ('__root__', tr('未归类')),
              for (final p in store.projects)
                (p['id'] as String, p['name'] as String),
            ])
              ValueRow(
                name,
                icon: id == '__root__'
                    ? Icons.inbox_outlined
                    : Icons.folder_outlined,
                chevron: false,
                trailing: (current ?? '__root__') == id
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(context, id),
              ),
          ],
        ),
      ],
    ),
  );
  if (project == null || project == (current ?? '__root__')) return;
  await store.mutate('move', {
    'id': entry['id'],
    'project': project == '__root__' ? null : project,
  }, baseRevision: baseRevision);
  if (context.mounted) {
    notify(
      context,
      tr('已移动到「{place}」', {
        'place': project == '__root__'
            ? tr('未归类')
            : store.state['projects'][project]['name'],
      }),
    );
  }
}
