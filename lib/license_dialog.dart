import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'l10n.dart';
import 'station_manager.dart';

// ── License list dialog ───────────────────────────────────────────

class LicenseListDialog extends StatefulWidget {
  final StationManager manager;

  const LicenseListDialog(this.manager, {super.key});

  @override
  State<LicenseListDialog> createState() => _LicenseListDialogState();
}

class _LicenseListDialogState extends State<LicenseListDialog> {
  late final Future<List<({String package, List<List<String>> licenses})>>
      _licensesFuture;

  @override
  void initState() {
    super.initState();
    _licensesFuture = _loadLicenses();
  }

  static Future<List<({String package, List<List<String>> licenses})>>
      _loadLicenses() async {
    final map = <String, List<List<String>>>{};

    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        map.putIfAbsent(package, () => []);
        final paragraphs = entry.paragraphs
            .map((p) => p.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (paragraphs.isNotEmpty) map[package]!.add(paragraphs);
      }
    }

    final appLicenses = map.remove(Common.appName) ?? [];
    final licenses =
        (map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((entry) => (
                  package: entry.key,
                  licenses: entry.value,
                ))
            .toList()
          ..add((
            package: Common.appName,
            licenses: appLicenses,
          ));

    return licenses;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── タイトル行（固定）──────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const Icon(
                    Icons.description,
                    color: Color(0xFF4080FF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.licensesDialogTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // ── スクロール領域 ──────────────────────────────────────
            Expanded(
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
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    children: [
                      // ── アプリ固有のヘッダー ──────────────────────
                      GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          barrierColor: Colors.transparent,
                          builder: (_) => LicenseDetailDialog(
                            l10n.appTitle,
                            appLicenses.licenses,
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
                              Text(
                                'Powered by Flutter',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.licensePublish,
                                style: TextStyle(
                                  fontSize: 12,
                                ),
                              ),
                              if (widget.manager.count > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.licenseStationsDetails(
                                    widget.manager.count,
                                    widget.manager.date,
                                    widget.manager.size,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                widget.manager.count > 0
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
                      const Divider(height: 8),
                      // ── 通常のライセンス条目 ──────────────────────
                      ...licenses.map(
                        (entry) => GestureDetector(
                          onTap: () => showDialog<void>(
                            context: context,
                            barrierColor: Colors.transparent,
                            builder: (_) => LicenseDetailDialog(
                              entry.package,
                              entry.licenses,
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
          ],
        ),
      ),
    );
  }
}

// ── License detail dialog ─────────────────────────────────────────

class LicenseDetailDialog extends StatelessWidget {
  final String package;
  final List<List<String>> licenses;

  const LicenseDetailDialog(this.package, this.licenses, {super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── タイトル行 ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Text(
                    package,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // ── テキスト ───────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: licenses
                    // 1. 【外层空防御】过滤掉完全没有内容的空许可证大块
                    .where((paragraphs) => paragraphs.isNotEmpty)
                    .map((paragraphs) => paragraphs
                        // 2. 【内层空防御】过滤掉许可证内部可能存在的空字符串/空段落
                        .where((paragraph) => paragraph.isNotEmpty)
                        // 3. 【内层拼装与截断】添加内层分隔符，并切掉最后一个
                        .expand((paragraph) => [
                              Text(
                                paragraph,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 12),
                            ])
                        .toList()
                      ..removeLast())
                    // 4. 【外层拼装与截断】添加外层分隔符，并切掉最后一个
                    .expand((texts) => [...texts, const Divider(height: 24)])
                    .toList()
                  ..removeLast(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
