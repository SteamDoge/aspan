// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'design.dart';

const _sceneOrder = ['订阅缴费', '日常与纪念日', '检查维护', '资源权益', '有效期'];

Json presetConfig(Json t) {
  final next = dateOnly(
    t['start_today'] == true ? DateTime.now() : civilTomorrow(),
  );
  final kind =
      t['resource'] as String? ?? (t['money'] == true ? 'money' : null);
  return <String, dynamic>{
    'name': t['name'],
    'icon': t['icon'],
    if (t['guidance'] != null) 'guidance': t['guidance'],
    'reminder': {
      'before': t['before'] ?? [7, 1],
      'on_day': true,
      'grace_days': t['grace'] ?? 0,
      'repeat_days': null,
    },
    if (t['cycle'] != null)
      'schedule': {
        'anchor': next,
        'next': next,
        'cycle': {'kind': t['cycle'], if (t['days'] != null) 'days': t['days']},
      },
    if (kind != null)
      'new_account': {
        'name': t['name'],
        'unit': {
          'kind': kind,
          'code': kind == 'money'
              ? 'CNY'
              : kind == 'count'
              ? '次'
              : t['unit'] ?? '单位',
          'precision': kind == 'count' ? 0 : 2,
        },
        'initial': t['initial'] ?? '0',
        'reference': t['reference'],
        'low': null,
      },
    if (t['reset'] != null) 'reset': t['reset'],
  };
}

/// Short, factual description of what a preset or saved template enables.
String configSummary(Json c) {
  final schedule = c['schedule'] as Map?;
  final account = c['new_account'] as Map?;
  final kind = account?['unit']?['kind'];
  return [
    schedule == null ? '无周期' : cycleLabel(object(schedule['cycle'])),
    if (kind == 'money') '金额账户 ${account!['unit']['code']}',
    if (kind == 'count') '次数账户',
    if (kind == 'quantity') '额度账户 ${account!['unit']['code']}',
    if (c['reset'] != null) '每期恢复额度',
    if (schedule != null && c['reminder'] != null)
      reminderSummary(object(c['reminder'])),
  ].join(' · ');
}

Future<void> openCreator(
  BuildContext context,
  SpanStore store, {
  Json? rule,
  String? project,
}) async {
  if (rule != null) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RuleEditor(store: store, initial: rule, editing: true),
      ),
    );
    return;
  }
  final official = (jsonDecode(
    await rootBundle.loadString('assets/templates.json'),
  ) as List).map(object).toList();
  if (!context.mounted) return;
  final custom = objects(store.state['templates']);
  final choice = await showModalBottomSheet<Json>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => TemplatePicker(official: official, custom: custom),
  );
  if (choice != null && context.mounted) {
    choice['project'] = project;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RuleEditor(store: store, initial: choice),
      ),
    );
  }
}

