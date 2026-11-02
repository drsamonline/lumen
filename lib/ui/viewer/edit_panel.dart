import 'package:flutter/material.dart';

import '../../core/models/edit_recipe.dart';

/// The adjustment sheet. Every change is previewed live on the photo behind
/// it; nothing is written until the user taps Apply.
class EditPanel extends StatefulWidget {
  const EditPanel({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final EditRecipe initial;
  final ValueChanged<EditRecipe> onChanged;

  @override
  State<EditPanel> createState() => _EditPanelState();
}

class _EditPanelState extends State<EditPanel> {
  late EditRecipe _recipe = widget.initial;

  void _update(EditRecipe next) {
    setState(() => _recipe = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('Adjust', style: text.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: _recipe.isIdentity
                        ? null
                        : () => _update(EditRecipe.empty),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _ToolButton(
                    icon: Icons.rotate_left,
                    label: 'Left',
                    onTap: () => _update(_recipe.copyWith(
                      rotate: (_recipe.rotate - 90 + 360) % 360,
                    )),
                  ),
                  _ToolButton(
                    icon: Icons.rotate_right,
                    label: 'Right',
                    onTap: () => _update(_recipe.copyWith(
                      rotate: (_recipe.rotate + 90) % 360,
                    )),
                  ),
                  _ToolButton(
                    icon: Icons.flip,
                    label: 'Flip',
                    active: _recipe.flipH,
                    onTap: () => _update(_recipe.copyWith(flipH: !_recipe.flipH)),
                  ),
                  _ToolButton(
                    icon: Icons.flip_camera_android,
                    label: 'Flip V',
                    active: _recipe.flipV,
                    onTap: () => _update(_recipe.copyWith(flipV: !_recipe.flipV)),
                  ),
                  _ToolButton(
                    icon: Icons.crop_square,
                    label: 'Square crop',
                    active: _recipe.hasCrop,
                    onTap: () => _update(_recipe.hasCrop
                        ? _recipe.copyWith(cropL: 0, cropT: 0, cropR: 1, cropB: 1)
                        : _recipe.copyWith(cropL: 0.1, cropT: 0.1, cropR: 0.9, cropB: 0.9)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Slider(
                label: 'Brightness',
                value: _recipe.brightness,
                onChanged: (v) => _update(_recipe.copyWith(brightness: v)),
              ),
              _Slider(
                label: 'Contrast',
                value: _recipe.contrast,
                onChanged: (v) => _update(_recipe.copyWith(contrast: v)),
              ),
              _Slider(
                label: 'Saturation',
                value: _recipe.saturation,
                onChanged: (v) => _update(_recipe.copyWith(saturation: v)),
              ),
              _Slider(
                label: 'Warmth',
                value: _recipe.warmth,
                onChanged: (v) => _update(_recipe.copyWith(warmth: v)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(-1.0, 1.0),
            min: -1,
            max: 1,
            divisions: 40,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            (value * 100).round().toString(),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
