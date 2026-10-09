import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/formatters.dart';
import '../errors/app_exception.dart';
import '../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.page,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: const BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class CurrencyText extends StatelessWidget {
  const CurrencyText({
    super.key,
    required this.cents,
    this.style,
    this.prefix = '',
    this.suffix = '',
  });
  final num cents;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  @override
  Widget build(BuildContext context) => Text(
    '$prefix${pesos(cents)}$suffix',
    style: AppTheme.moneyStyle.merge(style),
  );
}

class LocalPhoto extends StatelessWidget {
  const LocalPhoto({
    super.key,
    this.path,
    this.size = 56,
    this.icon = Icons.inventory_2_outlined,
  });
  final String? path;
  final double size;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.softPrimary,
      child: Center(
        child: Icon(icon, color: AppColors.primary, size: size * .42),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null || path!.isEmpty
            ? placeholder
            : Image.file(
                File(path!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.softPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary, size: 42),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Could not load your records',
    message: message,
    action: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice({super.key, required this.message, this.warning = false});
  final String message;
  final bool warning;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? AppColors.softAmber : AppColors.softPrimary,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.info_outline : Icons.offline_bolt_outlined,
            size: 20,
            color: warning ? AppColors.amber : AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: warning ? AppColors.amberText : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.validator,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.suffixIcon,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? minLines;
  final bool enabled;
  final Widget? suffixIcon;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    enabled: enabled,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      suffixIcon: suffixIcon,
    ),
    validator: validator,
    onChanged: onChanged,
    keyboardType: keyboardType,
    maxLines: maxLines,
    minLines: minLines,
    textCapitalization: keyboardType == null
        ? TextCapitalization.sentences
        : TextCapitalization.none,
    autovalidateMode: AutovalidateMode.onUserInteraction,
  );
}

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Saving…',
    this.icon = Icons.check,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String busyLabel;
  final IconData icon;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy ? null : onPressed,
    icon: SizedBox(
      width: 20,
      height: 20,
      child: busy
          ? CircularProgressIndicator(strokeWidth: 2, semanticsLabel: busyLabel)
          : Icon(icon, size: 20),
    ),
    label: Text(busy ? busyLabel : label),
  );
}

void showAppError(BuildContext context, Object error) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(userMessage(error))));
