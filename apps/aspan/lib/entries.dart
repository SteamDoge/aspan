// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 ASpan contributors.

import 'package:flutter/material.dart';

import 'data.dart';
import 'design.dart';
import 'details.dart';
import 'editor.dart';
import 'profile.dart';
import 'widgets.dart';

/// A place that lists rules: the smart home list, everything, the unfiled
/// rules, one folder (small project) or one tag.
@immutable
class Folder {
  final String kind;
  final String? id;
  const Folder(this.kind, [this.id]);
  static const home = Folder('home'),
      all = Folder('all'),
      inbox = Folder('inbox');
  const Folder.project(String this.id) : kind = 'project';
  const Folder.tag(String this.id) : kind = 'tag';

  String get key => id == null ? kind : '$kind-$id';
  String title(SpanStore store) => switch (kind) {
    'home' => tr('主页'),
    'all' => tr('全部规则'),
    'inbox' => tr('未归类'),
    'project' => store.state['projects'][id]?['name'] as String? ?? tr('文件夹'),
    _ => '#${store.state['tags'][id]?['name'] ?? ''}',
  };
  @override
  bool operator ==(Object other) =>
      other is Folder && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

/// Opens a folder as its own page (used outside the main shell).
void openFolder(BuildContext context, SpanStore store, Folder folder) =>
    push(context, FolderView(store: store, folder: folder, standalone: true));

/// The home layout setting: `due` (every rule by due date), `project` or
/// `tag` (grouped), or `project:<id>` / `tag:<id>` (one place only). Rust
/// validates the value; a place missing from this snapshot shows everything.
String homeLayout(SpanStore store) {
  final value = store.setting('home', 'due');
  final parts = value.split(':');
  if (parts.length != 2) return value;
  final places = store.state[parts[0] == 'project' ? 'projects' : 'tags'];
  return places[parts[1]] == null ? 'due' : value;
}

/// Nearest next event first; rules without a date last; then by name.
int byDue(SpanStore store, Json a, Json b) {
  final pa = store.view(a['id'] as String)['planned'] as String?;
  final pb = store.view(b['id'] as String)['planned'] as String?;
  if (pa != pb) {
    if (pa == null) return 1;
    if (pb == null) return -1;
    return pa.compareTo(pb);
  }
  return (a['name'] as String).compareTo(b['name'] as String);
}

/// Home rows offer quick completion while a period needs action or is close.
const quickPhases = [...actionPhases, 'reminder'];

void openTag(BuildContext context, SpanStore store, Json tag) =>
    openFolder(context, store, Folder.tag(tag['id'] as String));

Color tagColor(Json tag) =>
    Color(int.tryParse('FF${tag['color']}', radix: 16) ?? 0xFF2164C7);

enum Mode { browse, select, reorder }

/// One list page for every folder: a large title, search and grouped rows.
/// Pushed folders carry a toolbar with the count and the compose button; the
/// home tab sits above the dock and keeps compose in its navigation bar.
class FolderView extends StatefulWidget {
  final SpanStore store;
  final Folder folder;

