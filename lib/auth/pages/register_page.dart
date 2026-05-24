import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../../shared/services/app_localizations.dart';
import '../../shared/services/app_settings.dart';
import '../../shared/widgets/page_indicator.dart';
import '../../shared/widgets/top_notification.dart';
import '../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../shared/widgets/trade_republic_button.dart';
import '../../shared/widgets/trade_republic_list_tile.dart';
import '../../shared/widgets/trade_republic_text_field.dart';
import '../../shared/widgets/trade_republic_theme.dart';
import '../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Country data
// ─────────────────────────────────────────────────────────────────────────────
class _Country {
  final String flag;
  final String name;
  final String code;
  const _Country(this.flag, this.name, this.code);
}

const List<_Country> _countries = [
  _Country('🇺🇸', 'United States', '+1'),
  _Country('🇨🇦', 'Canada', '+1'),
  _Country('🇲🇽', 'Mexico', '+52'),

  // European Union
  _Country('🇩🇪', 'Germany',        '+49'),
  _Country('🇦🇹', 'Austria',        '+43'),
  _Country('🇧🇪', 'Belgium',        '+32'),
  _Country('🇧🇬', 'Bulgaria',       '+359'),
  _Country('🇭🇷', 'Croatia',        '+385'),
  _Country('🇨🇾', 'Cyprus',         '+357'),
  _Country('🇨🇿', 'Czech Republic', '+420'),
  _Country('🇩🇰', 'Denmark',        '+45'),
  _Country('🇪🇪', 'Estonia',        '+372'),
  _Country('🇫🇮', 'Finland',        '+358'),
  _Country('🇫🇷', 'France',         '+33'),
  _Country('🇬🇷', 'Greece',         '+30'),
  _Country('🇭🇺', 'Hungary',        '+36'),
  _Country('🇮🇪', 'Ireland',        '+353'),
  _Country('🇮🇹', 'Italy',          '+39'),
  _Country('🇱🇻', 'Latvia',         '+371'),
  _Country('🇱🇹', 'Lithuania',      '+370'),
  _Country('🇱🇺', 'Luxembourg',     '+352'),
  _Country('🇲🇹', 'Malta',          '+356'),
  _Country('🇳🇱', 'Netherlands',    '+31'),
  _Country('🇵🇱', 'Poland',         '+48'),
  _Country('🇵🇹', 'Portugal',       '+351'),
  _Country('🇷🇴', 'Romania',        '+40'),
  _Country('🇸🇰', 'Slovakia',       '+421'),
  _Country('🇸🇮', 'Slovenia',       '+386'),
  _Country('🇪🇸', 'Spain',          '+34'),
  _Country('🇸🇪', 'Sweden',         '+46'),

  // Requested extra country
  _Country('🇷🇺', 'Russia', '+7'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Lowercase input formatter
// ─────────────────────────────────────────────────────────────────────────────
class _LowercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue updated) =>
      updated.copyWith(text: updated.text.toLowerCase());
}

// ─────────────────────────────────────────────────────────────────────────────
// Country Picker Widget
// ─────────────────────────────────────────────────────────────────────────────
class _CountryPickerButton extends StatelessWidget {
  final _Country selected;
  final bool isLight;
  final VoidCallback onTap;

  const _CountryPickerButton({
    required this.selected,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fg.withOpacity(0.06),
          borderRadius: BorderRadius.circular(TradeRepublicTheme.radiusMedium),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(selected.flag, style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6,),
          const SizedBox(width: 6),
          Text(
              String.fromCharCode(40) + selected.code + String.fromCharCode(41),
              style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), fontWeight: FontWeight.w600, color: fg)),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_down, size: 12, color: fg.withOpacity(0.4)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Country Picker Bottom Sheet Widget
// ─────────────────────────────────────────────────────────────────────────────
class _CountryPickerSheet extends StatelessWidget {
  final _Country selected;
  final bool isLight;
  final ValueChanged<_Country> onSelected;

  const _CountryPickerSheet({
    required this.selected,
    required this.isLight,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(AppLocalizations.of(context)!.tr('Select Country'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _countries.length,
            itemBuilder: (_, i) {
              final c = _countries[i];
              final isSel = c.name == selected.name;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isSel ? fg.withOpacity(0.08) : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(TradeRepublicTheme.radiusMedium),
                ),
                child: TradeRepublicListTile(
                  title: '${c.flag}  ${c.name}',
                  subtitle: c.code,
                  trailing: isSel
                      ? Icon(CupertinoIcons.checkmark_alt, size: 16, color: fg)
                      : null,
                  onTap: () {
                    onSelected(c);
                    Navigator.pop(context);
                  },
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              );
            },
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
      ]),
    );
  }
}

class _BusinessSizePickerSheet extends StatelessWidget {
  final String selected;
  final bool isLight;
  final ValueChanged<String> onSelected;