/// Start blank, from a saved template, or from a preset grouped by scene.
class TemplatePicker extends StatelessWidget {
  final List<Json> official, custom;
  const TemplatePicker({
    super.key,
    required this.official,
    required this.custom,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scenes = <String, List<Json>>{};
    for (final t in official) {
      (scenes[t['scene'] as String? ?? '其他'] ??= []).add(t);
    }
    final order = [
      ..._sceneOrder.where(scenes.containsKey),
      ...scenes.keys.where((s) => !_sceneOrder.contains(s)),
    ];
    Widget option(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap, {
      bool emphasized = false,
    }) => ListTile(
      leading: IconTile(
        icon,
        size: 36,
        color: emphasized ? null : SpanColors.of(context).muted,
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新建规则', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  '模板只预填字段，创建的都是普通规则，所有字段均可修改。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Panel(
            children: [
              option(
                Icons.add,
                '空白创建',
                '只开启你需要的时间、资源与提醒',
                () => Navigator.pop(context, <String, dynamic>{}),
                emphasized: true,
              ),
            ],
          ),
          if (custom.isNotEmpty) ...[
            const SectionHeader('我的模板', note: '保留保存时的日期，请核对'),
            Panel(
              children: [
                for (final t in custom)
                  option(
                    Icons.bookmark_outline,
                    t['name'] as String,
                    configSummary(object(t['config'])),
                    () => Navigator.pop(
                      context,
                      object(t['config'])
                        ..['guidance'] =
                            '来自我的模板「${t['name']}」：模板保留保存时的配置日期，请核对本期日期与起点。',
                    ),
                  ),
              ],
            ),
          ],
          for (final scene in order) ...[
            SectionHeader(scene),
            Panel(
              children: [
                for (final t in scenes[scene]!)
                  option(
                    ruleIcon(t['icon'] as String?),
                    t['name'] as String,
                    t['description'] as String? ??
                        configSummary(presetConfig(t)),
                    () => Navigator.pop(context, presetConfig(t)),
                    emphasized: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

DateTime civilTomorrow() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1);
}

String formatUnits(int value, int precision) {
  final raw = BigInt.from(value).abs().toString().padLeft(precision + 1, '0');
  return '${value < 0 ? '-' : ''}${precision == 0 ? raw : '${raw.substring(0, raw.length - precision)}.${raw.substring(raw.length - precision)}'}';
}

class RuleEditor extends StatefulWidget {
  final SpanStore store;
  final Json initial;
  final bool editing;
  const RuleEditor({
    super.key,
    required this.store,
    required this.initial,
    this.editing = false,
  });
  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> fields = {};
  final Map<String, String> initialText = {};
  late bool timed, resource, pinned, onDay;
  late String cycle, kind, unit, icon, next, start, changeMode;
  late bool ended;
  late List<int> before;
  String? project, account;
  late int precision;
  late Set<String> tags;
  bool busy = false, changed = false, saved = false;
  String? error;
  late int baseRevision;
  TextEditingController field(String key) => fields[key]!;
  bool get dirty =>
      changed || fields.entries.any((e) => e.value.text != initialText[e.key]);

  /// Every user-driven change goes through here so leaving can be guarded.
  void update(VoidCallback change) => setState(() {
    change();
    changed = true;
  });

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    baseRevision = widget.store.revision;
    timed = r['schedule'] != null || !widget.editing && !r.containsKey('name');
    ended =
        widget.editing &&
        r['schedule'] != null &&
        r['schedule']['next'] == null;
    cycle = r['schedule']?['cycle']?['kind'] as String? ?? 'once';
    next = r['schedule']?['next'] as String? ?? dateOnly(civilTomorrow());
    resource = r['account'] != null || r['new_account'] != null;
    start = r['schedule']?['anchor'] as String? ?? dateOnly(DateTime.now());
    if (start.compareTo(next) > 0) start = next;
    account = r['account'] as String?;
    final ac = account == null
        ? r['new_account']
        : widget.store.state['accounts'][account];
    kind = ac?['unit']?['kind'] as String? ?? 'money';
    final resourceCode = ac?['unit']?['code'] as String? ?? 'CNY';
    unit = kind == 'money' ? resourceCode : 'CNY';
    precision = ac?['unit']?['precision'] as int? ?? 2;
    project = r['project'] as String?;
    tags = Set<String>.from(r['tags'] ?? []);
    pinned = r['pinned'] == true;
    icon = r['icon'] as String? ?? 'schedule';
    onDay = r['reminder']?['on_day'] as bool? ?? true;
    before = {
      for (final n in r['reminder']?['before'] as List? ?? const [7, 1])
        n as int,
    }.toList()..sort((a, b) => b.compareTo(a));
    String amount(dynamic value) => value == null
        ? ''
        : value is int
        ? formatUnits(value, precision)
        : value.toString();
    var changeAmount = '';
    if (r['reset'] != null) {
      changeMode = 'reset';
      changeAmount = amount(r['reset']);
    } else if (r['change'] != null) {
      final text = amount(r['change']);
      changeMode = text.startsWith('-') ? 'consume' : 'add';
      changeAmount = text.replaceFirst(RegExp(r'^[-+]'), '');
    } else {
      changeMode = 'none';
    }
    final values = <String, String>{
      'name': r['name'] as String? ?? '',
      'notes': r['notes'] as String? ?? '',
      'days': (r['schedule']?['cycle']?['days'] ?? 365).toString(),
      'dates': (r['schedule']?['cycle']?['dates'] as List? ?? []).join(','),
      'initial': ac?['initial'] as String? ?? '0',
      'reference': amount(ac?['reference']),
      'low': amount(ac?['low']),
      'amount': changeAmount,
      'grace': (r['reminder']?['grace_days'] ?? 0).toString(),
      'repeat': (r['reminder']?['repeat_days'] ?? '').toString(),
      'unit': resourceCode,
      'precision': precision.toString(),
    };
    for (final e in values.entries) {
      fields[e.key] = TextEditingController(text: e.value)
        ..addListener(textChanged);
      initialText[e.key] = e.value;
    }
    wasDirty = dirty;
  }

  /// Typing does not rebuild the form, but the back guard must follow it.
  late bool wasDirty;
  void textChanged() {
    if (dirty != wasDirty) setState(() => wasDirty = dirty);
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get unitCode => account != null
      ? widget.store.accountView(account!)['unit'] as String
      : kind == 'money'
      ? unit
      : kind == 'count'
      ? '次'
      : field('unit').text.trim();

  Widget input(
    String key,
    String label, {
    String? hint,
    int lines = 1,
    bool numeric = false,
    bool required = false,
    String? suffix,
    bool autofocus = false,
  }) => TextFormField(
    key: ValueKey('field-$key'),
    controller: field(key),
    maxLines: lines,
    autofocus: autofocus,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      helperText: hint,
      suffixText: suffix,
    ),
    validator: (value) {
      final text = value?.trim() ?? '';
      if (required && text.isEmpty) return '请填写$label';
      if (['precision', 'days', 'grace', 'repeat'].contains(key) &&
          text.isNotEmpty) {
        final n = int.tryParse(text);
        final min = key == 'days' || key == 'repeat' ? 1 : 0;
        final max = key == 'precision' ? 6 : 36500;
        if (n == null || n < min || n > max) return '请输入 $min—$max 之间的整数';
      }
      if (key == 'amount' && text.startsWith(RegExp(r'[-+]'))) {
        return '只填数值，方向由上方选项决定';
      }
      return null;
    },
  );

  Json draft() {
    final selectedUnit = kind == 'money'
        ? unit
        : kind == 'count'
        ? '次'
        : field('unit').text.trim();
    final p = kind == 'count'
        ? 0
        : kind == 'money'
        ? widget.store.snapshot['money_units'][unit] as int
        : int.parse(field('precision').text);
    final amount = field('amount').text.trim();
    final recordsChange = resource && amount.isNotEmpty;
    return {
      'name': field('name').text.trim(),
      'notes': field('notes').text,
      'icon': icon,
      'project': project,
      'tags': tags.toList(),
      'pinned': pinned,
      'schedule': timed
          ? {
              'anchor': start,
              'next': ended ? null : next,
              'cycle': {
                'kind': cycle,
                if (cycle == 'interval' || cycle == 'restart')
                  'days': int.parse(field('days').text),
                if (cycle == 'calendar')
                  'dates':
                      field('dates').text
                          .replaceAll('，', ',')
                          .split(',')
                          .map((v) => v.trim())
                          .where((v) => v.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort(),
              },
            }
          : null,
      'reminder': {
        'before': [...before],
        'on_day': onDay,
        'grace_days': int.parse(field('grace').text),
        'repeat_days': field('repeat').text.trim().isEmpty
            ? null
            : int.parse(field('repeat').text.trim()),
      },
      'account': resource ? account : null,
      if (resource && account == null)
        'new_account': {
          'name': field('name').text.trim(),
          'unit': {'kind': kind, 'code': selectedUnit, 'precision': p},
          'initial': field('initial').text.trim(),
          'reference': field('reference').text.trim().isEmpty
              ? null
              : field('reference').text.trim(),
          'low': field('low').text.trim().isEmpty
              ? null
              : field('low').text.trim(),
        },
      'change':
          recordsChange && (changeMode == 'consume' || changeMode == 'add')
          ? '${changeMode == 'consume' ? '-' : ''}$amount'
          : null,
      'reset': recordsChange && changeMode == 'reset' ? amount : null,
    };
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      setState(() => error = '请检查标出的字段');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = draft();
      if (widget.editing) value['id'] = widget.initial['id'];
      await widget.store.mutate('save_rule', value, baseRevision: baseRevision);
      saved = true;
      if (mounted) {
        notify(context, widget.editing ? '已保存修改' : '已创建「${value['name']}」');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave() async {
    if (await confirm(
          context,
          '放弃未保存的修改？',
          '离开后，本次填写的内容不会保存。',
          action: '放弃',
          destructive: true,
        ) &&
        mounted) {
      saved = true;
      Navigator.pop(context);
    }
  }

  Future<void> pickDate({required bool isNext}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(isNext ? next : start),
      firstDate: DateTime(1900),
      lastDate: isNext ? DateTime(2200) : DateTime.parse(next),
    );
    if (picked == null || !mounted) return;
    update(() {
      if (isNext) {
        ended = false;
        next = dateOnly(picked);
        if (start.compareTo(next) > 0) start = next;
      } else {
        start = dateOnly(picked);
      }
    });
  }

  Future<void> addReminderDay() async {
    final value = await askText(
      context,
      '提前几天提醒',
      label: '天数',
      helper: '0—36500 的整数；0 表示事件当天',
      keyboard: TextInputType.number,
      action: '添加',
    );
    final n = int.tryParse(value ?? '');
    if (value == null) return;
    if (n == null || n < 0 || n > 36500) {
      if (mounted) notify(context, '提醒节点须为 0—36500 的整数');
      return;
    }
    update(() {
      if (!before.contains(n)) before.add(n);
      before.sort((a, b) => b.compareTo(a));
    });
  }

  Future<void> createTag() async {
    final store = widget.store;
    final name = await askText(context, '新建标签', action: '创建');
    if (name == null || !mounted) return;
    final revision = store.revision;
    await perform(context, () async {
      final response = await store.mutate('save_tag', {'name': name});
      // Adopt the new revision only if nothing else changed meanwhile, so the
      // stale-draft protection still holds for concurrent edits.
      if (baseRevision == revision && store.revision == revision + 1) {
        baseRevision = store.revision;
      }
      if (mounted) update(() => tags.add(response['result'] as String));
    });
  }

  Widget section(String title, {Widget? trailing, String? note}) =>
      SectionHeader(
        title,
        note: note,
        trailing: trailing,
        padding: const EdgeInsets.fromLTRB(4, 28, 0, 10),
      );

  Widget dateRow({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
    String? detail,
    IconData icon = Icons.calendar_today_outlined,
  }) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    return Material(
      color: colors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(value, style: theme.textTheme.titleMedium),
                    if (detail != null)
                      Text(detail, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(icon, size: 20, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;
    final today = dateOnly(DateTime.now());
    final daysToNext = DateTime.parse(next)
        .difference(DateTime.parse(today))
        .inDays;
    final (addVerb, consumeVerb) = resourceVerbs(kind);
    const gap = SizedBox(height: 12);
    final children = <Widget>[
      if (widget.initial['guidance'] != null) ...[
        const SizedBox(height: 8),
        Callout(widget.initial['guidance'] as String),
      ],
      section('基本信息'),
      input(
        'name',
        '名称',
        required: true,
        autofocus: !widget.editing && field('name').text.isEmpty,
      ),
      gap,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (key, label, data) in ruleIcons)
            ChoiceChip(
              key: ValueKey('icon-$key'),
              label: Icon(
                data,
                size: 20,
                semanticLabel: label,
                color: icon == key ? theme.colorScheme.primary : null,
              ),
              selected: icon == key,
              tooltip: label,
              onSelected: (_) => update(() => icon = key),
            ),
        ],
      ),
      gap,
      if (widget.initial['group'] == null)
        DropdownButtonFormField<String>(
          initialValue: project ?? '',
          decoration: const InputDecoration(labelText: '所属小项目'),
          items: [
            const DropdownMenuItem(value: '', child: Text('未归类')),
            for (final p in store.projects)
              DropdownMenuItem(
                value: p['id'] as String,
                child: Text(p['name'] as String),
              ),
          ],
          onChanged: (v) => update(() => project = v == '' ? null : v),
        )
      else
        Text('归属随所在合并条目，在合并详情中移动。', style: theme.textTheme.bodySmall),
      gap,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in store.tags)
            FilterChip(
              label: Text('#${t['name']}'),
              selected: tags.contains(t['id']),
              onSelected: (v) => update(() {
                v ? tags.add(t['id'] as String) : tags.remove(t['id']);
              }),
            ),
          ActionChip(
            key: const ValueKey('create-tag'),
            avatar: const Icon(Icons.add, size: 18),
            label: Text(store.tags.isEmpty ? '添加标签' : '新标签'),
            onPressed: createTag,
          ),
        ],
      ),

      section(
        '时间与周期',
        trailing: Switch(
          key: const ValueKey('toggle-timed'),
          value: timed,
          onChanged: (v) => update(() => timed = v),
        ),
      ),
      if (!timed) Text('不管理日期时，规则只记录资源与历史。', style: theme.textTheme.bodySmall),
      if (timed) ...[
        dateRow(
          key: const ValueKey('next-date'),
          label: '本期事件日期',
          value: ended ? '周期已结束' : friendlyDate(next),
          detail: ended ? '点按重新安排；只改名称等信息不会产生新一期' : relativeDays(daysToNext),
          onTap: () => pickDate(isNext: true),
        ),
        if (!ended && daysToNext < 0) ...[
          const SizedBox(height: 8),
          Callout(
            '日期早于今天，保存后会立即显示为逾期或处理窗口。',
            icon: Icons.warning_amber_rounded,
            color: warningColor(context),
          ),
        ],
        gap,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in const [
              ('once', '单次'),
              ('daily', '每日'),
              ('weekly', '每周'),
              ('monthly', '每月'),
              ('yearly', '每年'),
              ('interval', '每隔 N 天'),
              ('restart', '完成后重计'),
              ('calendar', '指定日期'),
            ])
              ChoiceChip(
                key: ValueKey('cycle-$value'),
                label: Text(label),
                selected: cycle == value,
                onSelected: (_) => update(() => cycle = value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(switch (cycle) {
          'once' => '只发生一次，完成后不再产生新一期。',
          'restart' => '下一期从实际完成日期开始计算，例如充值保活。',
          'monthly' => '按自然月推进；月末日期在短月夹到月底，之后恢复。',
          'yearly' => '按自然年推进；2 月 29 日在非闰年按 2 月末处理。',
          'calendar' => '按列表中的日期依次推进。',
          _ => '按计划日历推进，晚确认不会改变原周期。',
        }, style: theme.textTheme.bodySmall),
        if (cycle == 'interval' || cycle == 'restart') ...[
          gap,
          input('days', '间隔天数', numeric: true, required: true, suffix: '天'),
        ],
        if (cycle == 'calendar') ...[
          gap,
          input('dates', '重复日期', hint: 'YYYY-MM-DD，以逗号分隔；首个日期与本期日期一致'),
        ],
        gap,
        dateRow(
          key: const ValueKey('start-date'),
          label: '周期起点',
          value: friendlyDate(start),
          detail: '用于计算进度，通常是上次事件日',
          icon: Icons.first_page,
          onTap: () => pickDate(isNext: false),
        ),

        section('提醒', note: '应用内计划 · 系统通知尚未接入'),
        Text('提前提醒', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in ({
              30,
              14,
              7,
              3,
              1,
              ...before,
            }.toList()..sort((a, b) => b.compareTo(a))))
              FilterChip(
                key: ValueKey('before-$n'),
                label: Text(n == 0 ? '当天' : '$n 天'),
                selected: before.contains(n),
                onSelected: (v) => update(() {
                  v ? before.add(n) : before.remove(n);
                  before.sort((a, b) => b.compareTo(a));
                }),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('自定义'),
              onPressed: addReminderDay,
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('事件当天提醒'),
          value: onDay,
          onChanged: (v) => update(() => onDay = v),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: input(
                'grace',
                '处理窗口',
                numeric: true,
                required: true,
                suffix: '天',
                hint: '事件后仍可处理',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: input(
                'repeat',
                '窗口内重复',
                numeric: true,
                suffix: '天',
                hint: '留空不重复',
              ),
            ),
          ],
        ),
      ],

      section(
        '资源账户',
        trailing: Switch(
          key: const ValueKey('toggle-resource'),
          value: resource,
          onChanged: (v) => update(() => resource = v),
        ),
      ),
      if (!resource)
        Text('金额、次数或有明确单位的额度；只管时间的事项不需要。', style: theme.textTheme.bodySmall),
      if (resource) ...[
        if (account != null)
          Panel(
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(store.state['accounts'][account]['name'] as String),
                subtitle: Text(
                  '当前 ${store.accountView(account!)['formatted']} ${store.accountView(account!)['unit']} · 余额在详情中调整',
                ),
              ),
            ],
          )
        else ...[
          SegmentedButton<String>(
            key: const ValueKey('account-kind'),
            segments: const [
              ButtonSegment(value: 'money', label: Text('金额')),
              ButtonSegment(value: 'count', label: Text('次数')),
              ButtonSegment(value: 'quantity', label: Text('数量 / 额度')),
            ],
            selected: {kind},
            showSelectedIcon: false,
            onSelectionChanged: (v) => update(() => kind = v.first),
          ),
          gap,
          if (kind == 'money')
            DropdownButtonFormField<String>(
              initialValue: unit,
              decoration: const InputDecoration(labelText: '币种'),
              items: [
                for (final c
                    in (store.snapshot['money_units'] as Map).keys
                        .cast<String>())
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => update(() => unit = v!),
            ),
          if (kind == 'quantity')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: input('unit', '单位', required: true, hint: '如 GB、积分'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: input(
                    'precision',
                    '小数位数',
                    numeric: true,
                    required: true,
                    hint: '0—6',
                  ),
                ),
              ],
            ),
          if (kind != 'count') gap,
          input(
            'initial',
            '初始余量',
            numeric: true,
            required: true,
            suffix: unitCode,
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: input(
                  'reference',
                  '参考总量',
                  hint: '可选，用于显示剩余比例',
                  numeric: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: input('low', '不足提醒', hint: '可选，低于即提示', numeric: true),
              ),
            ],
          ),
        ],
        if (timed) ...[
          const SizedBox(height: 16),
          Text('完成每一期时', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in [
                ('none', '不记录'),
                ('consume', consumeVerb),
                ('add', addVerb),
                ('reset', '恢复到额度'),
              ])
                ChoiceChip(
                  key: ValueKey('change-$value'),
                  label: Text(label),
                  selected: changeMode == value,
                  onSelected: (_) => update(() => changeMode = value),
                ),
            ],
          ),
          if (changeMode != 'none') ...[
            gap,
            input(
              'amount',
              changeMode == 'reset'
                  ? '恢复到'
                  : changeMode == 'consume'
                  ? '每期$consumeVerb'
                  : '每期$addVerb',
              numeric: true,
              required: true,
              suffix: unitCode,
              hint: '确认完成时记入实际流水；预测不会改变余额',
            ),
          ],
        ],
      ],

      section('更多'),
      input('notes', '备注', lines: 3),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('在主页置顶'),
        value: pinned,
        onChanged: (v) => update(() => pinned = v),
      ),
    ];
    return PopScope(
      canPop: saved || !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.editing ? '编辑规则' : '新建规则'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                key: const ValueKey('save-rule'),
                onPressed: busy ? null : save,
                style: FilledButton.styleFrom(minimumSize: const Size(64, 38)),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ),
          ],
          bottom: error == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Callout(
                      error!,
                      icon: Icons.error_outline,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
        ),
        body: Form(
          key: form,
          child: ListView(
            padding: pagePadding(context, top: 0),
            children: [
              for (final c in children) Readable(maxWidth: 680, child: c),
            ],
          ),
        ),
      ),
    );
  }
}
