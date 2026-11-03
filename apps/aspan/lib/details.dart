// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'data.dart';
import 'design.dart';
import 'editor.dart';
import 'widgets.dart';

void openRule(BuildContext context, SpanStore store, String id) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RuleDetail(store: store, id: id),
      ),
    );
void openGroup(BuildContext context, SpanStore store, String id) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GroupDetail(store: store, id: id),
      ),
    );
void openAccount(
  BuildContext context,
  SpanStore store,
  String id, {
  String? rule,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => AccountDetail(store: store, id: id, rule: rule),
  ),
);

String statusLabel(String value) => switch (value) {
  'pending' => '待处理',
  'processing' => '处理中',
  'completed' => '已完成',
  'skipped' => '已跳过',
  'failed' => '已失败或放弃',
  _ => value,
};
String actionLabel(String value) => switch (value) {
  'create_rule' => '创建规则',
  'edit_rule' => '编辑规则',
  'copy' => '完整复制',
  'merge' => '合并规则',
  'event' => '处理周期事件',
  'resource' => '记录资源变化',
  'correct_entry' => '纠正流水',
  'delete_rule' => '删除规则',
  'configure_account' => '账户设置',
  _ => value,
};

/// Rust records event status in its enum spelling; show it in Chinese.
String historyDetail(Json h) {
  final detail = h['detail'] as String? ?? '';
  if (detail.startsWith('{')) return '';
  return detail
      .replaceAll('Completed', '已完成')
      .replaceAll('Processing', '处理中')
      .replaceAll('Skipped', '已跳过')
      .replaceAll('Failed', '已失败或放弃')
      .replaceAll('Pending', '待处理');
}

