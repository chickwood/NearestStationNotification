import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../common.dart';
import '../l10n.dart';
import '../manager/event_manager.dart';
import '../manager/station_manager.dart';

// ── License list page ─────────────────────────────────────────────

class LicenseListPage extends StatefulWidget {
  final StationManager stationManager;
  final EventManager eventManager;

  const LicenseListPage(this.stationManager, this.eventManager, {super.key});

  @override
  State<LicenseListPage> createState() => _LicenseListPageState();
}

class _LicenseListPageState extends State<LicenseListPage> {
  late StationManager _stationManager;
  late final Future<List<({String package, List<List<String>> licenses})>>
  _licensesFuture;

  @override
  void initState() {
    super.initState();
    _stationManager = widget.stationManager;
    _licensesFuture = _loadLicenses();
  }

  static Future<List<({String package, List<List<String>> licenses})>>
  _loadLicenses() async {
    final map = <String, List<List<String>>>{};

    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        map.putIfAbsent(package, () => []);
        final paragraphs =
            entry.paragraphs
                .map((p) => p.text.trim())
                .where((t) => t.isNotEmpty)
                .toList();
        if (paragraphs.isNotEmpty) map[package]!.add(paragraphs);
      }
    }

    final appLicenses = map.remove(Common.appName) ?? [];
    final licenses =
        (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((entry) => (package: entry.key, licenses: entry.value))
            .toList()
          ..add((package: Common.appName, licenses: appLicenses));

    return licenses;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: Text(l10n.licensesPageTitle)),
      body: SafeArea(
        child: FutureBuilder(
          future: _licensesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final licenses = (snapshot.data ?? []).toList();
            // ADDITIONAL_NOTICE 单独处理
            final appLicenses = licenses.removeLast();
            final appLicensesLength = appLicenses.licenses.length - 1;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // ── アプリ固有のヘッダー ──────────────────────
                GestureDetector(
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => LicenseDetailPage(
                                l10n.appTitle,
                                appLicenses.licenses,
                              ),
                        ),
                      ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.appTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Text(
                          'Powered by Flutter',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.licensePublish,
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (_stationManager.count > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${l10n.licenseStationDetailsTitle}'
                            '\n${l10n.infoStations(_stationManager.count)}'
                            '\n${l10n.infoVersion(_stationManager.date, _stationManager.pdate)}'
                            '\n${l10n.infoSize(_stationManager.size)}'
                            '\n${l10n.licenseStationDetailsEkidata}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          _stationManager.count > 0
                              ? l10n.licenseCountWithAdditionalNotice(
                                appLicensesLength,
                              )
                              : l10n.licenseCount(appLicensesLength),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 16),
                // ── 通常のライセンス条目 ──────────────────────
                ...licenses.map(
                  (entry) => GestureDetector(
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => LicenseDetailPage(
                                  entry.package,
                                  entry.licenses,
                                ),
                          ),
                        ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.package),
                            Text(
                              l10n.licenseCount(entry.licenses.length),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── License detail page ───────────────────────────────────────────

class LicenseDetailPage extends StatelessWidget {
  final String package;
  final List<List<String>> licenses;

  const LicenseDetailPage(this.package, this.licenses, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: Text(package)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children:
              licenses
                  // 1. 【外层空防御】过滤掉完全没有内容的空许可证大块
                  .where((paragraphs) => paragraphs.isNotEmpty)
                  .map(
                    (paragraphs) =>
                        paragraphs
                            // 2. 【内层空防御】过滤掉许可证内部可能存在的空字符串/空段落
                            .where((paragraph) => paragraph.isNotEmpty)
                            // 3. 【内层拼装与截断】添加内层分隔符，并切掉最后一个
                            .expand(
                              (paragraph) => [
                                Text(
                                  paragraph,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            )
                            .toList()
                          ..removeLast(),
                  )
                  // 4. 【外层拼装与截断】添加外层分隔符，并切掉最后一个
                  .expand((texts) => [...texts, const Divider(height: 16)])
                  .toList()
                ..removeLast(),
        ),
      ),
    );
  }
}
