// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'dart:convert';
import 'dart:math' as math;

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
    if (kind == 'money') '金额 ${account!['unit']['code']}',
    if (kind == 'count') '次数',
    if (kind == 'quantity') '额度 ${account!['unit']['code']}',
    if (c['reset'] != null) '每期恢复额度',
  ].join(' · ');
}

Future<void> openCreator(
  BuildContext context,
  SpanStore store, {
  Json? rule,
  String? project,
}) async {
  if (rule != null) {
    await push<void>(
      context,
      RuleEditor(store: store, initial: rule, editing: true),
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
    await push<void>(context, RuleEditor(store: store, initial: choice));
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
      VoidCallback onTap,
    ) => ListTile(
      leading: IconTile(icon),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text(
            '新建规则',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Panel(
            children: [
              ValueRow(
                '空白规则',
                key: const ValueKey('blank-rule'),
                icon: Icons.add,
                onTap: () => Navigator.pop(context, <String, dynamic>{}),
              ),
            ],
          ),
          if (custom.isNotEmpty) ...[
            const SectionHeader('我的模板', large: false),
            Panel(
              dividerIndent: 64,
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
                            '来自我的模板「${t['name']}」：模板保留保存时的日期，请核对本期日期与起算日。',
                    ),
                  ),
              ],
            ),
            const SectionFooter('模板保留保存时的日期，使用时请核对。'),
          ],
          for (final scene in order) ...[
            SectionHeader(scene, large: false),
            Panel(
              dividerIndent: 64,
              children: [
                for (final t in scenes[scene]!)
                  option(
                    ruleIcon(t['icon'] as String?),
                    t['name'] as String,
                    t['description'] as String? ??
                        configSummary(presetConfig(t)),
                    () => Navigator.pop(context, presetConfig(t)),
                  ),
              ],
            ),
          ],
          const SectionFooter('模板只预填内容，创建的都是普通规则，之后都能修改。'),
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

const _cycles = [
  ('once', '单次'),
  ('daily', '每日'),
  ('weekly', '每周'),
  ('monthly', '每月'),
  ('yearly', '每年'),
  ('interval', '每隔 N 天'),
  ('restart', '完成后重新计时'),
  ('calendar', '指定日期'),
];

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

  String? validate(String key, String label, String? value, bool required) {
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
  }

  /// Label on the left, borderless value on the right.
  Widget input(
    String key,
    String label, {
    String? hint,
    bool numeric = false,
    bool required = false,
    String? suffix,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: theme.textTheme.bodyLarge),
          ),
          Expanded(
            child: TextFormField(
              key: ValueKey('field-$key'),
              controller: field(key),
              textAlign: TextAlign.end,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.text,
              style: theme.textTheme.bodyLarge?.copyWith(fontFeatures: tabular),
              decoration: _bare.copyWith(
                hintText: hint ?? (required ? '必填' : '可选'),
                suffixText: suffix,
              ),
              validator: (value) => validate(key, label, value, required),
            ),
          ),
        ],
      ),
    );
  }

  static const _bare = InputDecoration(
    filled: false,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(vertical: 14),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );

  /// A row that opens a menu of choices.
  Widget choice<T>({
    required Key key,
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T> onSelected,
    String Function(T)? itemKey,
  }) => PopupMenuButton<T>(
    key: key,
    tooltip: label,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final (v, l) in options)
        CheckedPopupMenuItem(
          key: itemKey == null ? null : ValueKey(itemKey(v)),
          value: v,
          checked: v == value,
          child: Text(l),
        ),
    ],
    child: ValueRow(
      label,
      value: options
          .firstWhere((o) => o.$1 == value, orElse: () => options.first)
          .$2,
      trailing: Icon(
        Icons.unfold_more_rounded,
        size: 18,
        color: SpanColors.of(context).muted,
      ),
    ),
  );

  /// Label above a wrap of chips inside a card row.
  Widget chips(String label, List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    ),
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
      setState(() => error = '请检查标出的内容');
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
      if (mounted) notify(context, '提醒天数须为 0—36500 的整数');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    final store = widget.store;
    final today = dateOnly(DateTime.now());
    final daysToNext = DateTime.parse(next)
        .difference(DateTime.parse(today))
        .inDays;
    final (addVerb, consumeVerb) = resourceVerbs(kind);
    final children = <Widget>[
      if (widget.initial['guidance'] != null) ...[
        Callout(widget.initial['guidance'] as String),
        const SizedBox(height: 12),
      ],
      if (error != null) ...[
        Callout(
          error!,
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 12),
      ],
      Panel(
        children: [
          TextFormField(
            key: const ValueKey('field-name'),
            controller: field('name'),
            autofocus: !widget.editing && field('name').text.isEmpty,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            textInputAction: TextInputAction.next,
            decoration: _bare.copyWith(
              hintText: '名称',
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            ),
            validator: (value) => validate('name', '名称', value, true),
          ),
          TextFormField(
            key: const ValueKey('field-notes'),
            controller: field('notes'),
            minLines: 1,
            maxLines: 8,
            style: theme.textTheme.bodyLarge,
            decoration: _bare.copyWith(
              hintText: '备注',
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            ),
          ),
        ],
      ),

      const SectionHeader('日期', large: false),
      Panel(
        children: [
          SwitchRow(
            '按日期管理',
            switchKey: const ValueKey('toggle-timed'),
            value: timed,
            onChanged: (v) => update(() => timed = v),
          ),
          if (timed) ...[
            ValueRow(
              '本期事件日期',
              key: const ValueKey('next-date'),
              value: ended
                  ? '周期已结束'
                  : '${friendlyDate(next, weekday: false)} · ${relativeDays(daysToNext)}',
              valueColor: ended ? null : theme.colorScheme.primary,
              chevron: false,
              onTap: () => pickDate(isNext: true),
            ),
            choice<String>(
              key: const ValueKey('cycle-menu'),
              label: '重复',
              value: cycle,
              options: _cycles,
              itemKey: (v) => 'cycle-$v',
              onSelected: (v) => update(() => cycle = v),
            ),
            if (cycle == 'interval' || cycle == 'restart')
              input('days', '间隔', numeric: true, required: true, suffix: '天'),
            if (cycle == 'calendar')
              input('dates', '日期列表', hint: 'YYYY-MM-DD，逗号分隔'),
            ValueRow(
              '起算日',
              key: const ValueKey('start-date'),
              value: friendlyDate(start),
              valueColor: theme.colorScheme.primary,
              chevron: false,
              onTap: () => pickDate(isNext: false),
            ),
          ],
        ],
      ),
      SectionFooter(
        !timed
            ? '关闭后只记录资源与历史。'
            : ended
            ? '点按日期重新安排；只改名称等信息不会产生新的一期。'
            : switch (cycle) {
                'once' => '只发生一次，完成后结束。起算日用于计算进度。',
                'restart' => '下一期从实际完成日期起算，适合充值保活、定期更换。',
                'monthly' => '按自然月推进；月末日期在短月取当月最后一天。',
                'yearly' => '按自然年推进；2 月 29 日在非闰年按 2 月末处理。',
                'calendar' => '按列表中的日期依次推进，第一个日期应与本期日期一致。',
                _ => '按计划日期推进，晚确认不会改变原周期。',
              },
      ),
      if (timed && !ended && daysToNext < 0) ...[
        const SizedBox(height: 10),
        Callout(
          '日期早于今天，保存后会立即显示为逾期或处理窗口。',
          icon: Icons.warning_amber_rounded,
          color: warningColor(context),
        ),
      ],

      if (timed) ...[
        const SectionHeader('提醒', large: false),
        Panel(
          children: [
            chips('提前提醒', [
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
                  label: SpanChipLabel(
                    n == 0 ? '当天' : '$n 天',
                    selected: before.contains(n),
                  ),
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
            ]),
            SwitchRow(
              '当天提醒',
              value: onDay,
              onChanged: (v) => update(() => onDay = v),
            ),
            input('grace', '处理窗口', numeric: true, required: true, suffix: '天'),
            input('repeat', '窗口内重复', numeric: true, hint: '不重复', suffix: '天'),
          ],
        ),
        const SectionFooter('处理窗口是事件之后仍可处理的天数。提醒只在应用内显示，系统通知尚未接入。'),
      ],

      const SectionHeader('资源', large: false),
      Panel(
        children: [
          SwitchRow(
            '记录余额或次数',
            switchKey: const ValueKey('toggle-resource'),
            value: resource,
            onChanged: (v) => update(() => resource = v),
          ),
          if (resource && account != null)
            ValueRow(
              store.state['accounts'][account]['name'] as String,
              value:
                  '${store.accountView(account!)['formatted']} ${store.accountView(account!)['unit']}',
            ),
          if (resource && account == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: SegmentedButton<String>(
                key: const ValueKey('account-kind'),
                segments: const [
                  ButtonSegment(value: 'money', label: Text('金额')),
                  ButtonSegment(value: 'count', label: Text('次数')),
                  ButtonSegment(value: 'quantity', label: Text('额度')),
                ],
                selected: {kind},
                showSelectedIcon: false,
                onSelectionChanged: (v) => update(() => kind = v.first),
              ),
            ),
            if (kind == 'money')
              choice<String>(
                key: const ValueKey('currency-menu'),
                label: '币种',
                value: unit,
                options: [
                  for (final c
                      in (store.snapshot['money_units'] as Map).keys
                          .cast<String>())
                    (c, c),
                ],
                onSelected: (v) => update(() => unit = v),
              ),
            if (kind == 'quantity') ...[
              input('unit', '单位', required: true, hint: '如 GB、积分'),
              input('precision', '小数位数', numeric: true, required: true),
            ],
            input(
              'initial',
              '初始余量',
              numeric: true,
              required: true,
              suffix: unitCode,
            ),
            input('reference', '参考总量', numeric: true),
            input('low', '低于时提醒', numeric: true),
          ],
          if (resource && timed) ...[
            chips('每期完成时', [
              for (final (value, label) in [
                ('none', '不记录'),
                ('consume', consumeVerb),
                ('add', addVerb),
                ('reset', '恢复到额度'),
              ])
                ChoiceChip(
                  key: ValueKey('change-$value'),
                  label: SpanChipLabel(label, selected: changeMode == value),
                  selected: changeMode == value,
                  onSelected: (_) => update(() => changeMode = value),
                ),
            ]),
            if (changeMode != 'none')
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
              ),
          ],
        ],
      ),
      SectionFooter(
        !resource
            ? '金额、次数或有单位的额度；只管时间的事项不需要。'
            : account != null
            ? '余额在规则详情中调整。'
            : '参考总量用于显示剩余比例。完成每期时记入实际流水，预测不会改变余额。',
      ),

      const SectionHeader('整理', large: false),
      Panel(
        children: [
          if (widget.initial['group'] == null)
            choice<String>(
              key: const ValueKey('project-menu'),
              label: '文件夹',
              value: project ?? '',
              options: [
                ('', '未归类'),
                for (final p in store.projects)
                  (p['id'] as String, p['name'] as String),
              ],
              onSelected: (v) => update(() => project = v == '' ? null : v),
            )
          else
            const ValueRow('文件夹', value: '随所在合并条目'),
          chips('标签', [
            for (final t in store.tags)
              FilterChip(
                label: SpanChipLabel(
                  '#${t['name']}',
                  selected: tags.contains(t['id']),
                ),
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
          ]),
          SwitchRow(
            '在主页置顶',
            value: pinned,
            onChanged: (v) => update(() => pinned = v),
          ),
        ],
      ),
    ];
    return PopScope(
      canPop: saved || !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          leadingWidth: 76,
          leading: TextButton(
            key: const ValueKey('cancel-rule'),
            onPressed: () => Navigator.maybePop(context),
            child: const Text('取消'),
          ),
          title: Text(widget.editing ? '编辑规则' : '新建规则'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton(
                key: const ValueKey('save-rule'),
                onPressed: busy ? null : save,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '保存',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
        body: Form(
          key: form,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.max(gutter, (constraints.maxWidth - 680) / 2);
              // Every field stays built so validation covers off-screen rows.
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  side,
                  8,
                  side,
                  MediaQuery.paddingOf(context).bottom + 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