  /// Pushed as its own route, so it guards back presses itself.
  final bool standalone;
  const FolderView({
    super.key,
    required this.store,
    required this.folder,
    this.standalone = false,
  });
  @override
  State<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends State<FolderView> {
  final search = TextEditingController();
  String query = '';
  Mode mode = Mode.browse;
  final Set<String> selected = {}, toggled = {};
  SpanStore get store => widget.store;
  Folder get folder => widget.folder;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void setMode(Mode next) {
    setState(() {
      mode = next;
      selected.clear();
    });
  }

  Future<void> startReorder() async {
    if (store.setting('sort', 'manual') != 'manual') {
      await perform(
        context,
        () => store.mutate('setting', {'key': 'sort', 'value': 'manual'}),
        success: tr('已切换为手动排序，原手动顺序保留'),
      );
    }
    if (mounted) setMode(Mode.reorder);
  }

  bool matches(Json r) => ('${r['name']} ${r['notes']}').toLowerCase().contains(
    query.trim().toLowerCase(),
  );

  bool inScope(Json r) => switch (folder.kind) {
    'inbox' => r['project'] == null,
    'project' => r['project'] == folder.id,
    'tag' => List<String>.from(r['tags']).contains(folder.id),
    _ => true,
  };

  void toggleSelect(String id) => setState(
    () => selected.contains(id) ? selected.remove(id) : selected.add(id),
  );

  void menuFor(Json rule, Offset position) => ruleMenu(
    context,
    store,
    rule,
    position,
    onSelect: folder.kind == 'home'
        ? null
        : () {
            setMode(Mode.select);
            toggleSelect(rule['id'] as String);
          },
  );

  RuleRow ruleRow(
    Json r, {
    bool first = false,
    bool last = false,
    double indent = 0,
    bool quick = false,
    Key? key,
  }) {
    final id = r['id'] as String;
    final selecting = mode == Mode.select;
    return RuleRow(
      key: key ?? ValueKey('rule-$id'),
      store: store,
      rule: r,
      first: first,
      last: last,
      indent: indent,
      selected: selecting && selected.contains(id),
      onTap: () => selecting ? toggleSelect(id) : openRule(context, store, id),
      onMenu: selecting ? null : (p) => menuFor(r, p),
      leading: selecting && r['group'] == null
          ? Padding(
              padding: const EdgeInsets.only(right: 8),
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
      trailing: !selecting && quick && store.view(id)['planned'] != null
          ? CompleteButton(
              onPressed: () => eventSheet(context, store, r, 'completed'),
            )
          : null,
    );
  }

  /// Home: low resources and pinned rules first, then every rule of the
  /// chosen place by its next due date, as one list or grouped by folder or
  /// tag (see [homeLayout]).
  List<Widget> homeSections() {
    final layout = homeLayout(store);
    final (kind, place) = switch (layout.split(':')) {
      [final k, final id] => (k, id),
      _ => (layout, null),
    };
    final rules = store.rules.where((r) {
      if (place == null) return true;
      return kind == 'project'
          ? r['project'] == place
          : List<String>.from(r['tags']).contains(place);
    }).toList()..sort((a, b) => byDue(store, a, b));
    final pinned = rules.where((r) => r['pinned'] == true).toList();
    final rest = rules.where((r) => r['pinned'] != true).toList();
    List<Widget> section(String title, List<Json> list) => [
      SectionHeader(title, note: '${list.length}'),
      ...groupedTiles(
        list,
        (r, f, l) => ruleRow(
          r,
          first: f,
          last: l,
          quick: quickPhases.contains(
            store.view(r['id'] as String)['phase'] as String,
          ),
          key: ValueKey('home-$title-${r['id']}'),
        ),
      ),
    ];
    final groups = <(String, List<Json>)>[
      if (place != null)
        (Folder(kind, place).title(store), rest)
      else if (kind == 'project') ...[
        for (final p in store.projects)
          (
            p['name'] as String,
            rest.where((r) => r['project'] == p['id']).toList(),
          ),
        (tr('未归类'), rest.where((r) => r['project'] == null).toList()),
      ] else if (kind == 'tag') ...[
        for (final t in [
          ...store.tags,
        ]..sort((a, b) => (a['name'] as String).compareTo(b['name'])))
          (
            '#${t['name']}',
            rest
                .where((r) => List<String>.from(r['tags']).contains(t['id']))
                .toList(),
          ),
        (tr('无标签'), rest.where((r) => List.from(r['tags']).isEmpty).toList()),
      ] else
        (tr('全部规则'), rest),
    ];
    final low = store.accounts
        .where(
          (a) =>
              a['archived'] != true &&
              store.accountView(a['id'] as String)['active'] == true &&
              store.accountView(a['id'] as String)['low'] == true,
        )
        .toList();
    return [
      if (low.isNotEmpty) ...[
        SectionHeader(tr('余量不足')),
        ...groupedTiles(
          low,
          (a, f, l) => GroupedTile(
            first: f,
            last: l,
            onTap: () => openAccount(context, store, a['id'] as String),
            child: ValueRow(
              a['name'] as String,
              value:
                  '${store.accountView(a['id'] as String)['formatted']} ${unitLabel(a['unit']['code'])}',
              valueColor: warningColor(context),
              chevron: true,
            ),
          ),
        ),
      ],
      if (pinned.isNotEmpty) ...section(tr('置顶'), pinned),
      for (final (title, list) in groups)
        if (list.isNotEmpty) ...section(title, list),
      if (place != null && rules.isEmpty && store.rules.isNotEmpty)
        EmptyState(
          tr('这里还没有规则'),
          message: tr('主页当前只显示「{place}」，可在右上角菜单改回全部规则。', {
            'place': Folder(kind, place).title(store),
          }),
          icon: Icons.filter_list,
        ),
    ];
  }

  /// Home layout menu: one list by due date, grouped, or one place only.
  Future<void> chooseHomeLayout(String value) async {
    var next = value;
    if (value == 'only-project' || value == 'only-tag') {
      final kind = value == 'only-project' ? 'project' : 'tag';
      final current = homeLayout(store);
      final places = kind == 'project'
          ? [
              for (final p in store.projects)
                (p['id'] as String, p['name'] as String),
            ]
          : [
              for (final t in [
                ...store.tags,
              ]..sort((a, b) => (a['name'] as String).compareTo(b['name'])))
                (t['id'] as String, '#${t['name']}'),
            ];
      final id = await showSpanSheet<String>(
        context,
        (context) => SheetBody(
          title: kind == 'project' ? tr('主页只显示文件夹') : tr('主页只显示标签'),
          content: [
            Panel(
              dividerIndent: 52,
              children: [
                for (final (id, name) in places)
                  ValueRow(
                    name,
                    key: ValueKey('home-place-$id'),
                    icon: kind == 'project'
                        ? Icons.folder_outlined
                        : Icons.sell_outlined,
                    chevron: false,
                    trailing: current == '$kind:$id'
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
      if (id == null) return;
      next = '$kind:$id';
    }
    if (!mounted || next == homeLayout(store)) return;
    await perform(
      context,
      () => store.mutate('setting', {'key': 'home', 'value': next}),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final colors = SpanColors.of(context);
      final home = folder.kind == 'home';
      final searching = query.trim().isNotEmpty;
      final manual = store.setting('sort', 'manual') == 'manual';
      final reordering = mode == Mode.reorder && manual;
      final scoped = store.rules.where(inScope).toList();
      final top = home
          ? <Json>[]
          : store.ordered([
              for (final r in scoped)
                if (r['group'] == null && matches(r)) r,
              for (final g in store.groups)
                if (scoped.any((r) => r['group'] == g['id'] && matches(r))) g,
            ]);
      final expandByDefault =
          folder.kind == 'all' || folder.kind == 'tag' || searching;
      final viewRevision = store.revision;

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

      // Flatten entries (and unfolded members) into one grouped card.
      final tiles = <Widget Function(bool first, bool last)>[];
      final results = home && searching
          ? (store.rules.where(matches).toList()
              ..sort((a, b) => a['name'].toString().compareTo(b['name'])))
          : <Json>[];
      for (final r in results) {
        tiles.add((f, l) => ruleRow(r, first: f, last: l));
      }
      for (final item in top) {
        final id = item['id'] as String;
        if (!item.containsKey('accounts')) {
          tiles.add((f, l) => ruleRow(item, first: f, last: l));
          continue;
        }
        final members = store.ordered(
          scoped.where((r) => r['group'] == id && matches(r)).toList(),
        );
        final expanded = expandByDefault ^ toggled.contains(id);
        tiles.add(
          (f, l) => GroupRow(
            key: ValueKey('group-$id'),
            store: store,
            group: item,
            members: members,
            first: f,
            last: l,
            expanded: expanded,
            dimmed: mode == Mode.select,
            onTap: () {
              if (mode == Mode.browse) openGroup(context, store, id);
            },
            onMenu: mode == Mode.browse
                ? (p) => groupMenu(context, store, item, p)
                : null,
            onToggle: mode == Mode.browse
                ? () => setState(
                    () => toggled.contains(id)
                        ? toggled.remove(id)
                        : toggled.add(id),
                  )
                : null,
          ),
        );
        if (expanded) {
          for (final m in members) {
            tiles.add((f, l) => ruleRow(m, first: false, last: l, indent: 38));
          }
        }
      }

      final count = home ? store.rules.length : top.length;
      final emptyHint = searching
          ? EmptyState(tr('没有找到'), icon: Icons.search_off)
          : switch (folder.kind) {
              'home' when store.rules.isEmpty => EmptyState(
                tr('还没有规则'),
                icon: Icons.event_note_outlined,
                action: FilledButton(
                  onPressed: () => openCreator(context, store),
                  child: Text(tr('新建规则')),
                ),
              ),
              'home' => const SizedBox.shrink(),
              'project' => EmptyState(
                tr('文件夹是空的'),
                icon: Icons.folder_open_outlined,
              ),
              'inbox' => EmptyState(tr('没有未归类的规则')),
              _ => EmptyState(tr('这里还没有规则'), icon: Icons.event_note_outlined),
            };

      final layout = homeLayout(store);
      String? only(String kind) => layout.startsWith('$kind:')
          ? Folder(kind, layout.substring(kind.length + 1)).title(store)
          : null;
      final menu = home
          ? PopupMenuButton<String>(
              key: const ValueKey('home-menu'),
              tooltip: tr('主页显示'),
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: chooseHomeLayout,
              itemBuilder: (_) => [
                for (final (value, label) in [
                  ('due', tr('全部规则，按到期时间')),
                  ('project', tr('按文件夹分组')),
                  ('tag', tr('按标签分组')),
                ])
                  CheckedPopupMenuItem(
                    value: value,
                    checked: layout == value,
                    child: Text(label),
                  ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'only-project',
                  checked: only('project') != null,
                  enabled: store.projects.isNotEmpty,
                  child: Text(
                    only('project') == null
                        ? tr('只看一个文件夹…')
                        : tr('只看：{place}', {'place': only('project')}),
                  ),
                ),
                CheckedPopupMenuItem(
                  value: 'only-tag',
                  checked: only('tag') != null,
                  enabled: store.tags.isNotEmpty,
                  child: Text(
                    only('tag') == null
                        ? tr('只看一个标签…')
                        : tr('只看：{place}', {'place': only('tag')}),
                  ),
                ),
              ],
            )
          : PopupMenuButton<String>(
              key: const ValueKey('entries-menu'),
              tooltip: tr('更多'),
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) async {
                final sort = store.setting('sort', 'manual');
                final descending = store.setting('descending', 'false');
                void set(String key, String value) => perform(
                  context,
                  () => store.mutate('setting', {'key': key, 'value': value}),
                );
                switch (value) {
                  case 'select':
                    setMode(Mode.select);
                  case 'reorder':
                    await startReorder();
                  case 'rename':
                    await renameProject(context, store, folder.id!);
                  case 'tag':
                    await tagSheet(
                      context,
                      store,
                      object(store.state['tags'][folder.id]),
                    );
                  case 'direction':
                    set('descending', descending == 'true' ? 'false' : 'true');
                  default:
                    if (value != sort) set('sort', value);
                }
              },
              itemBuilder: (_) {
                final sort = store.setting('sort', 'manual');
                final descending =
                    store.setting('descending', 'false') == 'true';
                return [
                  menuItem(
                    'select',
                    tr('选择'),
                    Icons.check_circle_outline,
                    enabled: top.any((e) => !e.containsKey('accounts')),
                  ),
                  menuItem(
                    'reorder',
                    tr('调整顺序'),
                    Icons.swap_vert,
                    enabled: top.length > 1,
                  ),
                  const PopupMenuDivider(),
                  for (final key in [
                    'manual',
                    'reminder',
                    'event',
                    'remaining',
                  ])
                    CheckedPopupMenuItem(
                      value: key,
                      checked: sort == key,
                      child: Text(sortLabel(key)),
                    ),
                  if (sort != 'manual')
                    menuItem(
                      'direction',
                      descending ? tr('改为由近到远') : tr('改为由远到近'),
                      descending ? Icons.north : Icons.south,
                    ),
                  if (folder.kind == 'project' || folder.kind == 'tag')
                    const PopupMenuDivider(),
                  if (folder.kind == 'project')
                    menuItem(
                      'rename',
                      tr('重命名文件夹'),
                      Icons.drive_file_rename_outline,
                    ),
                  if (folder.kind == 'tag')
                    menuItem('tag', tr('编辑标签'), Icons.sell_outlined),
                ];
              },
            );

      final attention = store.rules
          .where(
            (r) => actionPhases.contains(
              store.view(r['id'] as String)['phase'] as String,
            ),
          )
          .length;
      final subtitle = home
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: friendlyDate(store.snapshot['today'] as String?),
                  ),
                  if (store.rules.isNotEmpty) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: attention == 0
                          ? tr('暂无需要处理的事项')
                          : tr('{n} 项需要处理', {'n': attention}),
                      style: attention == 0
                          ? null
                          : TextStyle(
                              color: warningColor(context),
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ],
                ],
              ),
            )
          : null;

      void compose() => openCreator(
        context,
        store,
        project: folder.kind == 'project' ? folder.id : null,
      );
      final toolbar = switch (mode) {
        Mode.browse when !widget.standalone => null,
        Mode.browse => SpanToolbar(
          center: Text(
            home
                ? tr('{n} 条规则', {'n': store.rules.length})
                : tr('{n} 项', {'n': count}),
          ),
        ),
        Mode.select => SpanToolbar(
          key: const ValueKey('select-bar'),
          leading: TextButton(
            onPressed: () => setMode(Mode.browse),
            child: Text(tr('取消')),
          ),
          center: Text(
            selected.isEmpty
                ? tr('选择要合并的规则')
                : tr('已选 {n} 条', {'n': selected.length}),
          ),
          trailing: TextButton(
            key: const ValueKey('merge-selected'),
            onPressed: selected.length < 2
                ? null
                : () => perform(context, () async {
                    final merged = await mergeDialog(
                      context,
                      store,
                      selected.toList(),
                    );
                    if (merged && mounted) setMode(Mode.browse);
                  }),
            child: Text(
              selected.length < 2
                  ? tr('合并')
                  : tr('合并 {n}', {'n': selected.length}),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Mode.reorder => SpanToolbar(
          key: const ValueKey('reorder-bar'),
          trailing: TextButton(
            key: const ValueKey('reorder-done'),
            onPressed: () => setMode(Mode.browse),
            child: Text(
              tr('完成'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      };

      final Widget list;
      if (reordering) {
        list = SliverReorderableList(
          itemCount: top.length,
          onReorderItem: reorder,
          proxyDecorator: (child, _, _) => Material(
            elevation: 8,
            color: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: .3),
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          itemBuilder: (context, index) {
            final item = top[index];
            final handle = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: tr('上移'),
                  onPressed: index > 0 ? () => reorder(index, index - 1) : null,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: tr('下移'),
                  onPressed: index + 1 < top.length
                      ? () => reorder(index, index + 1)
                      : null,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: tr('拖动排序'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 14, 10),
                      child: Icon(Icons.drag_handle, color: colors.muted),
                    ),
                  ),
                ),
              ],
            );
            final first = index == 0, last = index == top.length - 1;
            return KeyedSubtree(
              key: ValueKey(item['id']),
              child: item.containsKey('accounts')
                  ? GroupRow(
                      store: store,
                      group: item,
                      members: scoped
                          .where((r) => r['group'] == item['id'])
                          .toList(),
                      first: first,
                      last: last,
                      expanded: false,
                      onTap: () {},
                      trailing: handle,
                    )
                  : RuleRow(
                      store: store,
                      rule: item,
                      first: first,
                      last: last,
                      onTap: () {},
                      trailing: handle,
                    ),
            );
          },
        );
      } else {
        list = SliverList.builder(
          itemCount: tiles.length,
          itemBuilder: (context, i) => tiles[i](i == 0, i == tiles.length - 1),
        );
      }

      final homeChildren = home && !searching ? homeSections() : <Widget>[];
      final empty = home
          ? (searching ? results.isEmpty : store.rules.isEmpty)
          : top.isEmpty;
      final page = SpanPage(
        title: folder.title(store),
        titleKey: ValueKey('page-${folder.kind}'),
        subtitle: subtitle,
        leading: mode != Mode.browse ? const SizedBox.shrink() : null,
        floatingActionButton: mode == Mode.browse
            ? AddButton(key: const ValueKey('create-rule'), onPressed: compose)
            : null,
        actions: [
          if (mode == Mode.select)
            TextButton(
              onPressed: () => setMode(Mode.browse),
              child: Text(
                tr('完成'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else if (mode == Mode.browse)
            menu,
        ],
        onRefresh: () => perform(context, store.refresh),
        toolbar: toolbar,
        slivers: [
          boxes([
            if (mode == Mode.browse)
              SearchField(
                key: const ValueKey('entry-search'),
                controller: search,
                hint: home ? tr('搜索全部规则') : tr('搜索'),
                onChanged: (v) => setState(() => query = v),
              ),
            if (!home && !reordering && top.isNotEmpty)
              const SizedBox(height: 12),
            if (home && searching && results.isNotEmpty)
              SectionHeader(tr('搜索结果'), note: '${results.length}'),
            if (reordering) const SizedBox(height: 12),
            ...homeChildren,
            if (empty) emptyHint,
          ]),
          list,
        ],
      );
      if (!widget.standalone) return page;
      return PopScope(
        canPop: mode == Mode.browse,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setMode(Mode.browse);
        },
        child: page,
      );
    },
  );
}

String sortLabel(String value) => switch (value) {
  'manual' => tr('手动排序'),
  'reminder' => tr('按下一次提醒'),
  'event' => tr('按下一次事件'),
  'remaining' => tr('按剩余有效期'),
  _ => value,
};

/// The 项目 tab: overview, unfiled rules, folders and tags. Each opens its
/// list as a page above the dock.
class ProjectsPage extends StatelessWidget {
  final SpanStore store;
  const ProjectsPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final theme = Theme.of(context);
      final counts = <String?, int>{};
      for (final r in store.rules) {
        counts[r['project'] as String?] =
            (counts[r['project'] as String?] ?? 0) + 1;
      }
      void open(Folder folder) => openFolder(context, store, folder);
      Widget row(
        Folder folder,
        IconData icon,
        String name,
        int count, {
        bool first = false,
        bool last = false,
        void Function(Offset)? onMenu,
      }) => GroupedTile(
        key: ValueKey('folder-${folder.key}'),
        first: first,
        last: last,
        indent: 52,
        onTap: () => open(folder),
        onMenu: onMenu,
        child: ValueRow(name, icon: icon, value: '$count', chevron: true),
      );
      return SpanPage(
        title: tr('项目'),
        titleKey: const ValueKey('page-projects'),
        floatingActionButton: AddButton(
          key: const ValueKey('create-rule'),
          onPressed: () => openCreator(context, store),
        ),
        onRefresh: () => perform(context, store.refresh),
        slivers: [
          boxes([
            const SizedBox(height: 8),
            row(
              Folder.all,
              Icons.format_list_bulleted,
              tr('全部规则'),
              store.rules.length,
              first: true,
            ),
            row(
              Folder.inbox,
              Icons.inbox_outlined,
              tr('未归类'),
              counts[null] ?? 0,
              last: true,
            ),
            SectionHeader(tr('文件夹'), large: false),
            for (final p in store.projects)
              row(
                Folder.project(p['id'] as String),
                Icons.folder_outlined,
                p['name'] as String,
                counts[p['id']] ?? 0,
                first: p == store.projects.first,
                onMenu: (position) async {
                  final action = await showContextMenu<String>(
                    context,
                    position,
                    title: p['name'] as String,
                    sections: [
                      [
                        MenuAction(
                          'rename',
                          tr('重命名'),
                          Icons.drive_file_rename_outline,
                        ),
                      ],
                    ],
                  );
                  if (action == 'rename' && context.mounted) {
                    await renameProject(context, store, p['id'] as String);
                  }
                },
              ),
            GroupedTile(
              key: const ValueKey('folder-create'),
              first: store.projects.isEmpty,
              last: true,
              indent: 52,
              onTap: () => createProject(context, store),
              child: ValueRow(
                tr('新建文件夹'),
                icon: Icons.create_new_folder_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            if (store.tags.isNotEmpty) ...[
              SectionHeader(tr('标签'), large: false),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in store.tags)
                      _TagPill(
                        key: ValueKey('tag-${t['id']}'),
                        tag: t,
                        onTap: () => openTag(context, store, t),
                        onLongPress: () => tagSheet(context, store, t),
                      ),
                  ],
                ),
              ),
            ],
          ]),
        ],
      );
    },
  );
}

class _TagPill extends StatelessWidget {
  final Json tag;
  final VoidCallback onTap, onLongPress;
  const _TagPill({
    super.key,
    required this.tag,
    required this.onTap,
    required this.onLongPress,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: SpanColors.of(context).panel,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tagColor(tag),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                tag['name'] as String,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks first: a cancelled dialog writes nothing and reports nothing.
Future<void> createProject(BuildContext context, SpanStore store) async {
  final name = await askText(context, tr('新建文件夹'), action: tr('创建'));
  if (name == null || !context.mounted) return;
  await perform(
    context,
    () => store.mutate('save_project', {'name': name}),
    success: tr('已创建文件夹'),
  );
}

Future<void> renameProject(BuildContext context, SpanStore store, String id) =>
    perform(context, () async {
      final baseRevision = store.revision;
      final name = await askText(
        context,
        tr('重命名文件夹'),
        initial: store.state['projects'][id]['name'] as String,
        action: tr('保存'),
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
      id == null ? tr('未归类') : store.state['projects'][id]['name'] as String;
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
            title: Text(
              tr('合并 {n} 条规则', {'n': ids.length}),
              textAlign: TextAlign.center,
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('单位相同的资源共用一个账户，余额只保留一份，不相加。'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: name,
                      decoration: InputDecoration(hintText: tr('合并后的名称')),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: project ?? '',
                      decoration: InputDecoration(labelText: tr('放在')),
                      items: [
                        DropdownMenuItem(value: '', child: Text(tr('未归类'))),
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
                            ? tr('余额不同，请选择保留哪一份')
                            : (bucket['accounts'] as List).length > 1
                            ? tr('余额相同，只保留一份')
                            : tr('共享资源账户'),
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
                            '${ac['formatted']} ${unitLabel(ac['unit']['code'])}',
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
                          tr('未选中的账户归档为历史证据，不计入共享余额。'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (needsConfirmation(project))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: approved,
                          title: Text(
                            tr('把所有成员移到「{place}」', {
                              'place': projectName(project),
                            }),
                          ),
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
                child: Text(tr('取消')),
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
                child: Text(tr('确认合并')),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (result == null) return false;
  await store.mutate('merge', result, baseRevision: baseRevision);
  if (context.mounted) {
    notify(context, tr('已合并为「{name}」', {'name': result['name']}));
  }
  return true;
}
