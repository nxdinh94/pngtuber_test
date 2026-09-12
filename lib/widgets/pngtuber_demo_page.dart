import 'package:flutter/material.dart';

import '../pngtuber/pngtuber_controller.dart';
import '../pngtuber/pngtuber_math.dart';
import 'pngtuber_stage.dart';

typedef PNGTuberControllerFactory = PNGTuberController Function();

class PNGTuberDemoPage extends StatefulWidget {
  const PNGTuberDemoPage({super.key, required this.controllerFactory});

  final PNGTuberControllerFactory controllerFactory;

  @override
  State<PNGTuberDemoPage> createState() => _PNGTuberDemoPageState();
}

class _PNGTuberDemoPageState extends State<PNGTuberDemoPage> {
  late final PNGTuberController _controller;
  final TransformationController _viewTransform = TransformationController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controllerFactory()..addListener(_onChanged);
    _controller.initialize();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openDiagnostics() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            _DiagnosticsPage(controller: _controller, onResetView: _resetView),
      ),
    );
    if (mounted) setState(() {});
  }

  void _resetView() => _viewTransform.value = Matrix4.identity();

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _viewTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_controller.fatalError != null || !_controller.ready) {
      return Scaffold(
        body: _ErrorView(
          message:
              '${_controller.fatalError ?? 'Character assets did not initialize.'}',
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050509),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CharacterPanel(
              controller: _controller,
              transformationController: _viewTransform,
            ),
            Positioned(
              top: 4,
              left: 8,
              right: 8,
              child: _TopBar(onOpenDiagnostics: _openDiagnostics),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _LiveMicCard(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onOpenDiagnostics});

  final VoidCallback onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              'Me PNGTuber',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Open diagnostics',
            onPressed: onOpenDiagnostics,
            icon: const Icon(Icons.tune),
          ),
        ),
      ],
    );
  }
}

class _LiveMicCard extends StatelessWidget {
  const _LiveMicCard({required this.controller});

  final PNGTuberController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  controller.listening ? Icons.graphic_eq : Icons.mic_none,
                  size: 18,
                  color: controller.listening
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.listening
                        ? 'Listening to your microphone'
                        : 'Tap the microphone to start live lip-sync',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: controller.volumeSignal,
                  builder: (context, volume, _) => Text(
                    '${(volume * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ValueListenableBuilder<double>(
              valueListenable: controller.volumeSignal,
              builder: (context, volume, _) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: volume,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: controller.toggleMicrophone,
              icon: Icon(controller.listening ? Icons.mic_off : Icons.mic),
              label: Text(
                controller.listening ? 'Stop microphone' : 'Start microphone',
              ),
            ),
            if (controller.statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                controller.statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CharacterPanel extends StatelessWidget {
  const _CharacterPanel({
    required this.controller,
    required this.transformationController,
  });

  final PNGTuberController controller;
  final TransformationController transformationController;

  @override
  Widget build(BuildContext context) {
    final track = controller.track!;
    return ColoredBox(
      color: const Color(0xFF050509),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 34, 10, 154),
          child: InteractiveViewer(
            transformationController: transformationController,
            minScale: 0.5,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(240),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 980),
              child: AspectRatio(
                aspectRatio: track.width / track.height,
                child: PNGTuberStage(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsPage extends StatelessWidget {
  const _DiagnosticsPage({required this.controller, required this.onResetView});

  final PNGTuberController controller;
  final VoidCallback onResetView;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Live lip-sync',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              controller.listening
                  ? 'The character is reacting to microphone input.'
                  : 'Start the microphone, then speak normally.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: controller.toggleMicrophone,
              icon: Icon(controller.listening ? Icons.mic_off : Icons.mic),
              label: Text(
                controller.listening ? 'Stop microphone' : 'Start microphone',
              ),
            ),
            if (controller.statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                controller.statusMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            ValueListenableBuilder<double>(
              valueListenable: controller.volumeSignal,
              builder: (context, volume, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Input level'),
                      const Spacer(),
                      Text('${(volume * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: volume),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('Sensitivity'),
                const Spacer(),
                Text(controller.sensitivity.round().toString()),
              ],
            ),
            Slider(
              value: controller.sensitivity,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: controller.setSensitivity,
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<MouthState>(
              valueListenable: controller.mouthStateSignal,
              builder: (context, mouthState, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mouth: ${mouthState.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MouthState.values
                        .map((state) {
                          return ChoiceChip(
                            label: Text(state.name),
                            selected: mouthState == state,
                            onSelected: (_) => controller.setManualState(state),
                          );
                        })
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: controller.toggleVideo,
              icon: Icon(
                controller.video!.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                controller.video!.value.isPlaying ? 'Pause loop' : 'Play loop',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onResetView,
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('Reset character view'),
            ),
            const SizedBox(height: 20),
            Text(
              'The character video is silent. Only microphone amplitude and tone are used for local mouth animation.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
