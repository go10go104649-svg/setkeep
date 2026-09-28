import 'package:flutter/material.dart';

import 'design/app_colors.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

import 'trainer_invite_qr.dart';

typedef TrainerScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onDetected,
);

class TrainerQrPage extends StatefulWidget {
  const TrainerQrPage({super.key, this.scannerBuilder, this.onInvite});

  // Allows result handling to be tested without a physical camera.
  final TrainerScannerBuilder? scannerBuilder;
  final ValueChanged<TrainerInviteQr>? onInvite;

  @override
  State<TrainerQrPage> createState() => _TrainerQrPageState();
}

class _TrainerQrPageState extends State<TrainerQrPage> {
  TrainerInviteQr? _invite;
  bool _invalid = false;

  void _detect(String raw) {
    if (!mounted || _invite != null) return;
    final invite = TrainerInviteQr.parse(raw);
    if (invite != null) {
      // Removing MobileScanner stops and disposes its internally owned camera.
      setState(() {
        _invite = invite;
        _invalid = false;
      });
      widget.onInvite?.call(invite);
    } else if (!_invalid) {
      // A persistent message avoids repeated alerts for the same invalid QR.
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('trainerQrPage'),
      appBar: AppBar(title: const Text('SETKEEP TRAINERと連携')),
      body: SafeArea(
        child: _invite != null
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 64),
                    const SizedBox(height: 24),
                    const Text(
                      'SETKEEP TRAINERの招待QRを読み取りました',
                      key: Key('trainerInviteRecognized'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '招待情報を認識しました。\n'
                      '招待の有効性はまだ確認していません。\n'
                      '連携画面で招待内容を確認してください。',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('closeTrainerInvite'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('SETKEEP TRAINERのQRコードを読み取ってください'),
                  ),
                  Expanded(
                    child:
                        widget.scannerBuilder?.call(context, _detect) ??
                        MobileScanner(
                          // With no external controller, the scanner owns camera
                          // disposal and background/resume lifecycle handling.
                          onDetect: (capture) {
                            for (final barcode in capture.barcodes) {
                              if (barcode.format == BarcodeFormat.qrCode &&
                                  barcode.rawValue != null) {
                                _detect(barcode.rawValue!);
                                if (_invite != null) break;
                              }
                            }
                          },
                          placeholderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          errorBuilder: (_, _) =>
                              const TrainerCameraUnavailable(),
                          overlayBuilder: (context, constraints) =>
                              IgnorePointer(
                                child: Center(
                                  child: SizedBox.square(
                                    dimension:
                                        constraints.biggest.shortestSide * 0.7,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.primaryGreen,
                                          width: 3,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ),
                  ),
                  if (_invalid)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'SETKEEP TRAINERの招待QRコードではありません。別のQRコードを読み取ってください。',
                        key: Key('invalidTrainerQr'),
                        style: TextStyle(color: Color(0xFFB3261E)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class TrainerCameraUnavailable extends StatelessWidget {
  const TrainerCameraUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF4F5F0),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.no_photography_outlined, size: 48),
            SizedBox(height: 16),
            Text('カメラを利用できません'),
            SizedBox(height: 12),
            Text('端末設定でSETKEEPのカメラ権限を確認してください。上部の戻るボタンでマイページへ戻れます。'),
          ],
        ),
      ),
    );
  }
}
