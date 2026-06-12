import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../widgets/common.dart';
import '../import/metadata_repository.dart';

final metadataRepositoryProvider =
    Provider<MetadataRepository>((_) => MetadataRepository());

/// Barcode scanner with torch, manual ISBN entry and lookup → Import.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key, this.manual = false});

  final bool manual;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  late bool _manual = widget.manual;
  bool _busy = false;
  bool _torch = false;
  String? _foundIsbn;
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
  );
  final _isbnController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _isbnController.dispose();
    super.dispose();
  }

  Future<void> _lookup(String isbn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _foundIsbn = isbn;
    });
    try {
      final meta =
          await ref.read(metadataRepositoryProvider).lookup(isbn);
      if (!mounted) return;
      context.pushReplacement('/import', extra: meta);
    } on MetadataLookupException catch (e) {
      if (!mounted) return;
      showToast(context, e.message);
      setState(() {
        _busy = false;
        _foundIsbn = null;
      });
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Lookup failed — check your connection.');
      setState(() {
        _busy = false;
        _foundIsbn = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF171A21),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.12)),
                    icon: const Icon(Icons.close_rounded, color: white),
                  ),
                  Expanded(
                    child: Text(
                      _manual ? 'Enter ISBN' : 'Scan a book',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium!
                          .copyWith(color: white),
                    ),
                  ),
                  IconButton(
                    onPressed: _manual
                        ? null
                        : () {
                            _controller.toggleTorch();
                            setState(() => _torch = !_torch);
                          },
                    style: IconButton.styleFrom(
                      backgroundColor: _torch
                          ? Colors.white.withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                    icon: Icon(
                        _torch
                            ? Icons.flashlight_on_rounded
                            : Icons.flashlight_off_rounded,
                        color: white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _manual ? _manualEntry(theme) : _camera(theme),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: TextButton(
                onPressed: () => setState(() => _manual = !_manual),
                child: Text(
                  _manual ? 'Back to camera' : 'Type ISBN manually',
                  style: const TextStyle(color: white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _camera(ThemeData theme) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              if (raw != null && !_busy) _lookup(raw);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Camera unavailable — type the ISBN instead.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
        // Scan frame with corner brackets.
        SizedBox(
          width: 250,
          height: 160,
          child: Stack(children: [
            for (final corner in const [
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ])
              Align(
                alignment: corner,
                child: _CornerBracket(
                  alignment: corner,
                  color: _foundIsbn != null
                      ? const Color(0xFF7EE08A)
                      : Colors.white,
                ),
              ),
            if (_busy)
              Center(
                child: _foundIsbn != null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                                color: Color(0xFF7EE08A),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                                size: 32, color: Color(0xFF103319)),
                          ),
                          const SizedBox(height: 10),
                          Text('ISBN $_foundIsbn',
                              style: theme.textTheme.labelLarge!
                                  .copyWith(color: Colors.white)),
                          Text('Looking up…',
                              style: theme.textTheme.bodySmall!
                                  .copyWith(color: Colors.white70)),
                        ],
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
          ]),
        ),
        Positioned(
          bottom: 60,
          child: Text(
            'Align the barcode inside the frame',
            style:
                theme.textTheme.bodyMedium!.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _manualEntry(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Enter ISBN',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.headlineSmall!.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text('The 13-digit number above the barcode',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium!.copyWith(color: Colors.white60)),
          const SizedBox(height: 22),
          TextField(
            controller: _isbnController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              hintText: '978…',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed:
                _busy ? null : () => _lookup(_isbnController.text),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search_rounded),
            label: const Text('Look up'),
          ),
        ],
      ),
    );
  }
}

class _CornerBracket extends StatelessWidget {
  const _CornerBracket({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = alignment.y < 0;
    final left = alignment.x < 0;
    final side = BorderSide(color: color, width: 3.5);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        border: Border(
          top: top ? side : BorderSide.none,
          bottom: !top ? side : BorderSide.none,
          left: left ? side : BorderSide.none,
          right: !left ? side : BorderSide.none,
        ),
      ),
    );
  }
}
