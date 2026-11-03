// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'data.dart';
import 'design.dart';
import 'details.dart';
import 'editor.dart';
import 'widgets.dart';

void openOverview(BuildContext context, SpanStore store) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => EntryBrowser(store: store, title: '全部规则', overview: true),
  ),
);

void openTag(BuildContext context, SpanStore store, Json tag) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => EntryBrowser(
      store: store,
      title: '# ${tag['name']}',
      tag: tag['id'] as String,
    ),
  ),
);

void openProject(BuildContext context, SpanStore store, Json project) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EntryBrowser(
          store: store,
          title: project['name'] as String,
          project: project['id'] as String,
        ),
      ),
    );

Color tagColor(Json tag) =>
    Color(int.tryParse('FF${tag['color']}', radix: 16) ?? 0xFF2164C7);

enum _Mode { browse, select, reorder }

/// File-manager style browser used for the project root, a folder, a tag
/// and the overview. One list component, one set of controls.
class EntryBrowser extends StatefulWidget {
  final SpanStore store;
  final String title;
  final String? project, tag;
  final bool overview, embedded;
  final ValueChanged<bool>? onModeChanged;
  const EntryBrowser({
    super.key,
    required this.store,
    this.title = '项目',
    this.project,
    this.tag,
    this.overview = false,
    this.embedded = false,
    this.onModeChanged,
  });
  @override
  State<EntryBrowser> createState() => _EntryBrowserState();
}

class _EntryBrowserState extends State<EntryBrowser> {
  final search = TextEditingController();
  String query = '';
  _Mode mode = _Mode.browse;
  final Set<String> selected = {}, toggled = {};
  SpanStore get store => widget.store;
  bool get root =>
      widget.embedded &&
      !widget.overview &&
      widget.tag == null &&
      widget.project == null;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void setMode(_Mode next) {
    setState(() {
      mode = next;
      selected.clear();
    });
    widget.onModeChanged?.call(next != _Mode.browse);
  }

  Future<void> startReorder() async {
    if (store.setting('sort', 'manual') != 'manual') {
      await perform(
        context,
        () => store.mutate('setting', {'key': 'sort', 'value': 'manual'}),
        success: '已切换为手动排序，原手动顺序保留',
      );
    }
    if (mounted) setMode(_Mode.reorder);
  }

  bool matches(Json r) =>
      (widget.tag == null ||
          List<String>.from(r['tags']).contains(widget.tag)) &&
      ('${r['name']} ${r['notes']}').toLowerCase().contains(
        query.trim().toLowerCase(),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final searchingAll = root && query.trim().isNotEmpty;
      final all = store.rules
          .where(
            (r) =>
                widget.overview ||
                widget.tag != null ||
                searchingAll ||
                r['project'] == widget.project,
          )
          .toList();
      final top = store.ordered([
        for (final r in all)
          if (r['group'] == null && matches(r)) r,
        for (final g in store.groups)
          if (all.any((r) => r['group'] == g['id'] && matches(r))) g,
      ]);
      final manual = store.setting('sort', 'manual') == 'manual';
      final reordering = mode == _Mode.reorder && manual;
      final viewRevision = store.revision;
      final expandByDefault =
          widget.overview || widget.tag != null || query.trim().isNotEmpty;

      void reorder(int oldIndex, int newIndex) {
        if (!reordering || oldIndex == newIndex) return;
        final ids = top.map((e) => e['id'] as String).toList();
        ids.insert(newIndex, ids.removeAt(oldIndex));
        perform(
          context,
          () =>
              store.mutate('reorder', {'ids': ids}, baseRevision: viewRevision),
        );
      }

      void toggleSelect(String id) => setState(
        () => selected.contains(id) ? selected.remove(id) : selected.add(id),
      );

      Widget member(Json r) => RuleTile(
        store: store,
        rule: r,
        onTap: () => openRule(context, store, r['id'] as String),
      );

      Widget entry(Json item, int index) {
        final id = item['id'] as String;
        Widget strip;
        if (!item.containsKey('accounts')) {
          final selecting = mode == _Mode.select;
          strip = RuleTile(
            store: store,
            rule: item,
            dense: reordering,
            selected: selecting && selected.contains(id),
            onTap: () =>
                selecting ? toggleSelect(id) : openRule(context, store, id),
            onLongPress: mode == _Mode.browse
                ? () {
                    setMode(_Mode.select);
                    toggleSelect(id);
                  }
                : null,
            trailing: selecting
                ? Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Icon(
                      selected.contains(id)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected.contains(id)
                          ? Theme.of(context).colorScheme.primary
                          : SpanColors.of(context).muted,
                    ),
                  )
                : null,
          );
        } else {
          final members = store.ordered(
            all.where((r) => r['group'] == id && matches(r)).toList(),
          );
          strip = GroupTile(
            store: store,
            group: item,
            members: members,
            dimmed: mode == _Mode.select,
            expanded: !reordering && (expandByDefault ^ toggled.contains(id)),
            onTap: () {
              if (mode == _Mode.browse) openGroup(context, store, id);
            },
            onToggle: mode == _Mode.browse
                ? () => setState(
                    () => toggled.contains(id)
                        ? toggled.remove(id)
                        : toggled.add(id),
                  )
                : null,
            memberBuilder: member,
          );
        }
        if (!reordering) return strip;
        return Row(
          children: [
            Expanded(child: strip),
            IconButton(
              tooltip: '上移',
              onPressed: index > 0 ? () => reorder(index, index - 1) : null,
              icon: const Icon(Icons.arrow_upward, size: 20),
            ),
            IconButton(
              tooltip: '下移',
              onPressed: index + 1 < top.length
                  ? () => reorder(index, index + 1)
                  : null,
              icon: const Icon(Icons.arrow_downward, size: 20),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Tooltip(
                message: '拖动排序',
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
            ),
          ],
        );
      }

      final sortButton = SortButton(store: store);
      final moreMenu = PopupMenuButton<String>(
        key: const ValueKey('entries-menu'),
        tooltip: '更多操作',
        icon: const Icon(Icons.more_horiz),
        onSelected: (value) async {
          switch (value) {
            case 'select':
              setMode(_Mode.select);
            case 'reorder':
              await startReorder();
            case 'project':
              await createProject(context, store);
            case 'rename':
              await renameProject(context, store, widget.project!);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'select',
            child: ListTile(
              leading: Icon(Icons.call_merge),
              title: Text('选择并合并'),
            ),
          ),
          PopupMenuItem(
            value: 'reorder',
            enabled: top.length > 1,
            child: const ListTile(
              leading: Icon(Icons.swap_vert),
              title: Text('调整顺序'),
            ),
          ),
          if (root)
            const PopupMenuItem(
              value: 'project',
              child: ListTile(
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('新建小项目'),
              ),
            ),
          if (widget.project != null)
            const PopupMenuItem(
              value: 'rename',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('重命名小项目'),
              ),
            ),
        ],
      );

