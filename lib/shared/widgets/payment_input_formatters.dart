import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Adds spaces every 4 characters, uppercases and limits the input to a valid
/// IBAN length. When the input matches a known German/Austrian/Swiss bank
/// code, [onBankDetected] is invoked synchronously. For everything else the
/// formatter falls back to a debounced async lookup against
/// [openiban.com](https://openiban.com), which returns both the bank name
/// and BIC for almost every European IBAN.
class IbanInputFormatter extends TextInputFormatter {
  final Function(String)? onBankDetected;
  final Function(String)? onBicDetected;

  IbanInputFormatter({this.onBankDetected, this.onBicDetected});

  // ── OpenIBAN async lookup (cache + debounce) ──────────────────────────────
  static final Map<String, Map<String, String>> _ibanCache = {};
  static String _lastLookupIban = '';
  static Timer? _lookupDebounce;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();

    if (newText.length > 34) {
      newText = newText.substring(0, 34);
    }

    if (newText.length >= 8 && onBankDetected != null) {
      final bankName = _detectBankFromIban(newText);
      if (bankName.isNotEmpty) {
        onBankDetected!(bankName);
      } else if (newText.length >= 15) {
        _scheduleOpenIbanLookup(newText);
      }
    }

    final buf = StringBuffer();
    for (var i = 0; i < newText.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(newText[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _detectBankFromIban(String iban) {
    if (iban.length < 8) return '';
    if (iban.startsWith('DE')) return _getBankFromBLZ(iban.substring(4, 12));
    if (iban.startsWith('AT')) {
      return _getBankFromAustrianCode(iban.substring(4, 9));
    }
    if (iban.startsWith('CH')) {
      return _getBankFromSwissCode(iban.substring(4, 9));
    }
    return '';
  }

  String _getBankFromBLZ(String blz) {
    const bankMap = {
      '10020030': 'HSBC Trinkaus',
      '10040000': 'Commerzbank',
      '10050000': 'Landesbank Berlin',
      '10070024': 'German Bank',
      '10080000': 'Commerzbank',
      '12030000': 'Commerzbank',
      '12040000': 'Commerzbank',
      '13040200': 'Commerzbank',
      '20040000': 'Commerzbank',
      '20070000': 'German Bank',
      '20080000': 'Commerzbank',
      '25040066': 'Commerzbank',
      '26580070': 'Peoples Bank',
      '30040000': 'Commerzbank',
      '30050110': 'Duesseldorf City Savings Bank',
      '30070010': 'German Bank',
      '30080000': 'Commerzbank',
      '37040044': 'Commerzbank',
      '40040028': 'Commerzbank',
      '50040000': 'Commerzbank',
      '50070010': 'Deutsche Bank',
      '50080000': 'Commerzbank',
      '60040071': 'Commerzbank',
      '70040041': 'Commerzbank',
      '70070010': 'German Bank',
      '70080000': 'Commerzbank',
      '76026000': 'HypoVereinsbank',
      '79040047': 'Commerzbank',
      '43060967': 'GLS Bank',
    };

    if (bankMap.containsKey(blz)) return bankMap[blz]!;

    if (blz.startsWith('700700') ||
        blz.startsWith('200700') ||
        blz.startsWith('100700')) {
      return 'Deutsche Bank';
    }
    if (blz.startsWith('760200') || blz.startsWith('700202')) {
      return 'HypoVereinsbank';
    }
    if (blz.startsWith('430609')) return 'GLS Bank';
    return '';
  }

  String _getBankFromAustrianCode(String code) {
    const map = {
      '20111': 'Erste Bank',
      '12000': 'Bank Austria',
      '32000': 'Raiffeisen Bank',
      '14000': 'BAWAG P.S.K.',
    };
    return map[code] ?? '';
  }

  String _getBankFromSwissCode(String code) {
    const map = {
      '00235': 'Credit Suisse',
      '00254': 'UBS',
      '00700': 'PostFinance',
      '08390': 'Raiffeisen',
    };
    return map[code] ?? '';
  }

  void _scheduleOpenIbanLookup(String iban) {
    if (iban == _lastLookupIban) return;

    final cached = _ibanCache[iban];
    if (cached != null) {
      final name = cached['name'] ?? '';
      final bic = cached['bic'] ?? '';
      if (name.isNotEmpty) onBankDetected?.call(name);
      if (bic.isNotEmpty) onBicDetected?.call(bic);
      return;
    }

    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 450), () async {
      _lastLookupIban = iban;
      try {
        final uri = Uri.parse(
          'https://openiban.com/validate/$iban?getBIC=true&validateBankCode=true',
        );
        final res = await http
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) return;

        final data = json.decode(res.body) as Map<String, dynamic>;
        final bankData = data['bankData'];
        if (bankData is! Map) return;

        final name = (bankData['name'] ?? '').toString().trim();
        final bic = (bankData['bic'] ?? '').toString().trim();

        _ibanCache[iban] = {'name': name, 'bic': bic};

        if (name.isNotEmpty) onBankDetected?.call(name);
        if (bic.isNotEmpty) onBicDetected?.call(bic);
      } catch (_) {
        // Network or parse error → silently ignore.
      }
    });
  }
}

/// BIC: 8-11 alphanumeric characters, always uppercase.
class BicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    if (newText.length > 11) newText = newText.substring(0, 11);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

/// US ABA routing number: exactly 9 digits.
class RoutingNumberInputFormatter extends TextInputFormatter {
  final Function(String)? onBankDetected;

  RoutingNumberInputFormatter({this.onBankDetected});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (newText.length > 9) newText = newText.substring(0, 9);

    if (newText.length == 9 && onBankDetected != null) {
      Future.microtask(() => onBankDetected!(newText));
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

/// Credit card number: digits only, auto-adds a space every 4 digits,
/// max 16 digits (19 chars with spaces).
class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all non-digit characters
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 16) digits = digits.substring(0, 16);

    // Add space every 4 digits
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Card expiry date: auto-adds "/" after 2 digits, max 5 chars (MM/YY).
class CardExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all non-digit characters
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);

    // Build formatted string: MM/YY
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2) buf.write('/');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Card CVC: digits only, max 4 digits (Amex uses 4 digits).
class CardCvcInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
