import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/models/performance_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────
final aiResultProvider =
    StateProvider<LiveAnalysisResult?>((ref) => null);

final selectedStepProvider = StateProvider<String>(
  (ref) => AppConstants.garbaSteps.first,
);

class AiTrainerScreen extends ConsumerStatefulWidget {
  const AiTrainerScreen({super.key});

  @override
  ConsumerState<AiTrainerScreen> createState() => _AiTrainerScreenState();
}

class _AiTrainerScreenState extends ConsumerState<AiTrainerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isAnalysing = false;
  Timer? _feedbackTimer;
  List<double> _accuracyHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  /// Simulate live analysis (replace with real camera + API calls)
  void _startLiveAnalysis() {
    setState(() => _isAnalysing = true);
    _accuracyHistory = [];

    _feedbackTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.aiFrameCaptureInterval),
      (_) async {
        try {
          // TODO: Capture camera frame and send to backend
          // final frame = await _cameraController.takePicture();
          // final result = await ref.read(apiServiceProvider)
          //     .sendFrameForAnalysis(frame.bytes, selectedStep);

          // Simulated response for demo
          final mockAccuracy = 70.0 + (DateTime.now().millisecond % 30);
          final result = LiveAnalysisResult(
            accuracy: mockAccuracy,
            score: mockAccuracy - 5,
            mistakes: mockAccuracy < 85
                ? ['Keep your left arm higher', 'Bend knees slightly']
                : [],
            suggestions: ['Great rhythm! Keep it up'],
            grade: mockAccuracy >= 90 ? 'A' : mockAccuracy >= 75 ? 'B' : 'C',
          );

          if (mounted) {
            ref.read(aiResultProvider.notifier).state = result;
            setState(() {
              _accuracyHistory.add(result.accuracy);
              if (_accuracyHistory.length > 20) {
                _accuracyHistory.removeAt(0);
              }
            });
          }
        } catch (e) {
          debugPrint('AI analysis error: $e');
        }
      },
    );
  }

  void _stopAnalysis() {
    _feedbackTimer?.cancel();
    setState(() => _isAnalysing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Garba Trainer'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Live', icon: Icon(Icons.videocam_outlined, size: 18)),
            Tab(text: 'Steps', icon: Icon(Icons.format_list_bulleted, size: 18)),
            Tab(text: 'Progress', icon: Icon(Icons.insights, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LiveAnalysisTab(
            isAnalysing: _isAnalysing,
            accuracyHistory: _accuracyHistory,
            onStart: _startLiveAnalysis,
            onStop: _stopAnalysis,
          ),
          const _GarbaStepsTab(),
          const _ProgressTab(),
        ],
      ),
    );
  }
}