      final searchField = Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: TextField(
          key: const ValueKey('entry-search'),
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: root ? '搜索全部规则' : '在${widget.title}中搜索',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () => setState(() {
                      search.clear();
                      query = '';
                    }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
      );

      final listTitle = searchingAll
          ? '搜索结果'
          : root
          ? '未归类'
          : widget.overview
          ? '全部条目'
          : '条目';
      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (root)
            Padding(
              key: const ValueKey('page-projects'),
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        '项目',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                  moreMenu,
                ],
              ),
            ),
          searchField,
          if (root && !searchingAll) ...[
            const SizedBox(height: 12),
            FolderGrid(store: store),
            if (store.tags.isNotEmpty) ...[
              const SectionHeader('标签'),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in store.tags)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: CircleAvatar(
                            radius: 5,
                            backgroundColor: tagColor(t),
                          ),
                          label: Text(t['name'] as String),
                          onPressed: () => openTag(context, store, t),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
          SectionHeader(
            listTitle,
            note: '${top.length}',
            trailing: top.length > 1 ? sortButton : null,
          ),
          if (top.isEmpty)
            query.trim().isNotEmpty
                ? EmptyState(
                    '没有找到匹配的规则',
                    '按名称和备注搜索，换个关键词试试。',
                    icon: Icons.search_off,
                  )
                : EmptyState(
                    root
                        ? (store.rules.isEmpty ? '还没有规则' : '未归类条目已全部整理')
                        : widget.project != null
                        ? '这个小项目还是空的'
                        : '这里还没有规则',
                    root && store.rules.isNotEmpty
                        ? '其余规则都在小项目中。'
                        : widget.project != null
                        ? '在这里新建规则，或在规则详情中“移动到小项目”。'
                        : '从空白或模板创建一条规则。',
                    icon: root && store.rules.isNotEmpty
                        ? Icons.check_circle_outline
                        : Icons.inbox_outlined,
                  ),
        ],
      );

      final list = ReorderableListView.builder(
        padding: pagePadding(context, fab: mode == _Mode.browse),
        header: Readable(maxWidth: 1000, child: header),
        itemCount: top.length,
        buildDefaultDragHandles: false,
        onReorderItem: reorder,
        itemBuilder: (context, index) => Readable(
          key: ValueKey(top[index]['id']),
          maxWidth: 1000,
          child: entry(top[index], index),
        ),
      );
      final bar = switch (mode) {
        _Mode.browse => null,
        _Mode.select => ModeBar(
          key: const ValueKey('select-bar'),
          title: selected.isEmpty ? '选择要合并的规则' : '已选 ${selected.length} 条',
          subtitle: '至少选两条独立规则',
          onClose: () => setMode(_Mode.browse),
          action: FilledButton.icon(
            onPressed: selected.length < 2
                ? null
                : () => perform(context, () async {
                    final merged = await mergeDialog(
                      context,
                      store,
                      selected.toList(),
                    );
                    if (merged && mounted) setMode(_Mode.browse);
                  }),
            icon: const Icon(Icons.call_merge, size: 18),
            label: Text('合并 ${selected.length}'),
          ),
        ),
        _Mode.reorder => ModeBar(
          key: const ValueKey('reorder-bar'),
          title: '调整顺序',
          subtitle: '拖动手柄或用箭头移动；切换自动排序时保留',
          action: FilledButton(
            onPressed: () => setMode(_Mode.browse),
            child: const Text('完成'),
          ),
        ),
      };
      final body = PopScope(
        canPop: mode == _Mode.browse,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setMode(_Mode.browse);
        },
        child: Column(
          children: [
            ?bar,
            Expanded(child: list),
          ],
        ),
      );
      if (widget.embedded) return body;
      return Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: [moreMenu]),
        body: body,
        floatingActionButton: mode != _Mode.browse
            ? null
            : FloatingActionButton.extended(
                onPressed: () =>
                    openCreator(context, store, project: widget.project),
                icon: const Icon(Icons.add),
                label: const Text('新建规则'),
              ),
      );
    },
  );
}

