// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'backup.dart';
import 'data.dart';
import 'design.dart';
import 'details.dart';
import 'editor.dart';
import 'entries.dart';

class Profile extends StatelessWidget {
  final SpanStore store;
  const Profile({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = objects(store.state['templates']);
    Widget row(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap, {
      Key? key,
      bool chevron = true,
    }) => ListTile(
      key: key,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: chevron ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
    final children = <Widget>[
      Padding(
        key: const ValueKey('page-profile'),
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('我的', style: theme.textTheme.headlineMedium),
            ),
            const SizedBox(height: 2),
            Text('数据只保存在本机，每一次变化都有记录。', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      const SectionHeader('外观'),
      Panel(
        padding: const EdgeInsets.all(16),
        dividerIndent: -1,
        children: [
          SegmentedButton<String>(
            key: const ValueKey('theme-mode'),
            segments: const [
              ButtonSegment(value: 'system', label: Text('跟随系统')),
              ButtonSegment(value: 'light', label: Text('浅色')),
              ButtonSegment(value: 'dark', label: Text('深色')),
            ],
            selected: {store.setting('theme', 'system')},
            showSelectedIcon: false,
            onSelectionChanged: (v) => perform(
              context,
              () => store.mutate('setting', {'key': 'theme', 'value': v.first}),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 4 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              final selected = SpanPalette.parse(
                store.setting('palette', 'lucent'),
              );
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final palette in SpanPalette.values)
                    SizedBox(
                      width: width,
                      child: _PaletteOption(
                        palette: palette,
                        selected: selected == palette,
                        onTap: () => perform(
                          context,
                          () => store.mutate('setting', {
                            'key': 'palette',
                            'value': palette.name,
                          }),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text('配色与明暗模式相互独立。', style: theme.textTheme.bodySmall),
        ],
      ),
      const SectionHeader('整理'),
      Panel(
        children: [
          row(
            Icons.sell_outlined,
            '标签',
            store.tags.isEmpty ? '跨小项目筛选规则' : '${store.tags.length} 个标签',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => TagManager(store: store)),
            ),
            key: const ValueKey('open-tags'),
          ),
          row(
            Icons.bookmarks_outlined,
            '我的模板',
            templates.isEmpty ? '在规则详情中“保存为模板”' : '${templates.length} 个模板',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => TemplateManager(store: store),
              ),
            ),
          ),
          row(
            Icons.notifications_none,
            '提醒计划',
            '未来 90 天的应用内提醒 · 系统通知尚未接入',
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReminderPlanPage(store: store),
              ),
            ),
          ),
        ],
      ),
      const SectionHeader('数据'),
      Panel(
        children: [
          row(
            Icons.file_upload_outlined,
            '导出完整备份',
            '规则、账户、流水、事件、模板与设置',
            () => perform(context, () async {
              if (await exportBackup(store) && context.mounted) {
                notify(context, '备份已导出');
              }
            }),
            chevron: false,
          ),
          row(
            Icons.settings_backup_restore,
            '从备份恢复',
            '先完整校验；恢复前的数据保存在本机检查点',
            () => perform(context, () async {
              final baseRevision = store.revision;
              await selectBackupFile((path) async {
                final preview = await store.read('validate_backup', {
                  'path': path,
                });
                if (context.mounted &&
                    await confirm(
                      context,
                      '用此备份替换当前数据？',
                      '备份包含 ${preview['rules']} 条规则、${preview['accounts']} 个账户、${preview['history']} 条历史。\n\n当前数据将被整体替换；替换前的数据保存在本机检查点（暂无应用内回退入口）。',
                      action: '替换并恢复',
                      destructive: true,
                    )) {
                  await store.mutate('restore', {
                    'path': path,
                  }, baseRevision: baseRevision);
                  if (context.mounted) notify(context, '备份已恢复');
                }
              });
            }),
            chevron: false,
          ),
        ],
      ),
      const SectionHeader('关于'),
      Panel(
        children: [
          row(
            Icons.all_inclusive,
            'ASpan',
            '$releaseVersion · 离线生命周期管理',
            () => showAboutDialog(
              context: context,
              applicationName: 'ASpan',
              applicationVersion: releaseVersion,
              applicationIcon: Icon(
                Icons.all_inclusive,
                color: theme.colorScheme.primary,
                size: 36,
              ),
              children: [
                const Text(
                  '还剩多少时间、还剩多少资源、什么时候需要处理，以及过去发生了什么。\n\n当前版本：纯日期与本地记录可用，系统通知和时刻/时区尚未实现。',
                ),
                const SizedBox(height: 12),
                const SelectableText(
                  '构建源码：${String.fromEnvironment('ASPAN_COMMIT', defaultValue: '开发工作区')}',
                ),
              ],
            ),
          ),
        ],
      ),
    ];
    return ListView(
      padding: pagePadding(context),
      children: [for (final c in children) Readable(child: c)],
    );
  }
}

class _PaletteOption extends StatelessWidget {
  final SpanPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _PaletteOption({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (tokens, accent, text) = paletteColors(
      palette,
      Theme.of(context).brightness,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        key: ValueKey('palette-${palette.name}'),
        color: tokens.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? accent : tokens.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Stack(
                      children: [
                        CircleAvatar(radius: 14, backgroundColor: tokens.soft),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: CircleAvatar(
                            radius: 8,
                            backgroundColor: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        palette.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: text,
                        ),
                      ),
                      Text(
                        palette.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tokens.muted),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 18, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const tagSwatches = [
  '2164C7',
  '0E7C86',
  '2E7D4F',
  'A86B00',
  'C2410C',
  'B42318',
  'A13E8C',
  '6D5BD0',
  '5B6472',
];

/// Name and color edited together; delete lives with the thing it deletes.
Future<void> tagSheet(
  BuildContext context,
  SpanStore store, [
  Json? tag,
]) async {
  final baseRevision = store.revision;
  var color = tag?['color'] as String? ?? tagSwatches.first;
  String? error;
  final result = await showSpanSheet<String>(
    context,
    (context) => TextControllerScope(
      initial: tag?['name'] as String? ?? '',
      builder: (context, name) => StatefulBuilder(
        builder: (context, setState) => SheetBody(
          title: tag == null ? '新建标签' : '编辑标签',
          subtitle: '标签可跨小项目筛选；合并条目显示成员标签的并集',
          content: [
            TextField(
              key: const ValueKey('tag-name'),
              controller: name,
              autofocus: tag == null,
              decoration: InputDecoration(labelText: '名称', errorText: error),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in {...tagSwatches, color})
                  Semantics(
                    button: true,
                    selected: color == c,
                    label: '颜色 #$c',
                    child: InkResponse(
                      onTap: () => setState(() => color = c),
                      radius: 24,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tagColor({'color': c}),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: color == c
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (tag != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, '__delete__'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除标签'),
                ),
              ),
            ],
          ],
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setState(() => error = '请填写名称');
                  return;
                }
                Navigator.pop(context, name.text.trim());
              },
              child: Text(tag == null ? '创建' : '保存'),
            ),
          ],
        ),
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  if (result == '__delete__') {
    if (await confirm(
          context,
          '删除标签「${tag!['name']}」？',
          '规则保留，只移除这个标签的关联。',
          action: '删除',
          destructive: true,
        ) &&
        context.mounted) {
      await perform(
        context,
        () => store.mutate('delete_tag', {
          'id': tag['id'],
        }, baseRevision: baseRevision),
        success: '标签已删除',
      );
    }
    return;
  }
  await perform(
    context,
    () => store.mutate('save_tag', {
      if (tag != null) 'id': tag['id'],
      'name': result,
      'color': color,
    }, baseRevision: baseRevision),
  );
}

class TagManager extends StatelessWidget {
  final SpanStore store;
  const TagManager({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final counts = <String, int>{};
      for (final r in store.rules) {
        for (final t in r['tags'] as List) {
          counts[t as String] = (counts[t] ?? 0) + 1;
        }
      }
      return Scaffold(
        appBar: AppBar(title: const Text('标签')),
        body: ListView(
          padding: pagePadding(context, fab: true),
          children: [
            Readable(
              child: store.tags.isEmpty
                  ? const EmptyState(
                      '还没有标签',
                      '标签不受小项目限制，例如“家庭”“工作”“每年一次”。',
                      icon: Icons.sell_outlined,
                    )
                  : Panel(
                      children: [
                        for (final t in store.tags)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: tagColor(t),
                              radius: 8,
                            ),
                            title: Text(t['name'] as String),
                            subtitle: Text('${counts[t['id']] ?? 0} 条规则'),
                            trailing: IconButton(
                              tooltip: '查看相关规则',
                              onPressed: () => openTag(context, store, t),
                              icon: const Icon(Icons.filter_list),
                            ),
                            onTap: () => tagSheet(context, store, t),
                          ),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => tagSheet(context, store),
          icon: const Icon(Icons.add),
          label: const Text('新建标签'),
        ),
      );
    },
  );
}

class TemplateManager extends StatelessWidget {
  final SpanStore store;
  const TemplateManager({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final templates = objects(store.state['templates']);
      return Scaffold(
        appBar: AppBar(title: const Text('我的模板')),
        body: ListView(
          padding: pagePadding(context),
          children: [
            Readable(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Callout(
                    '模板只保存配置，点按即可用它新建规则；完整复制才会保留余额与历史。模板保留保存时的日期，使用时请核对。',
                  ),
                  const SizedBox(height: 12),
                  if (templates.isEmpty)
                    const EmptyState(
                      '还没有模板',
                      '在规则详情右上角菜单中选择“保存为模板”。',
                      icon: Icons.bookmarks_outlined,
                    )
                  else
                    Panel(
                      children: [
                        for (final t in templates)
                          ListTile(
                            leading: const Icon(Icons.bookmark_outline),
                            title: Text(t['name'] as String),
                            subtitle: Text(configSummary(object(t['config']))),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => RuleEditor(
                                  store: store,
                                  initial: object(t['config'])
                                    ..['guidance'] =
                                        '来自我的模板「${t['name']}」：请核对本期日期与起点。',
                                ),
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: '模板操作',
                              onSelected: (v) => perform(context, () async {
                                final baseRevision = store.revision;
                                if (v == 'rename') {
                                  final name = await askText(
                                    context,
                                    '重命名模板',
                                    initial: t['name'] as String,
                                    action: '保存',
                                  );
                                  if (name != null) {
                                    await store.mutate('save_template', {
                                      'id': t['id'],
                                      'name': name,
                                      'config': t['config'],
                                    }, baseRevision: baseRevision);
                                  }
                                }
                                if (v == 'delete' &&
                                    context.mounted &&
                                    await confirm(
                                      context,
                                      '删除模板「${t['name']}」？',
                                      '已用它创建的规则不受影响。',
                                      action: '删除',
                                      destructive: true,
                                    )) {
                                  await store.mutate('delete_template', {
                                    'id': t['id'],
                                  }, baseRevision: baseRevision);
                                }
                              }),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The reminder plan grouped by day, each entry leading to its rule.
class ReminderPlanPage extends StatefulWidget {
  final SpanStore store;
  const ReminderPlanPage({super.key, required this.store});
  @override
  State<ReminderPlanPage> createState() => _ReminderPlanPageState();
}

class _ReminderPlanPageState extends State<ReminderPlanPage> {
  late Future<dynamic> plan = widget.store.read('reminder_plan');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提醒计划')),
    body: FutureBuilder<dynamic>(
      future: plan,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            '无法读取提醒计划',
            errorMessage(snapshot.error!),
            icon: Icons.error_outline,
            action: OutlinedButton(
              onPressed: () =>
                  setState(() => plan = widget.store.read('reminder_plan')),
              child: const Text('重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notifications =
            (snapshot.data['notifications'] as List).map(object).toList()..sort(
              (a, b) => (a['date'] as String).compareTo(b['date'] as String),
            );
        final days = <String, List<Json>>{};
        for (final n in notifications) {
          (days[n['date'] as String] ??= []).add(n);
        }
        return ListView(
          padding: pagePadding(context),
          children: [
            Readable(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Callout(snapshot.data['note'] as String),
                  if (days.isEmpty)
                    const EmptyState(
                      '未来 90 天没有提醒',
                      '在规则中设置提前提醒或当天提醒后会出现在这里。',
                      icon: Icons.notifications_off_outlined,
                    ),
                  for (final entry in days.entries) ...[
                    SectionHeader(friendlyDate(entry.key)),
                    Panel(
                      children: [
                        for (final n in entry.value)
                          ListTile(
                            leading: const Icon(Icons.notifications_none),
                            title: Text(n['title'] as String),
                            subtitle: Text(
                              '事件 ${friendlyDate((n['occurrence'] as String).split('@').last)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => openRule(
                              context,
                              widget.store,
                              n['rule'] as String,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
