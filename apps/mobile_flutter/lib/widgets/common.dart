import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class UCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double radius;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final Border? border;

  const UCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.radius = 16,
    this.gradient,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? UColors.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border,
        boxShadow: gradient == null
            ? [BoxShadow(color: const Color(0xFF0F2B5B).withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))]
            : null,
      ),
      child: child,
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null ? content : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content),
    );
  }
}

class UButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final bool ghost;
  final bool small;
  final IconData? icon;
  final Color? color;
  final Color? textColor;
  final double? width;

  const UButton({
    super.key,
    required this.text,
    this.onPressed,
    this.loading = false,
    this.ghost = false,
    this.small = false,
    this.icon,
    this.color,
    this.textColor,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final height = small ? 40.0 : 52.0;
    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(ghost ? UColors.navy : Colors.white),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: small ? 16 : 18, color: ghost ? (textColor ?? UColors.navy) : (textColor ?? Colors.white)), const SizedBox(width: 6)],
              Text(
                text,
                style: TextStyle(
                  fontSize: small ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: ghost ? (textColor ?? UColors.navy) : (textColor ?? Colors.white),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          );

    return Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: ghost
            ? OutlinedButton(
                onPressed: disabled ? null : onPressed,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color ?? UColors.navy.withValues(alpha: 0.35)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  backgroundColor: Colors.transparent,
                ),
                child: child,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: color == null ? UColors.goldGradient : LinearGradient(colors: [color!, color!]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: color == null
                      ? [BoxShadow(color: UColors.gold.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))]
                      : null,
                ),
                child: ElevatedButton(
                  onPressed: disabled ? null : onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: child,
                ),
              ),
      ),
    );
  }
}

class UNavBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool transparent;
  final Widget? trailing;
  final Color? color;

  const UNavBar({super.key, required this.title, this.transparent = false, this.trailing, this.color});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      backgroundColor: transparent ? Colors.transparent : (color ?? UColors.bg),
      elevation: 0,
      leading: Navigator.of(context).canPop()
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
      actions: trailing == null ? null : [trailing!, const SizedBox(width: 12)],
    );
  }
}

class UTag extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;

  const UTag({super.key, required this.text, this.color = UColors.navy, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: filled ? Colors.white : color),
      ),
    );
  }
}

class UEmpty extends StatelessWidget {
  final String text;
  final String? sub;
  final IconData icon;
  final Widget? action;

  const UEmpty({super.key, required this.text, this.sub, this.icon = Icons.inbox_outlined, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: UColors.navy.withValues(alpha: 0.05), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: UColors.navy.withValues(alpha: 0.35)),
            ),
            const SizedBox(height: 14),
            Text(text, style: UText.sub.copyWith(color: UColors.textSub)),
            if (sub != null) ...[const SizedBox(height: 6), Text(sub!, style: UText.tiny, textAlign: TextAlign.center)],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class ULoading extends StatelessWidget {
  const ULoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.2, color: UColors.gold)),
        ),
      );
}

class USectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const USectionTitle({super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Text(title, style: UText.h3.copyWith(fontSize: 16)),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Row(children: [
                Text(action!, style: UText.sub.copyWith(fontSize: 12)),
                const Icon(Icons.chevron_right, size: 16, color: UColors.textLight),
              ]),
            ),
        ],
      ),
    );
  }
}

class UField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final List<TextInputFormatter>? formatters;

  const UField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.keyboardType,
    this.maxLength,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.enabled = true,
    this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: UText.sub.copyWith(fontSize: 12, color: UColors.textSub)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          maxLength: maxLength,
          enabled: enabled,
          onChanged: onChanged,
          inputFormatters: formatters,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: UText.sub.copyWith(color: UColors.textLight),
            counterText: '',
            filled: true,
            fillColor: UColors.bg,
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: UColors.gold, width: 1.2)),
          ),
        ),
      ],
    );
  }
}

class UPhasedBar extends StatelessWidget {
  final int active; // 0-based
  final List<String> labels;
  const UPhasedBar({super.key, required this.active, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final done = i <= active;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: done ? UColors.gold : UColors.line,
                  shape: BoxShape.circle,
                ),
                child: Icon(done ? Icons.check : Icons.circle, size: done ? 13 : 6, color: done ? Colors.white : UColors.textLight),
              ),
              const SizedBox(width: 6),
              Text(labels[i], style: UText.tiny.copyWith(color: done ? UColors.text : UColors.textLight, fontWeight: done ? FontWeight.w600 : FontWeight.w400)),
              if (i < labels.length - 1)
                Expanded(child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 6), color: done ? UColors.gold.withValues(alpha: 0.5) : UColors.line)),
            ],
          ),
        );
      }),
    );
  }
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? UColors.danger : UColors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? content,
  String confirmText = '确认',
  String cancelText = '取消',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: UColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: UText.h3),
      content: content == null ? null : Text(content, style: UText.sub),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelText, style: UText.sub)),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmText, style: const TextStyle(color: UColors.navy, fontWeight: FontWeight.w600))),
      ],
    ),
  );
  return r ?? false;
}
