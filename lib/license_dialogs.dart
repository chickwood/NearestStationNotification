import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';

// ── License list dialog ───────────────────────────────────────────

class LicenseListDialog extends StatefulWidget {
  const LicenseListDialog({super.key});

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

    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return sorted
        .map((e) => (package: e.key, licenses: e.value))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
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
            const SizedBox(height: 4),
            // ── リスト ─────────────────────────────────────────────
            Expanded(
              child: FutureBuilder(
                future: _licensesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final licenses = snapshot.data ?? [];

                  return ListView.builder(
                    itemCount: licenses.length,
                    itemBuilder: (context, index) {
                      final entry = licenses[index];
                      final count = entry.licenses.length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: GestureDetector(
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) => LicenseDetailDialog(
                              package: entry.package,
                              licenses: entry.licenses,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.package),
                              Text(
                                l10n.licenseCount(count),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

  const LicenseDetailDialog({
    super.key,
    required this.package,
    required this.licenses,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 2,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
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
            const SizedBox(height: 4),
            // ── テキスト ───────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
