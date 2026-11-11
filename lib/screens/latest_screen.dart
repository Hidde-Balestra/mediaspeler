import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/episode_tile.dart';

/// Alle afleveringen en video's van al je feeds door elkaar, nieuwste eerst.
class LatestScreen extends StatefulWidget {
  const LatestScreen({super.key});

  @override
  State<LatestScreen> createState() => _LatestScreenState();
}

enum _Filter { all, audio, video }

class _LatestScreenState extends State<LatestScreen> {
  _Filter _filter = _Filter.all;
  bool _hideFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppScope.read(context);
      final stale = state.feeds.any((f) =>
          state.episodesFor(f.url) == null ||
          f.lastFetched == null ||
          DateTime.now().difference(f.lastFetched!) > const Duration(minutes: 30));
      if (stale) _refresh(quiet: true);
    });
  }

  Future<void> _refresh({bool quiet = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = await AppScope.read(context).refreshAll();
    if (failed > 0 && !quiet) {
      messenger.showSnackBar(SnackBar(
          content: Text(failed == 1
              ? '1 feed kon niet worden vernieuwd.'
              : '$failed feeds konden niet worden vernieuwd.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.allEpisodes(
      kind: switch (_filter) {
        _Filter.all => null,
        _Filter.audio => MediaKind.audio,
        _Filter.video => MediaKind.video,
      },
      hideFinished: _hideFinished,
    );

    final Widget body;
    if (state.feeds.isEmpty) {
      body = const _Hint(
        icon: Icons.new_releases_outlined,
        title: 'Nog niets te zien',
        text: 'Voeg bij "Feeds" een podcast of YouTube-kanaal toe. '
            'Hier zie je daarna alle nieuwe afleveringen bij elkaar.',
      );
    } else if (items.isEmpty && state.refreshingAll) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final rows = _withDayHeaders(items);
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _filters(context);
            final row = rows[i - 1];
            return switch (row) {
              _Header(:final label) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary)),
                ),
              _Item(:final episode, :final feed) =>
                EpisodeTile(episode: episode, feed: feed, showFeed: true),
              _Empty() => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Niets gevonden met deze filters.', textAlign: TextAlign.center),
                ),
            };
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nieuw'),
        bottom: state.refreshingAll
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
        actions: [
          IconButton(
            tooltip: 'Alles vernieuwen',
            onPressed: state.refreshingAll || state.feeds.isEmpty ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const ThemeMenuButton(),
        ],
      ),
      body: body,
    );
  }

  Widget _filters(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (f, label, icon) in const [
              (_Filter.all, 'Alles', Icons.all_inclusive),
              (_Filter.audio, 'Podcasts', Icons.headphones),
              (_Filter.video, "Video's", Icons.smart_display),
            ])
              ChoiceChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            FilterChip(
              label: const Text('Verberg beluisterd'),
              selected: _hideFinished,
              onSelected: (v) => setState(() => _hideFinished = v),
            ),
          ],
        ),
      );

  /// Voegt kopjes "Vandaag", "Gisteren", "Deze week" en per datum toe.
  static List<_Row> _withDayHeaders(List<(Episode, Feed)> items) {
    if (items.isEmpty) return const [_Empty()];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String label(DateTime? d) {
      if (d == null) return 'Zonder datum';
      final local = d.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final diff = today.difference(day).inDays;
      if (diff <= 0) return 'Vandaag';
      if (diff == 1) return 'Gisteren';
      if (diff < 7) return 'Deze week';
      if (diff < 31) return 'Deze maand';
      return '${_months[local.month - 1]} ${local.year}';
    }

    final rows = <_Row>[];
    String? last;
    for (final (e, f) in items) {
      final l = label(e.published);
      if (l != last) {
        rows.add(_Header(l));
        last = l;
      }
      rows.add(_Item(e, f));
    }
    return rows;
  }

  static const _months = [
    'Januari', 'Februari', 'Maart', 'April', 'Mei', 'Juni',
    'Juli', 'Augustus', 'September', 'Oktober', 'November', 'December',
  ];
}

sealed class _Row {
  const _Row();
}

class _Header extends _Row {
  final String label;
  const _Header(this.label);
}

class _Item extends _Row {
  final Episode episode;
  final Feed feed;
  const _Item(this.episode, this.feed);
}

class _Empty extends _Row {
  const _Empty();
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _Hint({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