// ─── Live Analysis Tab ─────────────────────────────────────────────────────────
class _LiveAnalysisTab extends ConsumerWidget {
  final bool isAnalysing;
  final List<double> accuracyHistory;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _LiveAnalysisTab({
    required this.isAnalysing,
    required this.accuracyHistory,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(aiResultProvider);
    final selectedStep = ref.watch(selectedStepProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Camera placeholder / live view
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isAnalysing
                    ? AppColors.success
                    : Colors.grey.shade800,
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isAnalysing) ...[
                  // Skeleton overlay placeholder
                  const Icon(Icons.accessibility_new_rounded,
                      size: 120, color: Colors.white24),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: Colors.white),
                          SizedBox(width: 4),
                          Text('LIVE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  if (result != null)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${result.accuracy.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ),
                ] else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined,
                          size: 56, color: Colors.white38),
                      const SizedBox(height: 12),
                      const Text('Camera not active',
                          style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 4),
                      Text(
                        'Press Start to begin AI analysis',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ).animate().fade(),
          const SizedBox(height: 16),
          // Step selector
          DropdownButtonFormField<String>(
            initialValue: selectedStep,
            decoration: const InputDecoration(
                labelText: 'Select Garba Step'),
            items: AppConstants.garbaSteps
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) =>
                ref.read(selectedStepProvider.notifier).state = v!,
          ),
          const SizedBox(height: 16),
          // Start / Stop button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: isAnalysing ? onStop : onStart,
              icon: Icon(
                  isAnalysing ? Icons.stop_circle : Icons.play_circle_fill),
              label: Text(isAnalysing ? 'Stop Analysis' : 'Start Live Analysis'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isAnalysing ? AppColors.error : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (result != null) ...[
            // Accuracy indicator
            CircularPercentIndicator(
              radius: 70,
              lineWidth: 10,
              percent: result.accuracy / 100,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${result.accuracy.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const Text('Accuracy',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              progressColor: result.accuracy >= 90
                  ? AppColors.success
                  : result.accuracy >= 70
                      ? AppColors.warning
                      : AppColors.error,
              backgroundColor: Colors.grey.shade200,
              circularStrokeCap: CircularStrokeCap.round,
              animation: true,
            ).animate().scale(),
            const SizedBox(height: 16),
            // Grade & Score
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MetricCard(label: 'Score', value: result.score.toStringAsFixed(0)),
                _MetricCard(label: 'Grade', value: result.grade ?? '-'),
                _MetricCard(label: 'Step', value: selectedStep.split(' ').first),
              ],
            ),
            const SizedBox(height: 20),
            // Accuracy chart
            if (accuracyHistory.length > 2) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Accuracy Over Time',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: accuracyHistory
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: AppColors.primary,
                        barWidth: 3,
                        belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withValues(alpha: 0.15)),
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Mistakes
            if (result.mistakes.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: AppColors.error, size: 18),
                        SizedBox(width: 6),
                        Text('Corrections Needed',
                            style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...result.mistakes.map(
                      (m) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_right,
                                color: AppColors.error, size: 16),
                            Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Suggestions
            if (result.suggestions.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tips_and_updates,
                            color: AppColors.success, size: 18),
                        SizedBox(width: 6),
                        Text('Tips',
                            style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...result.suggestions.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: AppColors.success, size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Garba Steps Tab ──────────────────────────────────────────────────────────
class _GarbaStepsTab extends StatelessWidget {
  const _GarbaStepsTab();

  static const _stepDescriptions = {
    'Basic Step': 'The foundational Garba step — a simple left-right-center movement with light hand gestures.',
    'Two Clap': 'A two-count clap pattern synchronized with footwork. Clap on beats 1 and 3.',
    'Three Clap': 'Three claps in a circular motion. Arms swing out-in-out with each clap.',
    'Dodhiya': 'A popular Gujarati folk step with rhythmic sideways movement and graceful arm arcs.',
    'Hinch': 'Involves a hip-sway with alternating shoulder movements creating a wave-like effect.',
    'Simple Spin': 'A full clockwise spin on the count of 8, maintaining posture and balance.',
  };

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: AppConstants.garbaSteps.length,
      itemBuilder: (_, i) {
        final step = AppConstants.garbaSteps[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text(step,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_stepDescriptions[step] ?? '',
                        style: const TextStyle(
                            color: Colors.grey, height: 1.6)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Practice This Step'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 42)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate(delay: (i * 50).ms).fade().slideY(begin: 0.15);
      },
    );
  }
}

// ─── Progress Tab ─────────────────────────────────────────────────────────────
class _ProgressTab extends ConsumerWidget {
  const _ProgressTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mock progress data — replace with real API call
    final mockData = [
      {'step': 'Basic Step', 'accuracy': 94.0, 'grade': 'A'},
      {'step': 'Two Clap', 'accuracy': 88.0, 'grade': 'B+'},
      {'step': 'Three Clap', 'accuracy': 76.0, 'grade': 'B'},
      {'step': 'Dodhiya', 'accuracy': 65.0, 'grade': 'C'},
      {'step': 'Hinch', 'accuracy': 55.0, 'grade': 'D'},
      {'step': 'Simple Spin', 'accuracy': 82.0, 'grade': 'B'},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall score
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.festiveGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Text('Overall Performance',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                SizedBox(height: 8),
                Text('78%',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold)),
                Text('Grade: B+',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
                SizedBox(height: 4),
                Text('Keep practicing to reach Grade A!',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ).animate().fade().scale(begin: const Offset(0.95, 0.95)),
          const SizedBox(height: 24),
          const Text('Performance by Step',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...mockData.asMap().entries.map((entry) {
            final item = entry.value;
            final acc = item['accuracy'] as double;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item['step'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Row(
                        children: [
                          Text('${acc.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          _GradeBadge(grade: item['grade'] as String),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: acc / 100,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      acc >= 90
                          ? AppColors.success
                          : acc >= 75
                              ? AppColors.warning
                              : AppColors.error,
                    ),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ).animate(delay: (entry.key * 80).ms).slideX(begin: -0.1).fade(),
            );
          }),
          const SizedBox(height: 24),
          // Practice streak
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: AppColors.secondary, size: 36),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Practice Streak',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('5 days in a row! Keep it up!',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
                Spacer(),
                Text('🔥 5',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeBadge extends StatelessWidget {
  final String grade;
  const _GradeBadge({required this.grade});

  @override
  Widget build(BuildContext context) {
    final color = grade.startsWith('A')
        ? AppColors.success
        : grade.startsWith('B')
            ? AppColors.info
            : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(grade,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }
}