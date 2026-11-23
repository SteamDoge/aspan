// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'backup.dart';
import 'data.dart';
import 'design.dart';
import 'details.dart';
import 'editor.dart';
import 'entries.dart';

/// The 我的 tab: appearance, organizing tools, data and about.
class SettingsPage extends StatelessWidget {
  final SpanStore store;
  const SettingsPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final theme = Theme.of(context);
      final templates = objects(store.state['templates']);
      final selected = SpanPalette.parse(store.setting('palette', 'lucent'));
      return SpanPage(
        title: '我的',
        titleKey: const ValueKey('page-profile'),
        maxWidth: 680,
        slivers: [
          boxes([
            // Same order as AQ's 我的: content sections first, then 外观,
            // then the version line.
            const SectionHeader('整理', large: false),
            Panel(
              dividerIndent: 52,
              children: [
                ValueRow(
                  '标签',
                  key: const ValueKey('open-tags'),
                  icon: Icons.sell_outlined,
                  value: '${store.tags.length}',
                  onTap: () => push(context, TagManager(store: store)),
                ),
                ValueRow(
                  '我的模板',
                  icon: Icons.bookmarks_outlined,
                  value: '${templates.length}',
                  onTap: () => push(context, TemplateManager(store: store)),
                ),
                ValueRow(
                  '提醒计划',
                  icon: Icons.notifications_none,
                  onTap: () => push(context, ReminderPlanPage(store: store)),
                ),
              ],
            ),
            const SectionFooter('提醒计划列出未来 90 天的应用内提醒；系统通知尚未接入。'),
            const SectionHeader('数据', large: false),
            Panel(
              dividerIndent: 52,
              children: [
                ValueRow(
                  '导出完整备份',
                  key: const ValueKey('export-backup'),
                  icon: Icons.ios_share,
                  onTap: () => perform(context, () async {
                    if (await exportBackup(store) && context.mounted) {
                      notify(context, '备份已导出');
                    }
                  }),
                ),
                ValueRow(
                  '从备份恢复',
                  key: const ValueKey('restore-backup'),
                  icon: Icons.settings_backup_restore,
                  onTap: () => perform(context, () async {
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
                            action: '替换',
                            destructive: true,
                          )) {
                        await store.mutate('restore', {
                          'path': path,
                        }, baseRevision: baseRevision);
                        if (context.mounted) notify(context, '备份已恢复');
                      }
                    });
                  }),
                ),
              ],
            ),
            const SectionFooter('数据只保存在本机。备份包含规则、账户、流水、模板与设置；恢复前会完整校验。'),
            const SectionHeader('外观', large: false),
            Panel(
              dividerIndent: 52,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ThemeModeControl(store: store),
                ),
                ValueRow(
                  '颜色主题',
                  key: const ValueKey('open-appearance'),
                  icon: Icons.palette_outlined,
                  value: selected.label,
                  onTap: () => push(context, AppearancePage(store: store)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Semantics(
              button: true,
              label: '关于 ASpan',
              child: InkWell(
                key: const ValueKey('about'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => showAboutDialog(
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ASpan  $releaseVersion',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '本机数据 · 无需登录 · 可离线使用',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      );
    },
  );
}

/// The light/dark choice as one full-width segmented control, worded and
/// laid out as in AQ.
class ThemeModeControl extends StatelessWidget {
  final SpanStore store;
  const ThemeModeControl({super.key, required this.store});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<String>(
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
  );
}

/// 外观: light/dark, then the color themes as one grouped selection list,
/// matching AQ's appearance page.
class AppearancePage extends StatelessWidget {
  final SpanStore store;
  const AppearancePage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final selected = SpanPalette.parse(store.setting('palette', 'lucent'));
      return SpanPage(
        title: '外观',
        maxWidth: 640,
        slivers: [
          boxes([
            const SectionHeader('明暗', large: false),
            ThemeModeControl(store: store),
            const SectionHeader('颜色主题', large: false),
            Panel(
              dividerIndent: 58,
              children: [
                for (final palette in SpanPalette.values)
                  _PaletteRow(
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
              ],
            ),
            const SectionFooter('只改变应用界面配色，与明暗模式相互独立。'),
          ]),
        ],
      );
    },
  );
}

class _PaletteRow extends StatelessWidget {
  final SpanPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _PaletteRow({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tokens, accent, _) = paletteColors(palette, theme.brightness);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('palette-${palette.name}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.background,
                      border: Border.all(color: SpanColors.of(context).line),
                    ),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(palette.label, style: theme.textTheme.bodyLarge),
                      Text(
                        palette.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: Icon(
                    Icons.check,
                    size: 22,
                    color: theme.colorScheme.primary,
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
          subtitle: '标签不受文件夹限制，可跨文件夹查看规则',
          content: [
            TextField(
              key: const ValueKey('tag-name'),
              controller: name,
              autofocus: tag == null,
              decoration: InputDecoration(
                hintText: '名称',
                errorText: error,
                fillColor: SpanColors.of(context).panel,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
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
                        width: 34,
                        height: 34,
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
              Panel(
                children: [
                  ValueRow(
                    '删除标签',
                    icon: Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                    chevron: false,
                    onTap: () => Navigator.pop(context, '__delete__'),
                  ),
                ],
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
      return SpanPage(
        title: '标签',
        maxWidth: 680,
        floatingActionButton: AddButton(
          key: const ValueKey('new-tag'),
          tooltip: '新建标签',
          onPressed: () => tagSheet(context, store),
        ),
        slivers: [
          boxes([
            const SizedBox(height: 12),
            if (store.tags.isEmpty)
              const EmptyState(
                '还没有标签',
                '标签不受文件夹限制，例如“家庭”“工作”“每年一次”。',
                icon: Icons.sell_outlined,
              )
            else ...[
              ...groupedTiles(
                store.tags,
                (t, f, l) => GroupedTile(
                  first: f,
                  last: l,
                  indent: 44,
                  onTap: () => openTag(context, store, t),
                  onMenu: (_) => tagSheet(context, store, t),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      CircleAvatar(backgroundColor: tagColor(t), radius: 7),
                      Expanded(
                        child: ValueRow(
                          t['name'] as String,
                          value: '${counts[t['id']] ?? 0}',
                          trailing: IconButton(
                            tooltip: '编辑标签',
                            onPressed: () => tagSheet(context, store, t),
                            icon: const Icon(Icons.info_outline, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionFooter('点按查看相关规则；长按或点 ⓘ 编辑名称与颜色。'),
            ],
          ]),
        ],
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
      return SpanPage(
        title: '我的模板',
        maxWidth: 680,
        slivers: [
          boxes([
            const SizedBox(height: 12),
            if (templates.isEmpty)
              const EmptyState(
                '还没有模板',
                '在规则详情的“更多”菜单中选择“存为模板”。',
                icon: Icons.bookmarks_outlined,
              )
            else ...[
              Panel(
                children: [
                  for (final t in templates)
                    ListTile(
                      title: Text(t['name'] as String),
                      subtitle: Text(configSummary(object(t['config']))),
                      onTap: () => push(
                        context,
                        RuleEditor(
                          store: store,
                          initial: object(
                            t['config'],
                          )..['guidance'] = '来自我的模板「${t['name']}」：请核对本期日期与起算日。',
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: '模板操作',
                        icon: const Icon(Icons.more_horiz_rounded),
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
                        itemBuilder: (_) => [
                          menuItem(
                            'rename',
                            '重命名',
                            Icons.drive_file_rename_outline,
                          ),
                          menuItem(
                            'delete',
                            '删除',
                            Icons.delete_outline,
                            destructive: true,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SectionFooter(
                '模板只保存配置，点按即可用它新建规则；完整复制才会保留余额与历史。模板保留保存时的日期，使用时请核对。',
              ),
            ],
          ]),
        ],
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
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: plan,
    builder: (context, snapshot) {
      final List<Widget> content;
      if (snapshot.hasError) {
        content = [
          EmptyState(
            '无法读取提醒计划',
            errorMessage(snapshot.error!),
            icon: Icons.error_outline,
            action: OutlinedButton(
              onPressed: () =>
                  setState(() => plan = widget.store.read('reminder_plan')),
              child: const Text('重试'),
            ),
          ),
        ];
      } else if (!snapshot.hasData) {
        content = [
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      } else {
        final notifications =
            (snapshot.data['notifications'] as List).map(object).toList()..sort(
              (a, b) => (a['date'] as String).compareTo(b['date'] as String),
            );
        final days = <String, List<Json>>{};
        for (final n in notifications) {
          (days[n['date'] as String] ??= []).add(n);
        }
        content = [
          if (days.isEmpty)
            const EmptyState(
              '未来 90 天没有提醒',
              '在规则中设置提前提醒或当天提醒后会出现在这里。',
              icon: Icons.notifications_off_outlined,
            ),
          for (final entry in days.entries) ...[
            SectionHeader(friendlyDate(entry.key), large: false),
            Panel(
              children: [
                for (final n in entry.value)
                  ValueRow(
                    n['title'] as String,
                    value:
                        '事件 ${friendlyDate((n['occurrence'] as String).split('@').last, weekday: false)}',
                    onTap: () =>
                        openRule(context, widget.store, n['rule'] as String),
                  ),
              ],
            ),
          ],
          SectionFooter(snapshot.data['note'] as String),
        ];
      }
      return SpanPage(title: '提醒计划', maxWidth: 680, slivers: [boxes(content)]);
    },
  );
}