/// Contextual bar for a temporary mode; replaces scattered toggles.
class ModeBar extends StatelessWidget {
  final String title, subtitle;
  final VoidCallback? onClose;
  final Widget action;
  const ModeBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    this.onClose,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: SpanColors.of(context).soft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(onClose == null ? 16 : 4, 8, 12, 8),
        child: Row(
          children: [
            if (onClose != null)
              IconButton(
                tooltip: '退出',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            action,
          ],
        ),
      ),
    );
  }
}

class SortButton extends StatelessWidget {
  final SpanStore store;
  const SortButton({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final sort = store.setting('sort', 'manual');
    final descending = store.setting('descending', 'false') == 'true';
    void set(String key, String value) => perform(
      context,
      () => store.mutate('setting', {'key': key, 'value': value}),
    );
    return PopupMenuButton<String>(
      key: const ValueKey('sort-menu'),
      tooltip: '排序方式',
      onSelected: (v) => v == 'direction'
          ? set('descending', descending ? 'false' : 'true')
          : set('sort', v),
      itemBuilder: (_) => [
        for (final key in ['manual', 'reminder', 'event', 'remaining'])
          CheckedPopupMenuItem(
            value: key,
            checked: sort == key,
            child: Text(sortLabel(key, long: true)),
          ),
        if (sort != 'manual') ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'direction',
            child: ListTile(
              leading: Icon(descending ? Icons.north : Icons.south),
              title: Text(descending ? '改为由近到远' : '改为由远到近'),
            ),
          ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sort == 'manual'
                  ? Icons.sort
                  : descending
                  ? Icons.south
                  : Icons.north,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              sortLabel(sort),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String sortLabel(String value, {bool long = false}) => switch (value) {
  'manual' => long ? '手动排序' : '手动',
  'reminder' => long ? '下一次提醒时间' : '下一提醒',
  'event' => long ? '下一次事件时间' : '下一事件',
  'remaining' => '剩余有效期',
  _ => value,
};

/// Folders are the primary organizer, so they get a distinct, scannable grid.
class FolderGrid extends StatelessWidget {
  final SpanStore store;
  const FolderGrid({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final counts = <String?, int>{};
    for (final r in store.rules) {
      counts[r['project'] as String?] =
          (counts[r['project'] as String?] ?? 0) + 1;
    }
    final tiles = <Widget>[
      FolderTile(
        key: const ValueKey('folder-overview'),
        icon: Icons.view_agenda_outlined,
        name: '全部规则',
        detail: '${store.rules.length} 条 · 含合并成员',
        onTap: () => openOverview(context, store),
      ),
      for (final p in store.projects)
        FolderTile(
          icon: Icons.folder_rounded,
          name: p['name'] as String,
          detail: '${counts[p['id']] ?? 0} 条规则',
          onTap: () => openProject(context, store, p),
          onLongPress: () => renameProject(context, store, p['id'] as String),
        ),
      FolderTile(
        key: const ValueKey('folder-create'),
        icon: Icons.create_new_folder_outlined,
        name: '新建小项目',
        detail: '像文件夹一样归类',
        outlined: true,
        onTap: () => createProject(context, store),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 480
            ? 3
            : 2;
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class FolderTile extends StatelessWidget {
  final IconData icon;
  final String name, detail;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool outlined;
  const FolderTile({
    super.key,
    required this.icon,
    required this.name,
    required this.detail,
    required this.onTap,
    this.onLongPress,
    this.outlined = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SpanColors.of(context);
    return MergeSemantics(
      child: Material(
        color: outlined ? Colors.transparent : colors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 26,
                  color: outlined ? colors.muted : theme.colorScheme.primary,
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> createProject(BuildContext context, SpanStore store) =>
    perform(context, () async {
      final name = await askText(context, '新建小项目', action: '创建');
      if (name != null) await store.mutate('save_project', {'name': name});
    }, success: '已创建小项目');

Future<void> renameProject(BuildContext context, SpanStore store, String id) =>
    perform(context, () async {
      final baseRevision = store.revision;
      final name = await askText(
        context,
        '重命名小项目',
        initial: store.state['projects'][id]['name'] as String,
        action: '保存',
      );
      if (name != null) {
        await store.mutate('save_project', {
          'id': id,
          'name': name,
        }, baseRevision: baseRevision);
      }
    });

/// Explicit merge: name, destination and one decision per conflicting unit.
/// Returns whether the merge was committed.
Future<bool> mergeDialog(
  BuildContext context,
  SpanStore store,
  List<String> ids,
) async {
  final baseRevision = store.revision;
  final plan = object(await store.read('merge_plan', {'rules': ids}));
  if (!context.mounted) return false;
  final initialName = ids
      .map((id) => store.state['rules'][id]['name'])
      .join(' + ');
  final originalProjects = ids
      .map((id) => store.state['rules'][id]['project'])
      .toSet();
  bool needsConfirmation(String? target) =>
      originalProjects.any((p) => p != target);
  final buckets = (plan['buckets'] as List).map(object).toList();
  final choices = <String, String>{
    for (final b in buckets)
      if (b['conflict'] != true)
        b['unit_key'] as String: (b['accounts'] as List)[0]['id'] as String,
  };
  String? project = store.state['rules'][ids.first]['project'] as String?;
  bool approved = false;
  String projectName(String? id) =>
      id == null ? '未归类' : store.state['projects'][id]['name'] as String;
  final result = await showDialog<Json>(
    context: context,
    builder: (context) => TextControllerScope(
      initial: initialName,
      builder: (context, name) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final missing = buckets.any(
            (b) => b['conflict'] == true && !choices.containsKey(b['unit_key']),
          );
          return AlertDialog(
            title: Text('合并 ${ids.length} 条规则'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Callout(
                      '各规则的周期、提醒、标签与历史保持独立；相同单位的资源共用一个账户，余额只采用一份，不相加。',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '合并条目名称'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: project ?? '',
                      decoration: const InputDecoration(labelText: '合并后归属'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('未归类')),
                        for (final p in store.projects)
                          DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(p['name'] as String),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        project = v == '' ? null : v;
                        approved = false;
                      }),
                    ),
                    for (final bucket in buckets) ...[
                      const SizedBox(height: 16),
                      Text(
                        bucket['conflict'] == true
                            ? '余额不同 · 请选择保留哪一份'
                            : (bucket['accounts'] as List).length > 1
                            ? '余额相同 · 只保留一份，不相加'
                            : '共享资源账户',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: bucket['conflict'] == true
                              ? warningColor(context)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final ac in bucket['accounts'] as List)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          selected: choices[bucket['unit_key']] == ac['id'],
                          leading: Icon(
                            choices[bucket['unit_key']] == ac['id']
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(ac['name'] as String),
                          trailing: Text(
                            '${ac['formatted']} ${ac['unit']['code']}',
                            style: const TextStyle(fontFeatures: tabular),
                          ),
                          onTap: () => setState(
                            () => choices[bucket['unit_key'] as String] =
                                ac['id'] as String,
                          ),
                        ),
                    ],
                    if (buckets.any((b) => (b['accounts'] as List).length > 1))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '未选中的账户归档为历史证据，不计入共享余额。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (needsConfirmation(project))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: approved,
                          title: Text('确认所有成员移动到「${projectName(project)}」'),
                          subtitle: const Text('成员目前位于不同位置'),
                          onChanged: (v) => setState(() => approved = v!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: (needsConfirmation(project) && !approved) || missing
                    ? null
                    : () => Navigator.pop(context, {
                        'rules': ids,
                        'name': name.text,
                        'project': project,
                        'choices': choices,
                        'confirm_project': approved,
                      }),
                child: const Text('确认合并'),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (result == null) return false;
  await store.mutate('merge', result, baseRevision: baseRevision);
  if (context.mounted) notify(context, '已合并为「${result['name']}」');
  return true;
}
