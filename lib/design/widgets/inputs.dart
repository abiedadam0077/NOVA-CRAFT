import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../theme.dart';
import '../tokens.dart';

class NovaField extends StatelessWidget {
  const NovaField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.helper,
    this.errorText,
    this.inputFormatters,
    this.onSubmitted,
    this.monospace = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final String? helper;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final bool monospace;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(label!.toUpperCase(), style: NovaTextStyles.caption(p.textMuted)),
          ),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          maxLines: obscure ? 1 : maxLines,
          minLines: minLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autofocus: autofocus,
          enabled: enabled,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          style: monospace
              ? NovaTextStyles.mono(13.5, p.text)
              : NovaTextStyles.body(p.text).copyWith(fontWeight: FontWeight.w600),
          cursorColor: p.primaryBright,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helper,
            helperMaxLines: 3,
            errorMaxLines: 3,
            helperStyle: NovaTextStyles.small(p.textDim),
            errorStyle: NovaTextStyles.small(p.dangerSoft),
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 19) : null,
            suffixIcon: suffix,
            isDense: false,
          ),
        ),
      ],
    );
  }
}

class NovaSearchField extends StatelessWidget {
  const NovaSearchField({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.onClear,
    this.trailing,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: p.isDark ? p.cardSoft.withValues(alpha: 0.9) : Colors.white,
        borderRadius: NovaRadii.rPill,
        border: Border.all(color: p.stroke),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, size: 19, color: p.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: NovaTextStyles.body(p.text).copyWith(fontWeight: FontWeight.w500),
              cursorColor: p.primaryBright,
              decoration: InputDecoration(
                hintText: hint ?? L10n.t('search'),
                hintStyle: NovaTextStyles.body(p.textDim),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                if (onClear != null) onClear!();
                if (onChanged != null) onChanged!('');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.close_rounded, size: 17, color: p.textDim),
              ),
            ),
          if (trailing != null) trailing! else const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class NovaSwitchTile extends StatelessWidget {
  const NovaSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: NovaRadii.rSm,
      child: Padding(
        padding: padding,
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.12),
                  borderRadius: NovaRadii.rSm,
                ),
                child: Icon(icon, size: 17, color: p.primaryBright),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: NovaTextStyles.bodyStrong(p.text)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle!, style: NovaTextStyles.small(p.textMuted)),
                    ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class NovaSliderTile extends StatelessWidget {
  const NovaSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.suffix,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String? suffix;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: p.textDim),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(label, style: NovaTextStyles.body(p.text))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.12),
                borderRadius: NovaRadii.rXs,
                border: Border.all(color: p.primary.withValues(alpha: 0.28)),
              ),
              child: Text(
                '${value.round()}${suffix ?? ''}',
                style: NovaTextStyles.smallStrong(p.primaryBright),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class NovaDropdown<T> extends StatelessWidget {
  const NovaDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String? label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(label!.toUpperCase(), style: NovaTextStyles.caption(p.textMuted)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.isDark ? p.cardSoft : Colors.white,
            borderRadius: NovaRadii.rMd,
            border: Border.all(color: p.stroke),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              hint: hint != null ? Text(hint!, style: NovaTextStyles.body(p.textDim)) : null,
              dropdownColor: p.cardHigh,
              borderRadius: NovaRadii.rMd,
              icon: Icon(Icons.expand_more_rounded, color: p.textMuted),
              style: NovaTextStyles.body(p.text).copyWith(fontWeight: FontWeight.w600),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
