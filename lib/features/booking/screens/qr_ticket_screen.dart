import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/booking_provider.dart';

class QrTicketScreen extends ConsumerWidget {
  final String bookingId;
  const QrTicketScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingAsync = ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Ticket'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saving ticket...')));
            },
          ),
        ],
      ),
      body: bookingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (booking) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Ticket card
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          gradient: AppColors.festiveGradient,
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.music_note_rounded,
                                color: Colors.white, size: 40),
                            const SizedBox(height: 8),
                            const Text('GARBA APP',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                    letterSpacing: 3)),
                            const SizedBox(height: 4),
                            Text(
                              booking.event?.title ?? 'Event Ticket',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      // Dashed divider
                      _DashedDivider(),
                      // QR Code
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            QrImageView(
                              data: booking.qrData,
                              version: QrVersions.auto,
                              size: 200,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppColors.primaryDark,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape:
                                    QrDataModuleShape.square,
                                color: AppColors.primaryDark,
                              ),
                            ).animate().scale(
                                delay: 200.ms,
                                duration: 600.ms,
                                curve: Curves.elasticOut),
                            const SizedBox(height: 16),
                            Text(
                              booking.ticketUuid
                                  .substring(0, 8)
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Info rows
                      Container(
                        color: const Color(0xFFFFF8F5),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _TicketInfoRow(
                              label: 'Name',
                              value: booking.userName ?? '—',
                            ),
                            _TicketInfoRow(
                              label: 'Email',
                              value: booking.userEmail ?? '—',
                            ),
                            if (booking.event != null) ...[
                              _TicketInfoRow(
                                label: 'Venue',
                                value: booking.event!.venue,
                              ),
                              _TicketInfoRow(
                                label: 'Date',
                                value:
                                    '${booking.event!.date.day}/${booking.event!.date.month}/${booking.event!.date.year}',
                              ),
                              _TicketInfoRow(
                                label: 'Time',
                                value: booking.event!.time,
                              ),
                            ],
                            _TicketInfoRow(
                              label: 'Status',
                              value: booking.status.toUpperCase(),
                              valueColor: booking.isConfirmed
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Production Security Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: AppColors.success),
                    SizedBox(width: 6),
                    Text(
                      'Cryptographically Signed Digital Pass',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Present this QR code at the venue gate for instant scanning',
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Security & Verification Information Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, size: 20, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Text(
                          'Entry Verification Protocol',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• A QR code alone is not proof of admission. The event scanner app validates the HMAC security token against our Firestore backend in real time.\n'
                      '• Once scanned, the pass status is atomically changed to ADMITTED to prevent replay or screenshot sharing.\n'
                      '• Please carry a matching government photo ID for name verification.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Colors.brown.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      color: Colors.white,
      child: Row(
        children: [
          Container(
              width: 24,
              decoration: const BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12)),
              )),
          Expanded(
            child: CustomPaint(
              painter: _DashPainter(),
            ),
          ),
          Container(
              width: 24,
              decoration: const BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12)),
              )),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, size.height / 2), Offset(x + 8, size.height / 2), paint);
      x += 14;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _TicketInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _TicketInfoRow(
      {required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: valueColor),
          ),
        ],
      ),
    );
  }
}