Widget historyRow(BuildContext context, Json h) {
  final detail = historyDetail(h);
  return ListTile(
    dense: true,
    leading: const Icon(Icons.history, size: 20),
    title: Text(actionLabel(h['action'] as String)),
    subtitle: Text(
      detail.isEmpty
          ? friendlyDate(h['date'] as String)
          : '${friendlyDate(h['date'] as String)} · $detail',
    ),
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
          body: const EmptyState(
            '规则已移入历史',
            '已发生的资源流水继续保留，可在账户明细中查看。',
            icon: Icons.history,
          ),
        );
      }
      final theme = Theme.of(context);
      final rule = object(r),
          v = store.view(id),
          aid = rule['account'] as String?;
      final phase = v['phase'] as String;
      final days = v['remaining_days'] as int?;
      final urgent = actionPhases.contains(phase);
      final accent = urgent || phase == 'reminder'
          ? phaseColor(context, phase)
          : theme.colorScheme.primary;
      final schedule = rule['schedule'] as Map?;
      final group = rule['group'] == null
          ? null
          : store.state['groups'][rule['group']];
      final project = rule['project'] == null
          ? null
          : store.state['projects'][rule['project']]?['name'];
      final occurrences =
          objects(store.state['occurrences'])
              .where((o) => o['rule'] == id)
              .toList()
            ..sort(
              (a, b) =>
                  b['planned'].toString().compareTo(a['planned'].toString()),
            );
      final history = (store.state['history'] as List)
          .map(object)
          .where((h) => h['subject'] == id)
          .toList()
          .reversed
          .toList();
      final completeLabel = rule['reset'] != null
          ? '完成并恢复额度'
          : rule['change'] != null
          ? '确认发生并记录'
          : '标记完成';
      final graceDays = rule['reminder']['grace_days'] as int? ?? 0;

      final children = <Widget>[
        // Identity: what is this and where does it live.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                ruleIcon(rule['icon'] as String?),
                size: 48,
                color: accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule['name'] as String,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PhaseBadge(phase),
                        Text(
                          project == null ? '未归类' : '$project',
                          style: theme.textTheme.bodySmall,
                        ),
                        for (final t in rule['tags'] as List)
                          Text(
                            '#${store.state['tags'][t]?['name'] ?? ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (group != null) ...[
          const SizedBox(height: 12),
          Panel(
            children: [
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text('属于合并条目「${group['name']}」'),
                subtitle: const Text('共享账户；周期、提醒与历史独立'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openGroup(context, store, group['id'] as String),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // Current period: the one thing a user comes here to act on.
        if (v['planned'] != null)
          Panel(
            padding: const EdgeInsets.all(16),
            dividerIndent: -1,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    relativeDays(days!),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: urgent ? accent : null,
                      fontFeatures: tabular,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '下次事件 ${friendlyDate(v['planned'] as String)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TimelineBar(
                segments: v['segments'] == null ? null : object(v['segments']),
                progress: (v['time_progress'] as num? ?? 0).toDouble(),
                remainingDays: days,
                graceDays: graceDays,
                color: accent,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '周期已过 ${(((v['time_progress'] as num?) ?? 0) * 100).round()}%',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      v['next_reminder'] == null
                          ? '本期无后续提醒'
                          : '下一提醒 ${friendlyDate(v['next_reminder'] as String, weekday: false)}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final primary = FilledButton.icon(
                    key: const ValueKey('complete-event'),
                    onPressed: () =>
                        eventSheet(context, store, rule, 'completed'),
                    icon: const Icon(Icons.check),
                    label: Text(completeLabel),
                  );
                  final secondary = [
                    if (phase != 'processing')
                      OutlinedButton(
                        onPressed: () =>
                            eventSheet(context, store, rule, 'processing'),
                        child: const Text('处理中'),
                      ),
                    PopupMenuButton<String>(
                      tooltip: '本期其他处理',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (s) => eventSheet(context, store, rule, s),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'skipped', child: Text('跳过本期')),
                        PopupMenuItem(value: 'failed', child: Text('失败或放弃')),
                      ],
                    ),
                  ];
                  // Large text on narrow phones: give the primary action its
                  // own full-width row instead of squeezing its label.
                  final stacked =
                      constraints.maxWidth <
                      300 * MediaQuery.textScalerOf(context).scale(1);
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        primary,
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: secondary,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: primary),
                      const SizedBox(width: 8),
                      ...secondary,
                    ],
                  );
                },
              ),
            ],
          )
        else if (schedule != null)
          const Callout(
            '周期已结束，没有待处理的一期。需要再次安排时，编辑规则并选择新的日期。',
            icon: Icons.event_busy_outlined,
          ),
        if (schedule != null) ...[
          const SizedBox(height: 12),
          Panel(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.repeat, size: 20),
                title: Text(cycleLabel(object(schedule['cycle']))),
                subtitle: Text(
                  schedule['cycle']['kind'] == 'restart'
                      ? '下一期从实际完成日期起算'
                      : '按计划日历推进，晚确认不改变周期',
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.notifications_none, size: 20),
                title: Text(reminderSummary(object(rule['reminder']))),
                subtitle: const Text('应用内提醒计划；系统通知尚未接入'),
              ),
            ],
          ),
        ],
        if (aid != null) ...[
          SectionHeader(group == null ? '资源账户' : '共享资源账户'),
          ResourceCard(store: store, account: aid, rule: id),
        ],
        if ((rule['notes'] as String).isNotEmpty) ...[
          const SectionHeader('备注'),
          Panel(
            padding: const EdgeInsets.all(16),
            children: [SelectableText(rule['notes'] as String)],
          ),
        ],
        SectionHeader('周期记录', note: '${occurrences.length}'),
        if (occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '完成、跳过或处理后，每一期都会在这里保留记录。',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          PagedItems(
            key: ValueKey('occurrences-$id'),
            items: occurrences,
            itemBuilder: (o) => occurrenceRow(context, o),
          ),
        SectionHeader('操作历史', note: '${history.length}'),
        PagedItems(
          key: ValueKey('history-$id'),
          items: history,
          itemBuilder: (h) => historyRow(context, h),
        ),
      ];
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              key: const ValueKey('edit-rule'),
              tooltip: '编辑规则',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => openCreator(context, store, rule: rule),
            ),
            PopupMenuButton<String>(
              key: const ValueKey('rule-menu'),
              tooltip: '更多规则操作',
              onSelected: (action) => switch (action) {
                'copy' => copyEntry(context, store, id),
                'move' => perform(
                  context,
                  () => moveEntry(context, store, rule),
                ),
                'template' => saveAsTemplate(context, store, rule),
                'delete' => deleteRule(context, store, id),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('完整复制'),
                    subtitle: Text('含历史、账户与余额'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'template',
                  child: ListTile(
                    leading: Icon(Icons.bookmark_add_outlined),
                    title: Text('保存为模板'),
                    subtitle: Text('仅保留配置'),
                  ),
                ),
                if (group == null)
                  const PopupMenuItem(
                    value: 'move',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_move_outlined),
                      title: Text('移动到小项目'),
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      '删除规则',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: pagePadding(context, top: 0),
          children: [for (final c in children) Readable(child: c)],
        ),
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
    'completed' => Icons.check_circle_outline,
    'processing' => Icons.pending_outlined,
    'skipped' => Icons.redo,
    'failed' => Icons.cancel_outlined,
    _ => Icons.radio_button_unchecked,
  };
  final windowEnd = o['window_end'] != o['planned'];
  return ListTile(
    dense: true,
    leading: Icon(icon, color: color, size: 20),
    title: Text(
      '${friendlyDate(o['planned'] as String)} · ${statusLabel(status)}',
    ),
    subtitle: Text(
      [
        if (o['actual'] != null)
          '实际 ${friendlyDate(o['actual'] as String, weekday: false)}',
        if (o['completed'] != null)
          '处理于 ${friendlyDate(o['completed'] as String, weekday: false)}',
        if (windowEnd)
          '窗口至 ${friendlyDate(o['window_end'] as String, weekday: false)}',
      ].join(' · '),
    ),
  );
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
          content: Text(isGroup ? '已复制全部成员、账户与历史' : '已完整复制，副本拥有独立账户与历史'),
          action: SnackBarAction(
            label: '查看副本',
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

Future<void> deleteRule(BuildContext context, SpanStore store, String id) =>
    perform(context, () async {
      final baseRevision = store.revision;
      final inGroup = store.state['rules'][id]['group'] != null;
      if (!await confirm(
        context,
        '删除这条规则？',
        '规则移入历史，不再提醒。已发生的流水和共享余额会保留'
            '${inGroup ? '；合并条目只剩一个成员时自动退化为普通规则' : ''}。此操作无法撤销。',
        action: '删除',
        destructive: true,
      )) {
        return;
      }
      await store.mutate('delete_rule', {'id': id}, baseRevision: baseRevision);
      if (context.mounted) {
        Navigator.pop(context);
        notify(context, '规则已删除，流水保留');
      }
    });

Future<void> saveAsTemplate(BuildContext context, SpanStore store, Json rule) =>
    perform(context, () async {
      final baseRevision = store.revision;
      final aid = rule['account'] as String?;
      final name = await askText(
        context,
        '保存为我的模板',
        initial: rule['name'] as String,
        label: '模板名称',
        helper: '模板只保存配置（含当前日期），不含余额与历史',
        action: '保存',
      );
      if (name == null) return;
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
    }, success: '已保存为模板，新建规则时可直接使用');

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
    notify(context, '周期尚未开始；请在起点当天之后处理，或先编辑起点');
    return;
  }
  final aid = rule['account'] as String?;
  final account = aid == null ? null : store.state['accounts'][aid];
  final unit = account?['unit']['code'] as String? ?? '';
  final precision = account?['unit']['precision'] as int? ?? 0;
  final change = rule['change'] as int?, reset = rule['reset'] as int?;
  final effect = account == null
      ? null
      : reset != null
      ? '恢复额度到 ${formatUnits(reset, precision)} $unit'
      : change != null
      ? '记录 ${change > 0 ? '+' : ''}${formatUnits(change, precision)} $unit'
      : null;
  final restart = rule['schedule']['cycle']['kind'] == 'restart';
  String actual = dateOnly(today);
  bool record = true;
  bool busy = false;
  String? error;
  final (title, action, explanation) = switch (status) {
    'completed' => (
      '完成本期',
      '确认完成',
      restart ? '下一期从实际发生日期重新计时。' : '下一期仍按原计划日历推进，晚确认不改变周期。',
    ),
    'processing' => ('标记处理中', '标记处理中', '本期保持在“需要处理”中，直到完成、跳过或放弃。'),
    'skipped' => ('跳过本期', '跳过本期', '本期结束并推进到下一计划，不产生资源流水。'),
    _ => ('标记失败或放弃', '确认放弃', '本期结束并推进到下一计划，不产生资源流水。'),
  };
  final accepted = await showSpanSheet<bool>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) => SheetBody(
        title: title,
        subtitle: '${rule['name']} · 计划 ${friendlyDate(planned)}',
        content: [
          if (error != null) ...[
            Callout(error!, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
          ],
          if (status == 'completed')
            Panel(
              children: [
                ListTile(
                  key: const ValueKey('actual-date'),
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('实际发生日期'),
                  trailing: Text(
                    actual == dateOnly(today) ? '今天' : friendlyDate(actual),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
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
                    secondary: const Icon(
                      Icons.account_balance_wallet_outlined,
                    ),
                    title: Text('同时$effect'),
                    subtitle: const Text('写入实际流水，可在账户明细中纠正'),
                    value: record,
                    onChanged: busy ? null : (v) => setState(() => record = v),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Text(explanation, style: Theme.of(context).textTheme.bodySmall),
        ],
        actions: [
          OutlinedButton(
            onPressed: busy ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
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
            child: Text(busy ? '正在保存…' : action),
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
          ? '已标记处理中'
          : next == null
          ? '本期已结束，没有下一期'
          : '本期已结束 · 下次 ${friendlyDate(next)}',
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
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
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
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontFeatures: tabular,
                                color: v['low'] == true
                                    ? warningColor(context)
                                    : null,
                              ),
                            ),
                            TextSpan(
                              text: '  ${v['unit']}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text('明细', style: theme.textTheme.bodySmall),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
        if (v['progress'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (v['progress'] as num).toDouble(),
                  minHeight: 4,
                ),
                const SizedBox(height: 4),
                Text(
                  '剩余比例 ${((v['progress'] as num) * 100).round()}% · 参考总量 ${formatUnits(ac['reference'] as int, p)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (v['low'] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              '已低于不足阈值 ${formatUnits(ac['low'] as int, p)} ${v['unit']}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: warningColor(context),
              ),
            ),
          ),
        if (ac['archived'] != true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
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
          const SizedBox(height: 12),
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
          body: const EmptyState(
            '合并条目已退化',
            '只剩一个成员时，它已成为普通规则，余额与历史保留。',
            icon: Icons.layers_clear_outlined,
          ),
        );
      }
      final theme = Theme.of(context);
      final members = store.ordered(
        store.rules.where((r) => r['group'] == id).toList(),
      );
      final project = g['project'] == null
          ? '未归类'
          : store.state['projects'][g['project']]?['name'] ?? '未归类';
      final history = (store.state['history'] as List)
          .map(object)
          .where((h) => h['subject'] == id)
          .toList()
          .reversed
          .toList();
      final children = <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(Icons.layers_outlined, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g['name'] as String,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '合并条目 · ${members.length} 条独立规则 · $project',
                      style: theme.textTheme.bodySmall,
                    ),
                    if ((store.snapshot['group_tags'][id] as List).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            for (final tid
                                in store.snapshot['group_tags'][id] as List)
                              '#${store.state['tags'][tid]['name']}',
                          ].join('  '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if ((g['accounts'] as List).isNotEmpty) ...[
          const SectionHeader('共享资源', note: '每个账户只计算一次'),
          for (final aid in g['accounts'] as List) ...[
            ResourceCard(store: store, account: aid as String),
            const SizedBox(height: 8),
          ],
        ],
        SectionHeader('成员规则', note: '${members.length}'),
        for (final r in members)
          RuleTile(
            store: store,
            rule: r,
            onTap: () => openRule(context, store, r['id'] as String),
          ),
        if ((g['archived_accounts'] as List).isNotEmpty) ...[
          const SectionHeader('合并前账本', note: '仅作历史证据，不计入共享余额'),
          Panel(
            children: [
              for (final aid in g['archived_accounts'] as List)
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined, size: 20),
                  title: Text(store.state['accounts'][aid]['name'] as String),
                  subtitle: Text(
                    '已归档 · ${store.accountView(aid as String)['formatted']} ${store.accountView(aid)['unit']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openAccount(context, store, aid),
                ),
            ],
          ),
        ],
        if (history.isNotEmpty) ...[
          const SectionHeader('操作历史'),
          PagedItems(
            key: ValueKey('group-history-$id'),
            items: history,
            itemBuilder: (h) => historyRow(context, h),
          ),
        ],
      ];
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: '重命名合并条目',
              onPressed: () => perform(context, () async {
                final baseRevision = store.revision;
                final name = await askText(
                  context,
                  '重命名合并条目',
                  initial: g['name'] as String,
                  action: '保存',
                );
                if (name != null) {
                  await store.mutate('rename_group', {
                    'id': id,
                    'name': name,
                  }, baseRevision: baseRevision);
                }
              }),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: '更多合并条目操作',
              onSelected: (action) => switch (action) {
                'move' => perform(
                  context,
                  () => moveEntry(context, store, object(g)),
                ),
                'copy' => copyEntry(context, store, id),
                'split' => splitGuide(context, store, id),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'move',
                  child: ListTile(
                    leading: Icon(Icons.drive_file_move_outlined),
                    title: Text('移动到小项目'),
                  ),
                ),
                PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('完整复制'),
                    subtitle: Text('全部成员、共享账户与历史'),
                  ),
                ),
                PopupMenuItem(
                  value: 'split',
                  child: ListTile(
                    leading: Icon(Icons.call_split),
                    title: Text('如何拆分'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: pagePadding(context, top: 0),
          children: [for (final c in children) Readable(child: c)],
        ),
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
      title: const Text('拆分合并条目'),
      content: const Text(
        '为保证两边账户与历史都完整、互不影响，拆分分三步：\n\n'
        '1. 完整复制此合并条目\n'
        '2. 在原条目中删除不需要的成员\n'
        '3. 在副本中删除另一部分成员\n\n'
        '只剩一个成员时会自动成为普通规则，余额与流水保留。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('第 1 步：完整复制'),
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
      final children = <Widget>[
        Panel(
          padding: const EdgeInsets.all(20),
          dividerIndent: -1,
          children: [
            Text(
              archived ? '归档账本 · 不计入当前共享余量' : '当前余量',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: v['formatted'] as String,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontSize: 34,
                      fontFeatures: tabular,
                      color: v['low'] == true ? warningColor(context) : null,
                    ),
                  ),
                  TextSpan(
                    text: '  ${v['unit']}',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            if (v['progress'] != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: (v['progress'] as num).toDouble(),
                minHeight: 6,
              ),
              const SizedBox(height: 6),
              Text(
                '剩余 ${((v['progress'] as num) * 100).round()}% · 参考总量 ${formatUnits(ac['reference'] as int, p)} ${v['unit']}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (ac['low'] != null) ...[
              const SizedBox(height: 4),
              Text(
                '不足提醒阈值 ${formatUnits(ac['low'] as int, p)} ${v['unit']}${v['low'] == true ? ' · 已低于阈值' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: v['low'] == true ? warningColor(context) : null,
                ),
              ),
            ],
            if (users.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${users.length > 1 ? '共享' : '关联'}：${users.map((r) => r['name']).join('、')}',
                style: theme.textTheme.bodySmall,
              ),
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
                  PopupMenuButton<String>(
                    tooltip: '更多账户操作',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (value) => value == 'set'
                        ? resourceSheet(context, store, id, 'set', rule)
                        : forecastSheet(context, store, id),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'set',
                        child: ListTile(
                          leading: Icon(Icons.tune),
                          title: Text('修正当前余量'),
                          subtitle: Text('追加差额流水，不改历史'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'forecast',
                        child: ListTile(
                          leading: Icon(Icons.insights_outlined),
                          title: Text('查看预测'),
                          subtitle: Text('只读估算，不入账'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
        SectionHeader('实际流水', note: '${entries.length} 条 · 点按查看或纠正'),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('暂无流水。', style: theme.textTheme.bodySmall),
          )
        else
          PagedItems(
            key: ValueKey('ledger-$id'),
            items: entries,
            itemBuilder: (e) =>
                ledgerRow(context, store, e, p, v['unit'] as String),
          ),
      ];
      return Scaffold(
        appBar: AppBar(
          title: Text(ac['name'] as String),
          actions: [
            if (!archived)
              IconButton(
                tooltip: '账户设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () =>
                    accountOptionsSheet(context, store, object(ac)),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: pagePadding(context, top: 4),
          children: [for (final c in children) Readable(child: c)],
        ),
      );
    },
  );
}

String entryNote(Json entry) {
  final note = entry['note'] as String;
  return entry['source'] == 'manual'
      ? note.replaceFirst(RegExp(r'^(add|consume|set):-?\d+:'), '')
      : note;
}

String sourceLabel(String source) => switch (source) {
  'initial' => '初始基准',
  'manual' => '手动记录',
  'confirmed' => '事件确认',
  'correction' => '纠正替代',
  'correction_reverse' => '纠正反向',
  _ => source,
};

Widget ledgerRow(
  BuildContext context,
  SpanStore store,
  Json e,
  int precision,
  String unit,
) {
  final delta = e['delta'] as int;
  final corrected = e['corrected_by'] != null;
  final note = entryNote(e);
  final rule = e['rule'] == null ? null : store.state['rules'][e['rule']];
  return ListTile(
    leading: Icon(
      delta >= 0 ? Icons.south_west : Icons.north_east,
      size: 20,
      color: delta >= 0 ? successColor(context) : null,
    ),
    title: Text(
      note.isNotEmpty ? note : sourceLabel(e['source'] as String),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: corrected
          ? TextStyle(
              decoration: TextDecoration.lineThrough,
              color: SpanColors.of(context).muted,
            )
          : null,
    ),
    subtitle: Text(
      [
        friendlyDate(e['date'] as String, weekday: false),
        sourceLabel(e['source'] as String),
        if (rule != null) rule['name'],
        if (corrected) '已纠正',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(
      '${delta > 0 ? '+' : ''}${formatUnits(delta, precision)}',
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
        color: corrected
            ? SpanColors.of(context).muted
            : delta >= 0
            ? successColor(context)
            : null,
      ),
    ),
    onTap: () => entrySheet(context, store, e, precision, unit),
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
      title: '${delta > 0 ? '+' : ''}${formatUnits(delta, precision)} $unit',
      subtitle:
          '${friendlyDate(e['date'] as String)} · ${sourceLabel(e['source'] as String)}',
      content: [
        Panel(
          dividerIndent: 16,
          children: [
            if (entryNote(e).isNotEmpty)
              ListTile(title: const Text('备注'), subtitle: Text(entryNote(e))),
            if (rule != null)
              ListTile(
                title: const Text('关联规则'),
                subtitle: Text(rule['name'] as String),
              ),
            if (e['corrected_by'] != null)
              const ListTile(
                title: Text('已纠正'),
                subtitle: Text('原记录保留；实际影响由反向与替代流水承担'),
              ),
            if (e['source'] == 'correction_reverse')
              const ListTile(
                title: Text('系统反向流水'),
                subtitle: Text('不能再次纠正；如需更改，请纠正对应的替代流水'),
              ),
            if (e['origin'] != null)
              ListTile(
                title: const Text('来源记录'),
                subtitle: Text('${e['origin']}'),
              ),
          ],
        ),
      ],
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
        if (correctable)
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('纠正此流水'),
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
  final String title, subtitle, action;
  final String? note;
  final String? suffix;
  final Future<String?> Function(Map<String, String>) submit;
  const _SheetForm({
    required this.fields,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.submit,
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
      if (f.$4 && values[f.$1]!.isEmpty) errors[f.$1] = '请填写${f.$2}';
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
  Widget build(BuildContext context) => SheetBody(
    title: widget.title,
    subtitle: widget.subtitle,
    content: [
      for (var i = 0; i < widget.fields.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
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
          decoration: InputDecoration(
            labelText: widget.fields[i].$2,
            suffixText: i == 0 ? widget.suffix : null,
            errorText: errors[widget.fields[i].$1],
          ),
          onChanged: (_) {
            if (errors.isNotEmpty) setState(errors.clear);
          },
          onSubmitted: (_) => run(),
        ),
      ],
      if (widget.note != null) ...[
        const SizedBox(height: 12),
        Callout(widget.note!),
      ],
    ],
    actions: [
      OutlinedButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
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
    _ => '修正当前余量',
  };
  final message = await showSpanSheet<String>(
    context,
    (_) => _SheetForm(
      title: title,
      subtitle: '${ac['name']} · 当前 ${v['formatted']} ${v['unit']}',
      action: '确认$title',
      suffix: v['unit'] as String,
      note: action == 'set' ? '将追加一条差额流水使余量等于输入值；原有流水保留。' : null,
      fields: [
        (
          'amount',
          action == 'set' ? '正确的当前余量' : '数量',
          action == 'consume' && ac['unit']['kind'] == 'count' ? '1' : '',
          true,
        ),
        ('note', '备注（可选）', '', false),
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
        return '已记录 · 当前 ${now['formatted']} ${now['unit']}';
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
      title: '纠正流水',
      subtitle:
          '原记录 ${formatUnits(entry['delta'] as int, precision)} $unit · ${friendlyDate(entry['date'] as String)}',
      action: '提交纠正',
      suffix: unit,
      note: '原流水保留；将同时追加一条反向流水和一条替代流水，原因写入审计历史。',
      fields: [
        (
          'delta',
          '正确的变化值（扣减为负数）',
          formatUnits(entry['delta'] as int, precision),
          true,
        ),
        ('reason', '纠正原因（写入审计历史）', '', true),
      ],
      submit: (values) async {
        await store.mutate('correct_entry', {
          'id': entry['id'],
          'delta': values['delta'],
          'reason': values['reason'],
        }, baseRevision: baseRevision);
        return '已纠正，原记录保留';
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
  final unit = store.accountView(id)['unit'];
  await showSpanSheet<void>(
    context,
    (context) => SheetBody(
      title: '未来资源预测',
      subtitle: forecast['assumption'] as String,
      content: [
        if ((forecast['events'] as List).isEmpty)
          const Callout('没有固定的扣费或恢复计划，无法估算。完成后重新计时的周期不参与预测。')
        else
          Panel(
            dividerIndent: 16,
            children: [
              for (final e in forecast['events'] as List)
                ListTile(
                  dense: true,
                  title: Text(
                    '${friendlyDate(e['planned'] as String)} · ${store.state['rules'][e['rule']]?['name'] ?? ''}',
                  ),
                  subtitle: Text(
                    '变化 ${e['delta']} $unit · 预计余量 ${e['balance']} $unit',
                  ),
                  trailing: e['insufficient'] == true
                      ? Text(
                          '可能不足',
                          style: TextStyle(color: warningColor(context)),
                        )
                      : null,
                ),
            ],
          ),
        if (forecast['truncated'] == true) ...[
          const SizedBox(height: 8),
          Text('仅显示最近的计划。', style: Theme.of(context).textTheme.bodySmall),
        ],
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
      title: '账户设置',
      subtitle: '共享成员看到同一设置；不改变实际余额',
      action: '保存',
      fields: [
        ('name', '账户名称', account['name'] as String, true),
        (
          'reference',
          '参考总量（可留空）',
          account['reference'] == null
              ? ''
              : formatUnits(account['reference'] as int, p),
          false,
        ),
        (
          'low',
          '不足提醒阈值（可留空）',
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
        return '账户设置已保存';
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
    notify(context, '成员随所属合并条目一起移动，请在合并详情中操作');
    return;
  }
  final current = entry['project'] as String?;
  final project = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('移动到'),
      children: [
        for (final (id, name) in [
          ('__root__', '未归类'),
          for (final p in store.projects)
            (p['id'] as String, p['name'] as String),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, id),
            child: Row(
              children: [
                Icon(
                  id == '__root__'
                      ? Icons.inbox_outlined
                      : Icons.folder_outlined,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(name)),
                if ((current ?? '__root__') == id)
                  Icon(
                    Icons.check,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
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
      '已移动到「${project == '__root__' ? '未归类' : store.state['projects'][project]['name']}」',
    );
  }
}