  const _BusinessSizePickerSheet({
    required this.selected,
    required this.isLight,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    final sizes = const [
      '1-10 employees',
      '11-50 employees',
      '51-100 employees',
      '101-500 employees',
      '500+ employees',
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business size',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        const SizedBox(height: 10),
        ...sizes.map((size) {
          final isSelected = size == selected;
          return TradeRepublicListTile(
            title: size,
            trailing: isSelected
                ? Icon(CupertinoIcons.checkmark_alt, color: fg)
                : null,
            onTap: () {
              onSelected(size);
              Navigator.pop(context);
            },
            padding: const EdgeInsets.symmetric(vertical: 10),
          );
        }),
      ],
    );
  }
}

class _CupertinoBirthdateSheet extends StatefulWidget {
  final bool isLight;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDone;

  const _CupertinoBirthdateSheet({
    required this.isLight,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDone,
  });

  @override
  State<_CupertinoBirthdateSheet> createState() => _CupertinoBirthdateSheetState();
}

class _CupertinoBirthdateSheetState extends State<_CupertinoBirthdateSheet> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isLight ? Colors.black : Colors.white;
    return SizedBox(
      height: 300,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: fg.withOpacity(0.08)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  height: 36,
                  width: 88,
                  isSecondary: true,
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  AppLocalizations.of(context)?.dateOfBirth ?? AppLocalizations.of(context)!.tr('Date of birth'),
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                  ),
                ),
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.done ?? AppLocalizations.of(context)!.tr('Done'),
                  height: 36,
                  width: 88,
                  onPressed: () {
                    widget.onDone(_selectedDate);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: widget.isLight ? Brightness.light : Brightness.dark,
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _selectedDate,
                minimumDate: widget.firstDate,
                maximumDate: widget.lastDate,
                onDateTimeChanged: (d) => _selectedDate = d,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step Page Widget
// ─────────────────────────────────────────────────────────────────────────────
class _StepPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLight;
  final bool isDesktop;
  final List<Widget> children;

  const _StepPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLight,
    required this.isDesktop,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final fg  = isLight ? Colors.black : Colors.white;
    final sub = fg.withOpacity(0.4);
    final hPad = isDesktop ? 32.0 : 24.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: isDesktop ? 40 : 32),
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: fg.withOpacity(0.07),
              borderRadius: BorderRadius.circular(TradeRepublicTheme.radiusMedium),
            ),
            child: Icon(icon, size: 26, color: fg),
          ),
          SizedBox(height: isDesktop ? 24 : 20),
          Text(title,
            style: TextStyle(
              fontSize: isDesktop ? 28 : 26,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), color: sub)),
          SizedBox(height: isDesktop ? 36 : 28),
          ...children,
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Row Widget
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color fg;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: fg.withOpacity(0.4)),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 13, color: fg.withOpacity(0.4))),
      const Spacer(),
      Flexible(
        child: Text(value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OTP Code Box Widget (single digit)
// ─────────────────────────────────────────────────────────────────────────────
class _CodeBox extends StatelessWidget {
  final String char;
  final bool isLight;
  final bool isFocused;

  const _CodeBox({required this.char, required this.isLight, this.isFocused = false});

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 40, height: 50,
      decoration: BoxDecoration(
        color: fg.withOpacity(isFocused ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isFocused ? fg.withOpacity(0.6) : fg.withOpacity(0.12),
          width: isFocused ? 1.5 : 1,
        ),
      ),
      child: Center(
        child: Text(char,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register Page
// ─────────────────────────────────────────────────────────────────────────────
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  static const int _totalPages = 4;

  // ── Step 1: Account
  final _usernameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _birthdateCtrl = TextEditingController();
  bool? _usernameAvailable;
  bool  _checkingUsername = false;
  Timer? _usernameDebounce;
  bool? _emailAvailable;
  bool _checkingEmail = false;
  Timer? _emailDebounce;

  // ── Step 2: Company
  final _companyCtrl = TextEditingController();
  final _businessDescriptionCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseNumberCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _businessCountryCtrl = TextEditingController(text: 'United States');
  final _businessSizeCtrl = TextEditingController(text: '1-10 employees');
  final _phoneCtrl   = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _einCtrl     = TextEditingController();
  _Country _selectedCountry = _countries.first;
  String _businessCountry = 'United States';
  String _businessSize = '1-10 employees';

  // ── Step 3: Review
  bool _acceptTerms = false;
  bool _isLoading   = false;

  // ── Step 4: Email Verification
  final _codeCtrl    = TextEditingController();
  final _codeFocus   = FocusNode();
  bool  _verifying   = false;
  bool  _resending   = false;
  String _pendingUsername = '';
  String _pendingEmail    = '';

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(_onUsernameChanged);
    _emailCtrl.addListener(_onEmailChanged);
    _phoneCtrl.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _emailDebounce?.cancel();
    _pageCtrl.dispose();
    _usernameCtrl..removeListener(_onUsernameChanged)..dispose();
    _emailCtrl.removeListener(_onEmailChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _birthdateCtrl.dispose();
    _companyCtrl.dispose();
    _businessDescriptionCtrl.dispose();
    _streetCtrl.dispose();
    _houseNumberCtrl.dispose();
    _zipCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _businessCountryCtrl.dispose();
    _businessSizeCtrl.dispose();
    _phoneCtrl.removeListener(_onPhoneChanged);
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _einCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ── Username availability check ───────────────────────────────────────────
  void _onUsernameChanged() {
    final u = _usernameCtrl.text.trim();
    _usernameDebounce?.cancel();
    if (u.length < 3) {
      setState(() { _usernameAvailable = null; _checkingUsername = false; });
      return;
    }
    setState(() => _checkingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () => _checkUsername(u));
  }

  Future<void> _checkUsername(String u) async {
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/check-username?username=${Uri.encodeComponent(u)}&scope=seller'),
      ).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      final data = json.decode(resp.body);
      setState(() {
        _usernameAvailable = data['available'] == true;
        _checkingUsername  = false;
      });
    } catch (_) {
      if (mounted) setState(() { _usernameAvailable = null; _checkingUsername = false; });
    }
  }

  // ── Email availability check (cultioo_users only) ───────────────────────
  void _onEmailChanged() {
    final e = _emailCtrl.text.trim().toLowerCase();
    _emailDebounce?.cancel();

    if (e.isEmpty || !e.contains('@')) {
      setState(() {
        _emailAvailable = null;
        _checkingEmail = false;
      });
      return;
    }

    setState(() => _checkingEmail = true);
    _emailDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkEmail(e),
    );
  }

  Future<void> _checkEmail(String e) async {
    try {
      final resp = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/auth/check-email?email=${Uri.encodeComponent(e)}',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;

      final data = json.decode(resp.body);
      setState(() {
        final exists = data['exists'] == true;
        _emailAvailable = !exists;
        _checkingEmail = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _emailAvailable = null;
          _checkingEmail = false;
        });
      }
    }
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  String _formatPhoneForSelectedCountry(String input) {
    final digits = _onlyDigits(input);
    if (digits.isEmpty) return '';

    // Keep numbers realistic and readable
    final maxLen = _selectedCountry.code == '+1'
        ? 10
        : _selectedCountry.code == '+52'
            ? 10
            : _selectedCountry.code == '+7'
                ? 10
                : 12;
    final d = digits.length > maxLen ? digits.substring(0, maxLen) : digits;

    // Formats like: (123) 456 78 90 / (55) 1234 5678 / (123) 456 7890
    final groups = _selectedCountry.code == '+1'
        ? <int>[3, 3, 4]
        : _selectedCountry.code == '+52'
            ? <int>[2, 4, 4]
            : _selectedCountry.code == '+7'
                ? <int>[3, 3, 2, 2]
                : <int>[3, 3, 2, 2, 2];

    int index = 0;
    final parts = <String>[];
    for (final size in groups) {
      if (index >= d.length) break;
      final end = (index + size > d.length) ? d.length : index + size;
      parts.add(d.substring(index, end));
      index = end;
    }

    if (parts.isEmpty) return '';

    final first = '(${parts.first})';
    if (parts.length == 1) return first;

    return '$first ${parts.sublist(1).join(' ')}';
  }

  void _onPhoneChanged() {
    final formatted = _formatPhoneForSelectedCountry(_phoneCtrl.text);
    if (_phoneCtrl.text == formatted) return;
    _phoneCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _fullPhoneWithCountry() {
    final local = _phoneCtrl.text.trim();
    if (local.isEmpty) return '(${_selectedCountry.code})';
    return '(${_selectedCountry.code}) $local';
  }

  String _formatDateYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _buildBusinessAddress() {
    final street = _streetCtrl.text.trim();
    final house = _houseNumberCtrl.text.trim();
    final zip = _zipCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final state = _stateCtrl.text.trim();
    final country = _businessCountry.trim();

    final parts = <String>[];
    final streetLine = [street, house].where((p) => p.isNotEmpty).join(' ');
    if (streetLine.isNotEmpty) parts.add(streetLine);
    if (zip.isNotEmpty || city.isNotEmpty) {
      parts.add([zip, city].where((p) => p.isNotEmpty).join(' '));
    }
    if (state.isNotEmpty) parts.add(state);
    if (country.isNotEmpty) parts.add(country);

    return parts.join(', ');
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final firstDate = DateTime(1900, 1, 1);
    final defaultDate = DateTime(now.year - 25, now.month, now.day);

    DateTime selectedDate = defaultDate;
    if (_birthdateCtrl.text.trim().isNotEmpty) {
      try {
        selectedDate = DateTime.parse(_birthdateCtrl.text.trim());
      } catch (_) {
        selectedDate = defaultDate;
      }
    }

    final isLight = AppSettings().isLightMode(context);
    await TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: 360,
      showDragHandle: true,
      child: _CupertinoBirthdateSheet(
        isLight: isLight,
        initialDate: selectedDate,
        firstDate: firstDate,
        lastDate: now,
        onDone: (d) {
          if (!mounted) return;
          setState(() => _birthdateCtrl.text = _formatDateYmd(d));
        },
      ),
    );
  }

  Future<void> _pickBusinessCountry(bool isLight) async {
    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      showDragHandle: true,
      child: _CountryPickerSheet(
        selected: _countries.firstWhere(
          (c) => c.name == _businessCountry,
          orElse: () => _selectedCountry,
        ),
        isLight: isLight,
        onSelected: (c) {
          setState(() {
            _businessCountry = c.name;
            _businessCountryCtrl.text = c.name;
          });
        },
      ),
    );
  }

  Future<void> _pickBusinessSize(bool isLight) async {
    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _BusinessSizePickerSheet(
        selected: _businessSize,
        isLight: isLight,
        onSelected: (size) {
          setState(() {
            _businessSize = size;
            _businessSizeCtrl.text = size;
          });
        },
      ),
    );
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _next() {
    if (_currentPage == 0) {
      final u = _usernameCtrl.text.trim();
      final e = _emailCtrl.text.trim();
      final p = _passwordCtrl.text;
      if (u.isEmpty || e.isEmpty || p.isEmpty || _firstNameCtrl.text.trim().isEmpty || _lastNameCtrl.text.trim().isEmpty || _birthdateCtrl.text.trim().isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Please fill in all fields') ?? AppLocalizations.of(context)!.tr('Please fill in all fields'));
        return;
      }
      if (!e.contains('@')) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Please enter a valid email') ?? AppLocalizations.of(context)!.tr('Please enter a valid email'));
        return;
      }
      if (p.length < 8) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Password must be at least 8 characters') ?? AppLocalizations.of(context)!.tr('Password must be at least 8 characters'));
        return;
      }
      if (_usernameAvailable == false) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Username is already taken') ?? AppLocalizations.of(context)!.tr('Username is already taken'));
        return;
      }
      if (_emailAvailable == false) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Email is already registered') ?? AppLocalizations.of(context)!.tr('Email is already registered'));
        return;
      }
    }
    if (_currentPage == 1) {
      if (_streetCtrl.text.trim().isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Street is required') ?? AppLocalizations.of(context)!.tr('Street is required'));
        return;
      }
      if (_houseNumberCtrl.text.trim().isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('House number is required') ?? AppLocalizations.of(context)!.tr('House number is required'));
        return;
      }
      if (_zipCtrl.text.trim().isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('ZIP code is required') ?? AppLocalizations.of(context)!.tr('ZIP code is required'));
        return;
      }
      if (_cityCtrl.text.trim().isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('City is required') ?? AppLocalizations.of(context)!.tr('City is required'));
        return;
      }
      if (_businessCountry.trim().isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('Business country is required') ?? AppLocalizations.of(context)!.tr('Business country is required'));
        return;
      }
    }
    if (_currentPage < _totalPages - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _back() {
    if (_currentPage > 0 && _currentPage < 3) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else if (_currentPage == 0) {
      Navigator.pop(context);
    }
    // Page 3 (verification) — no back
  }

  // ── Submit (after accepting terms) ────────────────────────────────────────
  Future<void> _submit() async {
    if (!_acceptTerms) {
      TopNotification.error(context, AppLocalizations.of(context)!.tr('Please accept the terms first') ?? AppLocalizations.of(context)!.tr('Please accept the terms first'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final fullPhone = _fullPhoneWithCountry();
      final fullAddress = _buildBusinessAddress();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username':    _usernameCtrl.text.trim().toLowerCase(),
          'firstname':   _firstNameCtrl.text.trim(),
          'lastname':    _lastNameCtrl.text.trim(),
          'email':       _emailCtrl.text.trim(),
          'password':    _passwordCtrl.text,
          'birthdate':   _birthdateCtrl.text.trim(),
            'companyName': _companyCtrl.text.trim().isNotEmpty
              ? _companyCtrl.text.trim()
              : null,
          'businessDescription': _businessDescriptionCtrl.text.trim(),
          'businessAddress': fullAddress,
          'businessCountry': _businessCountry.trim(),
          'businessSize': _businessSize.trim(),
          'phone':       fullPhone,
          'website':     _websiteCtrl.text.trim().isNotEmpty ? _websiteCtrl.text.trim() : null,
          'ein':         _einCtrl.text.trim().isNotEmpty ? _einCtrl.text.trim() : null,
        }),
      );
      if (!mounted) return;
      final data = json.decode(resp.body);
      final isSuccess = data['success'] == true;
      final requiresVerification = data['requiresVerification'] == true;
      if (isSuccess && (resp.statusCode == 201 || (resp.statusCode == 200 && requiresVerification))) {
        _pendingUsername = data['username'] ?? _usernameCtrl.text.trim().toLowerCase();
        _pendingEmail    = data['email']    ?? _emailCtrl.text.trim();
        // Go to verification page
        _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _codeFocus.requestFocus();
        });
      } else {
        TopNotification.error(context, data['message'] ?? AppLocalizations.of(context)!.tr('Registration failed'));
      }
    } catch (e) {
      if (mounted) TopNotification.error(context, AppLocalizations.of(context)!.tr('Connection error') ?? AppLocalizations.of(context)!.tr('Connection error'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Verify email code ─────────────────────────────────────────────────────
  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 8) {
      TopNotification.error(context, AppLocalizations.of(context)!.tr('Please enter the 8-digit code') ?? AppLocalizations.of(context)!.tr('Please enter the 8-digit code'));
      return;
    }
    setState(() => _verifying = true);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': _pendingUsername, 'code': code}),
      );
      if (!mounted) return;
      final data = json.decode(resp.body);
      if (resp.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token',   data['token'] ?? AppLocalizations.of(context)!.tr(''));
        await prefs.setString('username',     data['user']['username'] ?? AppLocalizations.of(context)!.tr(''));
        await prefs.setString('company_name', data['user']['companyName'] ?? AppLocalizations.of(context)!.tr(''));
        await prefs.setString('email',        data['user']['email'] ?? AppLocalizations.of(context)!.tr(''));
        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        TopNotification.error(context, data['message'] ?? AppLocalizations.of(context)!.tr('Invalid code'));
      }
    } catch (e) {
      if (mounted) TopNotification.error(context, AppLocalizations.of(context)!.tr('Connection error') ?? AppLocalizations.of(context)!.tr('Connection error'));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // ── Resend code ───────────────────────────────────────────────────────────
  Future<void> _resendCode() async {
    setState(() => _resending = true);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/resend-verification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': _pendingUsername}),
      );
      if (!mounted) return;
      final data = json.decode(resp.body);
      if (data['success'] == true) {
        TopNotification.success(
          context,
          '${AppLocalizations.of(context)!.tr('New code sent to')} $_pendingEmail',
        );
        _codeCtrl.clear();
      } else {
        TopNotification.error(context, data['message'] ?? AppLocalizations.of(context)!.tr('Could not resend code'));
      }
    } catch (_) {
      if (mounted) TopNotification.error(context, AppLocalizations.of(context)!.tr('Connection error') ?? AppLocalizations.of(context)!.tr('Connection error'));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  // ── Country picker ────────────────────────────────────────────────────────
  void _showCountryPicker(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      showDragHandle: true,
      child: _CountryPickerSheet(
        selected: _selectedCountry,
        isLight: isLight,
        onSelected: (c) {
          setState(() => _selectedCountry = c);
          _onPhoneChanged();
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLight   = AppSettings().isLightMode(context);
    final fg        = isLight ? Colors.black : Colors.white;
    final sub       = fg.withOpacity(0.4);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 480.0 : double.infinity),
            child: Column(children: [
              // ── Top bar
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32 : 20, vertical: isDesktop ? 20 : 14),
                child: Row(children: [
                  // Hide back on verification page
                  if (_currentPage < 3)
                    TradeRepublicTap(
                      onTap: _back,
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                            color: fg.withOpacity(0.06), shape: BoxShape.circle),
                        child: Icon(CupertinoIcons.back, size: 18, color: fg),
                      ),
                    )
                  else
                    const SizedBox(width: 38),
                  const Spacer(),
                  PageIndicator(
                    currentPage: _currentPage,
                    pageCount: _totalPages,
                    pageController: _pageCtrl,
                  ),
                  const Spacer(),
                  const SizedBox(width: 38),
                ]),
              ),

              // ── Pages
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    // ── Page 1: Account ───────────────────────────────────
                    _StepPage(
                      icon: CupertinoIcons.person_circle,
                      title: AppLocalizations.of(context)!.tr('Your Account') ?? AppLocalizations.of(context)!.tr('Your Account'),
                      subtitle: AppLocalizations.of(context)!.tr('Set up your login credentials') ?? AppLocalizations.of(context)!.tr('Set up your login credentials'),
                      isLight: isLight,
                      isDesktop: isDesktop,
                      children: [
                        Stack(children: [
                          TradeRepublicTextField(
                            controller: _usernameCtrl,
                            hintText: AppLocalizations.of(context)!.tr('Username  (lowercase only)') ?? AppLocalizations.of(context)!.tr('Username  (lowercase only)'),
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.none,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_\.]')),
                              _LowercaseFormatter(),
                            ],
                            prefixIcon: Icon(CupertinoIcons.at, size: 18, color: sub),
                          ),
                          Positioned(
                            right: 14, top: 0, bottom: 0,
                            child: Center(child: _buildUsernameStatus(fg)),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Row(children: [
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: _firstNameCtrl,
                              hintText: AppLocalizations.of(context)!.tr('First name *') ?? AppLocalizations.of(context)!.tr('First name *'),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              prefixIcon: Icon(CupertinoIcons.person, size: 18, color: sub),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: _lastNameCtrl,
                              hintText: AppLocalizations.of(context)!.tr('Last name *') ?? AppLocalizations.of(context)!.tr('Last name *'),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              // Keep identical input metrics as first name field.
                              prefixIcon: Icon(
                                CupertinoIcons.person,
                                size: 18,
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Stack(children: [
                          TradeRepublicTextField(
                            controller: _emailCtrl,
                            hintText: AppLocalizations.of(context)!.tr('Email address') ?? AppLocalizations.of(context)!.tr('Email address'),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            prefixIcon: Icon(CupertinoIcons.mail, size: 18, color: sub),
                          ),
                          Positioned(
                            right: 14, top: 0, bottom: 0,
                            child: Center(child: _buildEmailStatus(fg)),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicTap(
                          onTap: _pickBirthdate,
                          child: AbsorbPointer(
                            child: TradeRepublicTextField(
                              controller: _birthdateCtrl,
                              hintText: AppLocalizations.of(context)!.tr('Date of birth *  (YYYY-MM-DD)') ?? AppLocalizations.of(context)!.tr('Date of birth *  (YYYY-MM-DD)'),
                              textInputAction: TextInputAction.next,
                              prefixIcon: Icon(CupertinoIcons.calendar, size: 18, color: sub),
                            ),
                          ),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicTextField(
                          controller: _passwordCtrl,
                          hintText: AppLocalizations.of(context)!.tr('Password  (min. 8 characters)') ?? AppLocalizations.of(context)!.tr('Password  (min. 8 characters)'),
                          obscureText: true,
                          showVisibilityToggle: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _next(),
                        ),
                      ],
                    ),

                    // ── Page 2: Company ───────────────────────────────────
                    _StepPage(
                      icon: CupertinoIcons.building_2_fill,
                      title: AppLocalizations.of(context)!.tr('Your Company') ?? AppLocalizations.of(context)!.tr('Your Company'),
                      subtitle: AppLocalizations.of(context)!.tr('Tell us about your business') ?? AppLocalizations.of(context)!.tr('Tell us about your business'),
                      isLight: isLight,
                      isDesktop: isDesktop,
                      children: [
                        TradeRepublicTextField(
                          controller: _companyCtrl,
                          hintText: AppLocalizations.of(context)!.tr('Company / Business name (optional)') ?? AppLocalizations.of(context)!.tr('Company / Business name (optional)'),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icon(CupertinoIcons.briefcase, size: 18, color: sub),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicTextField(
                          controller: _businessDescriptionCtrl,
                          hintText: AppLocalizations.of(context)!.tr('Business description (optional)') ?? AppLocalizations.of(context)!.tr('Business description (optional)'),
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icon(CupertinoIcons.doc_plaintext, size: 18, color: sub),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: TradeRepublicTextField(
                              controller: _streetCtrl,
                              hintText: AppLocalizations.of(context)!.tr('Street *') ?? AppLocalizations.of(context)!.tr('Street *'),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              prefixIcon: Icon(CupertinoIcons.location_solid, size: 18, color: sub),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TradeRepublicTextField(
                              controller: _houseNumberCtrl,
                              hintText: AppLocalizations.of(context)!.tr('No. *') ?? AppLocalizations.of(context)!.tr('No. *'),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Row(children: [
                          Expanded(
                            flex: 2,
                            child: TradeRepublicTextField(
                              controller: _zipCtrl,
                              hintText: AppLocalizations.of(context)!.tr('ZIP *') ?? AppLocalizations.of(context)!.tr('ZIP *'),
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TradeRepublicTextField(
                              controller: _cityCtrl,
                              hintText: AppLocalizations.of(context)!.tr('City *') ?? AppLocalizations.of(context)!.tr('City *'),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicTextField(
                          controller: _stateCtrl,
                          hintText: AppLocalizations.of(context)!.tr('State / Region (optional)') ?? AppLocalizations.of(context)!.tr('State / Region (optional)'),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Row(children: [
                          Expanded(
                            child: TradeRepublicTap(
                              onTap: () => _pickBusinessCountry(isLight),
                              child: AbsorbPointer(
                                child: TradeRepublicTextField(
                                  controller: _businessCountryCtrl,
                                  hintText: AppLocalizations.of(context)!.tr('Business country *') ?? AppLocalizations.of(context)!.tr('Business country *'),
                                  prefixIcon: Icon(CupertinoIcons.globe, size: 18, color: sub),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TradeRepublicTap(
                              onTap: () => _pickBusinessSize(isLight),
                              child: AbsorbPointer(
                                child: TradeRepublicTextField(
                                  controller: _businessSizeCtrl,
                                  hintText: AppLocalizations.of(context)!.tr('Business size (optional)') ?? AppLocalizations.of(context)!.tr('Business size (optional)'),
                                  prefixIcon: Icon(CupertinoIcons.person_2, size: 18, color: sub),
                                ),
                              ),
                            ),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicTextField(
                          controller: _websiteCtrl,
                          hintText: AppLocalizations.of(context)!.tr('Website  (optional)') ?? AppLocalizations.of(context)!.tr('Website  (optional)'),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icon(CupertinoIcons.globe, size: 18, color: sub),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        // Phone row (Pflichtfeld)
                        Row(children: [
                          _CountryPickerButton(
                            selected: _selectedCountry,
                            isLight: isLight,
                            onTap: () => _showCountryPicker(isLight),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: _phoneCtrl,
                              hintText: AppLocalizations.of(context)!.tr('Phone (optional)  (123) 456 78 90') ?? AppLocalizations.of(context)!.tr('Phone (optional)  (123) 456 78 90'),
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\s\(\)]'))],
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicTextField(
                          controller: _einCtrl,
                          hintText: AppLocalizations.of(context)!.tr('EIN / Tax ID  (optional)') ?? AppLocalizations.of(context)!.tr('EIN / Tax ID  (optional)'),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _next(),
                          prefixIcon: Icon(CupertinoIcons.doc_text, size: 18, color: sub),
                        ),
                      ],
                    ),

                    // ── Page 3: Review & Terms ────────────────────────────
                    _StepPage(
                      icon: CupertinoIcons.checkmark_shield,
                      title: AppLocalizations.of(context)!.tr('Almost done') ?? AppLocalizations.of(context)!.tr('Almost done'),
                      subtitle: AppLocalizations.of(context)!.tr('Review & accept the terms') ?? AppLocalizations.of(context)!.tr('Review & accept the terms'),
                      isLight: isLight,
                      isDesktop: isDesktop,
                      children: [
                        // Summary card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: fg.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(TradeRepublicTheme.radiusMedium),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SummaryRow(icon: CupertinoIcons.at,        label: AppLocalizations.of(context)!.tr('Username') ?? AppLocalizations.of(context)!.tr('Username'), value: _usernameCtrl.text.trim(), fg: fg),
                              const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.person,    label: AppLocalizations.of(context)!.tr('Name') ?? AppLocalizations.of(context)!.tr('Name'), value: '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim(), fg: fg),
                                const SizedBox(height: 10),
                              _SummaryRow(icon: CupertinoIcons.mail,      label: AppLocalizations.of(context)!.tr('Email') ?? AppLocalizations.of(context)!.tr('Email'),    value: _emailCtrl.text.trim(), fg: fg),
                              const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.calendar,  label: AppLocalizations.of(context)!.tr('Birthdate') ?? AppLocalizations.of(context)!.tr('Birthdate'), value: _birthdateCtrl.text.trim(), fg: fg),
                                const SizedBox(height: 10),
                              _SummaryRow(icon: CupertinoIcons.briefcase, label: AppLocalizations.of(context)!.tr('Company') ?? AppLocalizations.of(context)!.tr('Company'),  value: _companyCtrl.text.trim(), fg: fg),
                              const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.doc_plaintext, label: AppLocalizations.of(context)!.tr('Description') ?? AppLocalizations.of(context)!.tr('Description'), value: _businessDescriptionCtrl.text.trim(), fg: fg),
                                const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.location_solid, label: AppLocalizations.of(context)!.tr('Address') ?? AppLocalizations.of(context)!.tr('Address'), value: _buildBusinessAddress(), fg: fg),
                                const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.globe, label: AppLocalizations.of(context)!.tr('Business Country') ?? AppLocalizations.of(context)!.tr('Business Country'), value: _businessCountry, fg: fg),
                                const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.person_2, label: AppLocalizations.of(context)!.tr('Business Size') ?? AppLocalizations.of(context)!.tr('Business Size'), value: _businessSize, fg: fg),
                                const SizedBox(height: 10),
                              _SummaryRow(icon: CupertinoIcons.phone,     label: AppLocalizations.of(context)!.tr('Phone') ?? AppLocalizations.of(context)!.tr('Phone'),
                                  value: _fullPhoneWithCountry(), fg: fg),
                              if (_websiteCtrl.text.trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _SummaryRow(icon: CupertinoIcons.globe, label: AppLocalizations.of(context)!.tr('Website') ?? AppLocalizations.of(context)!.tr('Website'), value: _websiteCtrl.text.trim(), fg: fg),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                        // Terms checkbox
                        TradeRepublicTap(
                          onTap: () => setState(() => _acceptTerms = !_acceptTerms),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 24, height: 24,
                                decoration: BoxDecoration(
                                  color: _acceptTerms ? fg : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _acceptTerms ? fg : fg.withOpacity(0.25),
                                    width: 1.5,
                                  ),
                                ),
                                child: _acceptTerms
                                    ? Icon(CupertinoIcons.checkmark, size: 14,
                                        color: isLight ? Colors.white : Colors.black)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(fontSize: 13,
                                        color: fg.withOpacity(0.55), height: 1.5),
                                    children: [
                                      const TextSpan(text: 'I accept the '),
                                      TextSpan(
                                        text: 'Terms & Conditions',
                                        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () => launchUrl(
                                            Uri.parse('https://cultioo.com/us/us_legal_app#business_terms'),
                                            mode: LaunchMode.inAppBrowserView,
                                          ),
                                      ),
                                      const TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Privacy Policy',
                                        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () => launchUrl(
                                            Uri.parse('https://cultioo.com/us/us_legal_app#business_privacy'),
                                            mode: LaunchMode.inAppBrowserView,
                                          ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── Page 4: Email Verification ────────────────────────
                    _StepPage(
                      icon: CupertinoIcons.envelope_badge,
                      title: AppLocalizations.of(context)!.tr('Verify your email') ?? AppLocalizations.of(context)!.tr('Verify your email'),
                      subtitle:
                          '${AppLocalizations.of(context)!.tr('We sent an 8-digit code to')} $_pendingEmail',
                      isLight: isLight,
                      isDesktop: isDesktop,
                      children: [
                        // Hidden text field to capture keyboard input
                        SizedBox(
                          height: 0,
                          child: TradeRepublicTextField(
                            controller: _codeCtrl,
                            focusNode: _codeFocus,
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            counterText: '',
                            filled: false,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(color: Colors.transparent),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _verifyCode(),
                          ),
                        ),
                        // Visual OTP boxes
                        TradeRepublicTap(
                          onTap: () => _codeFocus.requestFocus(),
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _codeCtrl,
                            builder: (_, val, __) {
                              final code = val.text.padRight(8);
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(8, (i) {
                                  // Small gap after digit 4
                                  return Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (i == 4) const SizedBox(width: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: _CodeBox(
                                        char: i < val.text.length ? code[i] : '',
                                        isLight: isLight,
                                        isFocused: i == val.text.length && _codeFocus.hasFocus,
                                      ),
                                    ),
                                  ]);
                                }),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Resend row
                        Center(
                          child: TradeRepublicTap(
                            onTap: _resending ? null : _resendCode,
                            child: _resending
                                ? SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5, color: fg.withOpacity(0.4)))
                                : Text(AppLocalizations.of(context)!.tr("Didn't receive a code? Resend"),
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: fg.withOpacity(0.55),
                                        decoration: TextDecoration.underline)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Bottom button
              Padding(
                padding: EdgeInsets.fromLTRB(
                    isDesktop ? 32 : 24, 12, isDesktop ? 32 : 24, isDesktop ? 32 : 28),
                child: TradeRepublicButton(
                  width: double.infinity,
                  height: isDesktop ? 52 : 56,
                  label: _currentPage == 2
                      ? 'Create Seller Account'
                      : _currentPage == 3
                          ? 'Verify & Continue'
                          : 'Continue',
                  isLoading: _isLoading || _verifying,
                  onPressed: (_isLoading || _verifying)
                      ? null
                      : _currentPage == 2
                          ? _submit
                          : _currentPage == 3
                              ? _verifyCode
                              : _next,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameStatus(Color fg) {
    if (_checkingUsername) {
      return SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: fg.withOpacity(0.4)));
    }
    if (_usernameAvailable == true) {
      return Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: const Color(0xFF19AF00));
    }
    if (_usernameAvailable == false) {
      return Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: const Color(0xFFC80000));
    }
    return const SizedBox.shrink();
  }

  Widget _buildEmailStatus(Color fg) {
    if (_checkingEmail) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: fg.withOpacity(0.4),
        ),
      );
    }
    if (_emailAvailable == true) {
      return Icon(
        CupertinoIcons.checkmark_circle_fill,
        size: 18,
        color: const Color(0xFF19AF00),
      );
    }
    if (_emailAvailable == false) {
      return Icon(
        CupertinoIcons.xmark_circle_fill,
        size: 18,
        color: const Color(0xFFC80000),
      );
    }
    return const SizedBox.shrink();
  }
}
