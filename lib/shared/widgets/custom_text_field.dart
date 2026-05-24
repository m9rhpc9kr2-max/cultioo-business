import 'package:flutter/material.dart';
import 'trade_republic_text_field.dart';

/// @Deprecated Use [TradeRepublicTextField] instead for consistent styling.
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final int? maxLength;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TradeRepublicTextField(
      controller: controller,
      hintText: hintText,
      obscureText: obscureText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      suffixIcon: suffixIcon,
      keyboardType: keyboardType,
      maxLength: maxLength);
  }
}
