import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/trade_republic_tap.dart';


// USDOT Number Formatter: 8 digits only
class USDOTFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Limit to 8 digits
    final limited = text.length > 8 ? text.substring(0, 8) : text;

    return TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length),
    );
  }
}

// MC Number Formatter: 6-7 digits only
class MCNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Limit to 7 digits
    final limited = text.length > 7 ? text.substring(0, 7) : text;

    return TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length),
    );
  }
}

// US Phone Formatter: (XXX) XXX-XXXX format
class USPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Limit to 10 digits
    final limited = text.length > 10 ? text.substring(0, 10) : text;

    String formatted = '';
    if (limited.isNotEmpty) {
      // Add area code with parentheses
      if (limited.length <= 3) {
        formatted = '($limited';
      } else if (limited.length <= 6) {
        formatted = '(${limited.substring(0, 3)}) ${limited.substring(3)}';
      } else {
        formatted =
            '(${limited.substring(0, 3)}) ${limited.substring(3, 6)}-${limited.substring(6)}';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// German Phone Formatter: XXXX XXXXXXX format
class GermanPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Limit to 11 digits (typical German number)
    final limited = text.length > 11 ? text.substring(0, 11) : text;

    String formatted = '';
    if (limited.isNotEmpty) {
      // Format as XXXX XXXXXXX
      if (limited.length <= 4) {
        formatted = limited;
      } else {
        formatted = '${limited.substring(0, 4)} ${limited.substring(4)}';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DriverStep8Company extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const DriverStep8Company({
    super.key,
    required this.initialData,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<DriverStep8Company> createState() => _DriverStep8CompanyState();
}

class _DriverStep8CompanyState extends State<DriverStep8Company> {
  // Form key for validation
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Check if selected country from Step 1 is USA
  bool get _isUSCountry {
    final country = widget.initialData['country']?.toString() ?? '';
    return country == 'United States' || country == 'USA';
  }

  // Get personal country from Step 1
  String get _personalCountry {
    return widget.initialData['country']?.toString() ??
        (AppLocalizations.of(context)?.unitedStates ?? '');
  }

  // Controllers for company information
  final TextEditingController _usdotController = TextEditingController();
  final TextEditingController _mcNumberController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _dbaNameController = TextEditingController();
  final TextEditingController _companyStreetController =
      TextEditingController();
  final TextEditingController _companyStreetNumberController =
      TextEditingController();
  final TextEditingController _companyCityController = TextEditingController();
  final TextEditingController _companyZipController = TextEditingController();
  final TextEditingController _companyEmailController = TextEditingController();
  final TextEditingController _companyPhoneController = TextEditingController();

  // Single Driver mode (no company)
  bool _isSingleDriver = false;

  // Legal structure dropdown
  String _selectedLegalStructure = 'LLC';

  // US Legal structure options
  List<String> get _usLegalStructures => [
    'LLC',
    AppLocalizations.of(context)?.corporation ?? 'Corporation',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.partnershipLabel ?? 'Partnership',
    'S Corporation',
    'C Corporation',
  ];

  // German Legal structure options
  List<String> get _germanLegalStructures => [
    'GmbH (Limited Liability)',
    'UG (Mini GmbH)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    'GbR (Civil Partnership)',
    'OHG (General Partnership)',
    'KG (Limited Partnership)',
    'AG (Corporation)',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Austrian Legal structure options
  List<String> get _austrianLegalStructures => [
    'GmbH (Limited Liability)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    'OG (General Partnership)',
    'KG (Limited Partnership)',
    'AG (Corporation)',
    'GesbR (Civil Partnership)',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Swiss Legal structure options
  List<String> get _swissLegalStructures => [
    'GmbH (Limited Liability)',
    'AG (Corporation)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.generalPartnership ?? 'General Partnership',
    AppLocalizations.of(context)?.limitedPartnership ?? 'Limited Partnership',
    AppLocalizations.of(context)?.cooperative ?? 'Cooperative',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // French Legal structure options
  List<String> get _frenchLegalStructures => [
    'SARL (Limited Liability)',
    'SAS (Simplified Corp)',
    'SA (Corporation)',
    'EURL (Single-Member LLC)',
    'Auto-entrepreneur',
    'SCI (Property Company)',
    'SNC (General Partnership)',
  ];

  // Italian Legal structure options
  List<String> get _italianLegalStructures => [
    'S.r.l. (Limited Liability)',
    'S.p.A. (Corporation)',
    'S.a.s. (Limited Partnership)',
    'S.n.c. (General Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Spanish Legal structure options
  List<String> get _spanishLegalStructures => [
    'S.L. (Limited Liability)',
    'S.A. (Corporation)',
    'Self-Employed',
    'S.L.U. (Single-Member LLC)',
    AppLocalizations.of(context)?.cooperative ?? 'Cooperative',
    AppLocalizations.of(context)?.civilPartnership ?? 'Civil Partnership',
  ];

  // Dutch Legal structure options
  List<String> get _dutchLegalStructures => [
    'B.V. (Limited Liability)',
    'N.V. (Corporation)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    'V.O.F. (General Partnership)',
    'C.V. (Limited Partnership)',
    AppLocalizations.of(context)?.professionalPartnership ?? 'Professional Partnership',
    'ZZP (Freelancer)',
  ];

  // Polish Legal structure options
  List<String> get _polishLegalStructures => [
    'Sp. z o.o. (Limited Liability)',
    'S.A. (Corporation)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.generalPartnership ?? 'General Partnership',
    AppLocalizations.of(context)?.limitedPartnership ?? 'Limited Partnership',
    AppLocalizations.of(context)?.professionalPartnership ?? 'Professional Partnership',
  ];

  // UK Legal structure options
  List<String> get _ukLegalStructures => [
    'Ltd',
    'PLC',
    AppLocalizations.of(context)?.soleTrader ?? 'Sole Trader',
    AppLocalizations.of(context)?.partnershipLabel ?? 'Partnership',
    'LLP',
  ];

  // Belgian Legal structure options
  List<String> get _belgianLegalStructures => [
    'BV/SPRL (Limited Liability)',
    'NV/SA (Corporation)',
    'VOF/SNC (General Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.cooperative ?? 'Cooperative',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Czech Legal structure options
  List<String> get _czechLegalStructures => [
    's.r.o. (Limited Liability)',
    'a.s. (Corporation)',
    'k.s. (Limited Partnership)',
    'v.o.s. (General Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
  ];

  // Danish Legal structure options
  List<String> get _danishLegalStructures => [
    'ApS (Limited Liability)',
    'A/S (Corporation)',
    'I/S (General Partnership)',
    'K/S (Limited Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
  ];

  // Finnish Legal structure options
  List<String> get _finnishLegalStructures => [
    'Oy (Ltd)',
    'Oyj (PLC)',
    'Ky (Limited Partnership)',
    'Ay (General Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Greek Legal structure options
  List<String> get _greekLegalStructures => [
    'IKE (Limited Liability)',
    'AE (Corporation)',
    'OE (General Partnership)',
    'EE (Limited Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Hungarian Legal structure options
  List<String> get _hungarianLegalStructures => [
    'Kft. (Limited Liability)',
    'Zrt. / Rt. (Corporation)',
    'Bt. (Limited Partnership)',
    'Kkt. (General Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
  ];

  // Irish Legal structure options
  List<String> get _irishLegalStructures => [
    'Ltd',
    'PLC',
    'LLP',
    AppLocalizations.of(context)?.soleTrader ?? 'Sole Trader',
    AppLocalizations.of(context)?.partnershipLabel ?? 'Partnership',
  ];

  // Portuguese Legal structure options
  List<String> get _portugueseLegalStructures => [
    'Lda. (Limited Liability)',
    'S.A. (Corporation)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    'SNC (General Partnership)',
    AppLocalizations.of(context)?.cooperative ?? 'Cooperative',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Romanian Legal structure options
  List<String> get _romanianLegalStructures => [
    'SRL (Limited Liability)',
    'SA (Corporation)',
    'PFA (Sole / Freelancer)',
    'II (Individual Enterprise)',
    AppLocalizations.of(context)?.cooperative ?? 'Cooperative',
  ];

  // Swedish Legal structure options
  List<String> get _swedishLegalStructures => [
    'AB (Aktiebolag / Corporation)',
    'HB (General Partnership)',
    'KB (Limited Partnership)',
    'EF (Economic Association)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
  ];

  // Canadian Legal structure options
  List<String> get _canadianLegalStructures => [
    'Inc. (Incorporated)',
    'Ltd. (Limited)',
    'Corp. (Corporation)',
    'LP (Limited Partnership)',
    'GP (General Partnership)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
  ];

  // Mexican Legal structure options
  List<String> get _mexicanLegalStructures => [
    'S.A. de C.V. (Corporation)',
    'S. de R.L. de C.V. (LLC)',
    'S.A.S. (Simplified Corp.)',
    'S.C. (Civil Society)',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
  ];

  // Generic EU Legal structure options (smaller EU countries)
  List<String> get _euGenericLegalStructures => [
    'Ltd. (Limited Liability)',
    'Corporation / SA',
    AppLocalizations.of(context)?.soleProprietorship ?? 'Sole Proprietorship',
    AppLocalizations.of(context)?.partnershipLabel ?? 'Partnership',
    AppLocalizations.of(context)?.cooperative ?? 'Cooperative',
    AppLocalizations.of(context)?.freelancer ?? 'Freelancer',
  ];

  // Get legal structures based on selected country
  List<String> get _legalStructures {
    switch (_selectedCountry) {
      case 'United States':     return _usLegalStructures;
      case 'Canada':            return _canadianLegalStructures;
      case 'Mexico':            return _mexicanLegalStructures;
      case 'United Kingdom':    return _ukLegalStructures;
      case 'Germany':           return _germanLegalStructures;
      case 'Austria':           return _austrianLegalStructures;
      case 'Switzerland':       return _swissLegalStructures;
      case 'Belgium':           return _belgianLegalStructures;
      case 'Czech Republic':    return _czechLegalStructures;
      case 'Denmark':           return _danishLegalStructures;
      case 'Finland':           return _finnishLegalStructures;
      case 'France':            return _frenchLegalStructures;
      case 'Greece':            return _greekLegalStructures;
      case 'Hungary':           return _hungarianLegalStructures;
      case 'Ireland':           return _irishLegalStructures;
      case 'Italy':             return _italianLegalStructures;
      case 'Netherlands':       return _dutchLegalStructures;
      case 'Poland':            return _polishLegalStructures;
      case 'Portugal':          return _portugueseLegalStructures;
      case 'Romania':           return _romanianLegalStructures;
      case 'Spain':             return _spanishLegalStructures;
      case 'Sweden':            return _swedishLegalStructures;
      default:                  return _euGenericLegalStructures;
    }
  }

  // Get default legal structure for country
  String _getDefaultLegalStructure(String country) {
    switch (country) {
      case 'United States':   return 'LLC';
      case 'Canada':          return 'Inc. (Incorporated)';
      case 'Mexico':          return 'S.A. de C.V. (Corporation)';
      case 'United Kingdom':  return 'Ltd';
      case 'Germany':         return 'GmbH (Limited Liability)';
      case 'Austria':         return 'GmbH (Limited Liability)';
      case 'Switzerland':     return 'GmbH (Limited Liability)';
      case 'Belgium':         return 'BV/SPRL (Limited Liability)';
      case 'Czech Republic':  return 's.r.o. (Limited Liability)';
      case 'Denmark':         return 'ApS (Limited Liability)';
      case 'Finland':         return 'Oy (Ltd)';
      case 'France':          return 'SARL (Limited Liability)';
      case 'Greece':          return 'IKE (Limited Liability)';
      case 'Hungary':         return 'Kft. (Limited Liability)';
      case 'Ireland':         return 'Ltd';
      case 'Italy':           return 'S.r.l. (Limited Liability)';
      case 'Netherlands':     return 'B.V. (Limited Liability)';
      case 'Poland':          return 'Sp. z o.o. (Limited Liability)';
      case 'Portugal':        return 'Lda. (Limited Liability)';
      case 'Romania':         return 'SRL (Limited Liability)';
      case 'Spain':           return 'S.L. (Limited Liability)';
      case 'Sweden':          return 'AB (Aktiebolag / Corporation)';
      default:                return 'Ltd. (Limited Liability)';
    }
  }

  // Country selection
  String _selectedCountry = 'United States';

  // Country options with emoji flags — North America + all EU
  final List<Map<String, String>> _countries = [
    // North America
    {'name': 'United States', 'emoji': '🇺🇸'},
    {'name': 'Canada', 'emoji': '🇨🇦'},
    {'name': 'Mexico', 'emoji': '🇲🇽'},
    // UK & Switzerland
    {'name': 'United Kingdom', 'emoji': '🇬🇧'},
    {'name': 'Switzerland', 'emoji': '🇨🇭'},
    // EU Countries (alphabetical)
    {'name': 'Austria', 'emoji': '🇦🇹'},
    {'name': 'Belgium', 'emoji': '🇧🇪'},
    {'name': 'Bulgaria', 'emoji': '🇧🇬'},
    {'name': 'Croatia', 'emoji': '🇭🇷'},
    {'name': 'Cyprus', 'emoji': '🇨🇾'},
    {'name': 'Czech Republic', 'emoji': '🇨🇿'},
    {'name': 'Denmark', 'emoji': '🇩🇰'},
    {'name': 'Estonia', 'emoji': '🇪🇪'},
    {'name': 'Finland', 'emoji': '🇫🇮'},
    {'name': 'France', 'emoji': '🇫🇷'},
    {'name': 'Germany', 'emoji': '🇩🇪'},
    {'name': 'Greece', 'emoji': '🇬🇷'},
    {'name': 'Hungary', 'emoji': '🇭🇺'},
    {'name': 'Ireland', 'emoji': '🇮🇪'},
    {'name': 'Italy', 'emoji': '🇮🇹'},
    {'name': 'Latvia', 'emoji': '🇱🇻'},
    {'name': 'Lithuania', 'emoji': '🇱🇹'},
    {'name': 'Luxembourg', 'emoji': '🇱🇺'},
    {'name': 'Malta', 'emoji': '🇲🇹'},
    {'name': 'Netherlands', 'emoji': '🇳🇱'},
    {'name': 'Poland', 'emoji': '🇵🇱'},
    {'name': 'Portugal', 'emoji': '🇵🇹'},
    {'name': 'Romania', 'emoji': '🇷🇴'},
    {'name': 'Slovakia', 'emoji': '🇸🇰'},
    {'name': 'Slovenia', 'emoji': '🇸🇮'},
    {'name': 'Spain', 'emoji': '🇪🇸'},
    {'name': 'Sweden', 'emoji': '🇸🇪'},
  ];

  // State selection
  String _selectedState = 'California';

  // US States
  final List<String> _usStates = [
    'Alabama',
    'Alaska',
    'Arizona',
    'Arkansas',
    'California',
    'Colorado',
    'Connecticut',
    'Delaware',
    'Florida',
    'Georgia',
    'Hawaii',
    'Idaho',
    'Illinois',
    'Indiana',
    'Iowa',
    'Kansas',
    'Kentucky',
    'Louisiana',
    'Maine',
    'Maryland',
    'Massachusetts',
    'Michigan',
    'Minnesota',
    'Mississippi',
    'Missouri',
    'Montana',
    'Nebraska',
    'Nevada',
    'New Hampshire',
    'New Jersey',
    'New Mexico',
    'New York',
    'North Carolina',
    'North Dakota',
    'Ohio',
    'Oklahoma',
    'Oregon',
    'Pennsylvania',
    'Rhode Island',
    'South Carolina',
    'South Dakota',
    'Tennessee',
    'Texas',
    'Utah',
    'Vermont',
    'Virginia',
    'Washington',
    'West Virginia',
    'Wisconsin',
    'Wyoming',
  ];

  // German States (Bundesländer)
  final List<String> _germanStates = [
    'Baden-Württemberg',
    'Bayern',
    'Berlin',
    'Brandenburg',
    'Bremen',
    'Hamburg',
    'Hessen',
    'Mecklenburg-Vorpommern',
    'Niedersachsen',
    'Nordrhein-Westfalen',
    'Rheinland-Pfalz',
    'Saarland',
    'Sachsen',
    'Sachsen-Anhalt',
    'Schleswig-Holstein',
    'Thüringen',
  ];

  // Austrian States (Bundesländer)
  final List<String> _austrianStates = [
    'Wien',
    'Niederösterreich',
    'Oberösterreich',
    'Salzburg',
    'Tirol',
    'Vorarlberg',
    'Kärnten',
    'Steiermark',
    'Burgenland',
  ];

  // Swiss Cantons
  final List<String> _swissCantons = [
    'Zürich',
    'Bern',
    'Luzern',
    'Uri',
    'Schwyz',
    'Obwalden',
    'Nidwalden',
    'Glarus',
    'Zug',
    'Freiburg',
    'Solothurn',
    'Basel-Stadt',
    'Basel-Landschaft',
    'Schaffhausen',
    'Appenzell Ausserrhoden',
    'Appenzell Innerrhoden',
    'St. Gallen',
    'Graubünden',
    'Aargau',
    'Thurgau',
    'Tessin',
    'Waadt',
    'Wallis',
    'Neuenburg',
    'Genf',
    'Jura',
  ];

  // French Regions
  final List<String> _frenchRegions = [
    'Île-de-France',
    'Auvergne-Rhône-Alpes',
    'Nouvelle-Aquitaine',
    'Occitanie',
    'Hauts-de-France',
    'Provence-Alpes-Côte d\'Azur',
    'Grand Est',
    'Pays de la Loire',
    'Bretagne',
    'Normandie',
    'Bourgogne-Franche-Comté',
    'Centre-Val de Loire',
    'Corse',
  ];

  // Italian Regions
  final List<String> _italianRegions = [
    'Lombardia',
    'Lazio',
    'Campania',
    'Sicilia',
    'Veneto',
    'Emilia-Romagna',
    'Piemonte',
    'Puglia',
    'Toscana',
    'Calabria',
    'Sardegna',
    'Liguria',
    'Marche',
    'Abruzzo',
    'Friuli-Venezia Giulia',
    'Trentino-Alto Adige',
    'Umbria',
    'Basilicata',
    'Molise',
    'Valle d\'Aosta',
  ];

  // Spanish Autonomous Communities
  final List<String> _spanishRegions = [
    'Andalucía',
    'Cataluña',
    'Comunidad de Madrid',
    'Comunidad Valenciana',
    'Galicia',
    'Castilla y León',
    'País Vasco',
    'Castilla-La Mancha',
    'Canarias',
    'Región de Murcia',
    'Aragón',
    'Islas Baleares',
    'Extremadura',
    'Asturias',
    'Navarra',
    'Cantabria',
    'La Rioja',
    'Ceuta',
    'Melilla',
  ];

  // Dutch Provinces
  final List<String> _dutchProvinces = [
    'Noord-Holland',
    'Zuid-Holland',
    'Noord-Brabant',
    'Gelderland',
    'Utrecht',
    'Limburg',
    'Overijssel',
    'Flevoland',
    'Groningen',
    'Friesland',
    'Drenthe',
    'Zeeland',
  ];

  // Polish Voivodeships
  final List<String> _polishVoivodeships = [
    'Mazowieckie',
    'Śląskie',
    'Wielkopolskie',
    'Małopolskie',
    'Dolnośląskie',
    'Łódzkie',
    'Pomorskie',
    'Lubelskie',
    'Podkarpackie',
    'Kujawsko-Pomorskie',
    'Zachodniopomorskie',
    'Warmińsko-Mazurskie',
    'Świętokrzyskie',
    'Podlaskie',
    'Lubuskie',
    'Opolskie',
  ];

  // UK Countries/Regions
  final List<String> _ukRegions = ['England', 'Scotland', 'Wales', 'Northern Ireland'];

  // Canada Provinces
  final List<String> _canadaProvinces = [
    'Alberta', 'British Columbia', 'Manitoba', 'New Brunswick',
    'Newfoundland and Labrador', 'Nova Scotia', 'Ontario',
    'Prince Edward Island', 'Quebec', 'Saskatchewan',
    'Northwest Territories', 'Nunavut', 'Yukon',
  ];

  // Mexico States
  final List<String> _mexicoStates = [
    'Aguascalientes', 'Baja California', 'Baja California Sur', 'Campeche',
    'Chiapas', 'Chihuahua', 'Ciudad de México', 'Coahuila', 'Colima',
    'Durango', 'Guanajuato', 'Guerrero', 'Hidalgo', 'Jalisco', 'México',
    'Michoacán', 'Morelos', 'Nayarit', 'Nuevo León', 'Oaxaca', 'Puebla',
    'Querétaro', 'Quintana Roo', 'San Luis Potosí', 'Sinaloa', 'Sonora',
    'Tabasco', 'Tamaulipas', 'Tlaxcala', 'Veracruz', 'Yucatán', 'Zacatecas',
  ];

  // Belgium Regions
  final List<String> _belgianRegions = [
    'Brussels Capital Region', 'Flemish Region', 'Walloon Region',
  ];

  // Bulgaria Regions
  final List<String> _bulgariaRegions = [
    'Sofia', 'Plovdiv', 'Varna', 'Burgas', 'Ruse', 'Stara Zagora',
    'Pleven', 'Sliven', 'Dobrich', 'Shumen', 'Montana', 'Vidin',
    'Lovech', 'Gabrovo', 'Blagoevgrad', 'Pazardzhik', 'Pernik',
    'Haskovo', 'Yambol', 'Smolyan', 'Kyustendil', 'Targovishte',
    'Razgrad', 'Silistra', 'Kardzhali', 'Vratsa', 'Veliko Tarnovo',
  ];

  // Croatia Counties
  final List<String> _croatiaCounties = [
    'Zagreb', 'Split-Dalmatia', 'Rijeka (Primorje-Gorski Kotar)',
    'Osijek-Baranja', 'Zadar', 'Istria', 'Sisak-Moslavina',
    'Karlovac', 'Varaždin', 'Koprivnica-Križevci', 'Krapina-Zagorje',
    'Bjelovar-Bilogora', 'Virovitica-Podravina', 'Požega-Slavonia',
    'Vukovar-Syrmia', 'Šibenik-Knin', 'Lika-Senj',
    'Dubrovnik-Neretva', 'Međimurje',
  ];

  // Cyprus Districts
  final List<String> _cyprusDistricts = [
    'Nicosia', 'Limassol', 'Larnaca', 'Famagusta', 'Paphos', 'Kyrenia',
  ];

  // Czech Regions
  final List<String> _czechRegions = [
    'Prague', 'Central Bohemian', 'South Bohemian', 'Plzeň',
    'Karlovy Vary', 'Ústí nad Labem', 'Liberec', 'Hradec Králové',
    'Pardubice', 'Olomouc', 'Moravian-Silesian', 'South Moravian',
    'Vysočina', 'Zlín',
  ];

  // Denmark Regions
  final List<String> _denmarkRegions = [
    'Capital Region of Denmark', 'Central Denmark Region',
    'North Denmark Region', 'Region Zealand',
    'Region of Southern Denmark',
  ];

  // Estonia Counties
  final List<String> _estoniaCounties = [
    'Harju', 'Tartu', 'Ida-Viru', 'Pärnu', 'Lääne-Viru',
    'Viljandi', 'Rapla', 'Võru', 'Saare', 'Jõgeva',
    'Järva', 'Valga', 'Põlva', 'Lääne', 'Hiiu',
  ];

  // Finland Regions
  final List<String> _finlandRegions = [
    'Uusimaa', 'Southwest Finland', 'Satakunta', 'Kanta-Häme',
    'Pirkanmaa', 'Päijät-Häme', 'Kymenlaakso', 'South Karelia',
    'Etelä-Savo', 'Pohjois-Savo', 'North Karelia', 'Central Finland',
    'South Ostrobothnia', 'Ostrobothnia', 'Central Ostrobothnia',
    'North Ostrobothnia', 'Kainuu', 'Lapland', 'Åland',
  ];

  // Greece Regions
  final List<String> _greeceRegions = [
    'Attica', 'Central Greece', 'Central Macedonia', 'Crete',
    'Eastern Macedonia and Thrace', 'Epirus', 'Ionian Islands',
    'North Aegean', 'Peloponnese', 'South Aegean', 'Thessaly',
    'Western Greece', 'Western Macedonia',
  ];

  // Hungary Counties
  final List<String> _hungarianCounties = [
    'Budapest', 'Baranya', 'Bács-Kiskun', 'Békés',
    'Borsod-Abaúj-Zemplén', 'Csongrád-Csanád', 'Fejér',
    'Győr-Moson-Sopron', 'Hajdú-Bihar', 'Heves',
    'Jász-Nagykun-Szolnok', 'Komárom-Esztergom', 'Nógrád',
    'Pest', 'Somogy', 'Szabolcs-Szatmár-Bereg', 'Tolna',
    'Vas', 'Veszprém', 'Zala',
  ];

  // Ireland Provinces
  final List<String> _irelandProvinces = [
    'Connacht', 'Leinster', 'Munster', 'Ulster (IE)',
  ];

  // Latvia Regions
  final List<String> _latviaRegions = [
    'Riga', 'Vidzeme', 'Kurzeme', 'Zemgale', 'Latgale',
  ];

  // Lithuania Counties
  final List<String> _lithuaniaCounties = [
    'Vilnius', 'Kaunas', 'Klaipėda', 'Šiauliai', 'Panevėžys',
    'Alytus', 'Marijampolė', 'Mažeikiai', 'Jonava', 'Utena',
  ];

  // Luxembourg Cantons
  final List<String> _luxembourgCantons = [
    'Luxembourg', 'Esch-sur-Alzette', 'Differdange', 'Dudelange',
    'Ettelbruck', 'Diekirch', 'Wiltz', 'Echternach',
    'Remich', 'Grevenmacher', 'Clervaux', 'Vianden',
  ];

  // Malta Regions
  final List<String> _maltaRegions = [
    'Southern Harbour', 'Northern Harbour', 'South Eastern',
    'Western', 'Northern', 'Gozo and Comino',
  ];

  // Portugal Districts
  final List<String> _portugueseDistricts = [
    'Aveiro', 'Beja', 'Braga', 'Bragança', 'Castelo Branco', 'Coimbra',
    'Évora', 'Faro', 'Guarda', 'Leiria', 'Lisboa', 'Portalegre',
    'Porto', 'Santarém', 'Setúbal', 'Viana do Castelo', 'Vila Real',
    'Viseu', 'Açores', 'Madeira',
  ];

  // Romania Counties
  final List<String> _romanianCounties = [
    'Alba', 'Arad', 'Argeș', 'Bacău', 'Bihor', 'Bistrița-Năsăud',
    'Botoșani', 'Brașov', 'Brăila', 'București', 'Buzău',
    'Caraș-Severin', 'Călărași', 'Cluj', 'Constanța', 'Covasna',
    'Dâmbovița', 'Dolj', 'Galați', 'Giurgiu', 'Gorj', 'Harghita',
    'Hunedoara', 'Ialomița', 'Iași', 'Ilfov', 'Maramureș',
    'Mehedinți', 'Mureș', 'Neamț', 'Olt', 'Prahova', 'Satu Mare',
    'Sălaj', 'Sibiu', 'Suceava', 'Teleorman', 'Timiș', 'Tulcea',
    'Vaslui', 'Vâlcea', 'Vrancea',
  ];

  // Slovakia Regions
  final List<String> _slovakiaRegions = [
    'Bratislava', 'Trnava', 'Trenčín', 'Nitra',
    'Žilina', 'Banská Bystrica', 'Prešov', 'Košice',
  ];

  // Slovenia Regions
  final List<String> _sloveniaRegions = [
    'Osrednjeslovenska', 'Podravska', 'Savinjska', 'Gorenjska',
    'Obalno-kraška', 'Jugovzhodna Slovenija', 'Zasavska',
    'Posavska', 'Primorsko-notranjska', 'Goriška',
    'Pomurska', 'Koroška',
  ];

  // Sweden Counties
  final List<String> _swedenCounties = [
    'Stockholm', 'Uppsala', 'Södermanland', 'Östergötland',
    'Jönköping', 'Kronoberg', 'Kalmar', 'Gotland', 'Blekinge',
    'Skåne', 'Halland', 'Västra Götaland', 'Värmland', 'Örebro',
    'Västmanland', 'Dalarna', 'Gävleborg', 'Västernorrland',
    'Jämtland', 'Västerbotten', 'Norrbotten',
  ];

  // Get states/regions based on selected country
  List<String> get _statesList {
    switch (_selectedCountry) {
      case 'United States':   return _usStates;
      case 'Canada':          return _canadaProvinces;
      case 'Mexico':          return _mexicoStates;
      case 'United Kingdom':  return _ukRegions;
      case 'Germany':         return _germanStates;
      case 'Austria':         return _austrianStates;
      case 'Switzerland':     return _swissCantons;
      case 'Belgium':         return _belgianRegions;
      case 'Bulgaria':        return _bulgariaRegions;
      case 'Croatia':         return _croatiaCounties;
      case 'Cyprus':          return _cyprusDistricts;
      case 'Czech Republic':  return _czechRegions;
      case 'Denmark':         return _denmarkRegions;
      case 'Estonia':         return _estoniaCounties;
      case 'Finland':         return _finlandRegions;
      case 'France':          return _frenchRegions;
      case 'Greece':          return _greeceRegions;
      case 'Hungary':         return _hungarianCounties;
      case 'Ireland':         return _irelandProvinces;
      case 'Italy':           return _italianRegions;
      case 'Latvia':          return _latviaRegions;
      case 'Lithuania':       return _lithuaniaCounties;
      case 'Luxembourg':      return _luxembourgCantons;
      case 'Malta':           return _maltaRegions;
      case 'Netherlands':     return _dutchProvinces;
      case 'Poland':          return _polishVoivodeships;
      case 'Portugal':        return _portugueseDistricts;
      case 'Romania':         return _romanianCounties;
      case 'Slovakia':        return _slovakiaRegions;
      case 'Slovenia':        return _sloveniaRegions;
      case 'Spain':           return _spanishRegions;
      case 'Sweden':          return _swedenCounties;
      default:                return _usStates;
    }
  }

  // Get default state for country
  String _getDefaultState(String country) {
    switch (country) {
      case 'United States':   return 'California';
      case 'Canada':          return 'Ontario';
      case 'Mexico':          return 'Ciudad de México';
      case 'United Kingdom':  return 'England';
      case 'Germany':         return 'Bayern';
      case 'Austria':         return 'Wien';
      case 'Switzerland':     return 'Zürich';
      case 'Belgium':         return 'Brussels Capital Region';
      case 'Bulgaria':        return 'Sofia';
      case 'Croatia':         return 'Zagreb';
      case 'Cyprus':          return 'Nicosia';
      case 'Czech Republic':  return 'Prague';
      case 'Denmark':         return 'Capital Region of Denmark';
      case 'Estonia':         return 'Harju';
      case 'Finland':         return 'Uusimaa';
      case 'France':          return 'Île-de-France';
      case 'Greece':          return 'Attica';
      case 'Hungary':         return 'Budapest';
      case 'Ireland':         return 'Leinster';
      case 'Italy':           return 'Lombardia';
      case 'Latvia':          return 'Riga';
      case 'Lithuania':       return 'Vilnius';
      case 'Luxembourg':      return 'Luxembourg';
      case 'Malta':           return 'Northern Harbour';
      case 'Netherlands':     return 'Noord-Holland';
      case 'Poland':          return 'Mazowieckie';
      case 'Portugal':        return 'Lisboa';
      case 'Romania':         return 'București';
      case 'Slovakia':        return 'Bratislava';
      case 'Slovenia':        return 'Osrednjeslovenska';
      case 'Spain':           return 'Comunidad de Madrid';
      case 'Sweden':          return 'Stockholm';
      default:                return 'California';
    }
  }

  // Get state label for country
  String _getStateLabel(String country) {
    switch (country) {
      case 'United States':   return AppLocalizations.of(context)?.stateField ?? 'State';
      case 'Canada':          return 'Province / Territory';
      case 'Mexico':          return AppLocalizations.of(context)?.stateField ?? 'State';
      case 'United Kingdom':  return AppLocalizations.of(context)?.country ?? 'Country';
      case 'Germany':         return AppLocalizations.of(context)?.stateField ?? 'State';
      case 'Austria':         return AppLocalizations.of(context)?.stateField ?? 'State';
      case 'Switzerland':     return 'Canton';
      case 'Belgium':         return 'Region';
      case 'Bulgaria':        return 'Region';
      case 'Croatia':         return 'County';
      case 'Cyprus':          return 'District';
      case 'Czech Republic':  return 'Region';
      case 'Denmark':         return 'Region';
      case 'Estonia':         return 'County';
      case 'Finland':         return 'Region';
      case 'France':          return 'Region';
      case 'Greece':          return 'Region';
      case 'Hungary':         return 'County';
      case 'Ireland':         return 'Province';
      case 'Italy':           return 'Region';
      case 'Latvia':          return 'Region';
      case 'Lithuania':       return 'County';
      case 'Luxembourg':      return 'Canton';
      case 'Malta':           return 'Region';
      case 'Netherlands':     return 'Province';
      case 'Poland':          return 'Province';
      case 'Portugal':        return 'District';
      case 'Romania':         return 'County';
      case 'Slovakia':        return 'Region';
      case 'Slovenia':        return 'Region';
      case 'Spain':           return 'Region';
      case 'Sweden':          return 'County';
      default:                return AppLocalizations.of(context)?.stateField ?? 'State';
    }
  }

  // Phone country code selection
  String _selectedPhoneCountryCode = '+1';

  // Phone country codes with emoji flags
  final List<Map<String, String>> _phoneCountryCodes = [
    // North America
    {'code': '+1',   'country': 'USA / Canada',    'emoji': '🇺🇸'},
    {'code': '+52',  'country': 'Mexico',           'emoji': '🇲🇽'},
    // UK & Switzerland
    {'code': '+44',  'country': 'UK',               'emoji': '🇬🇧'},
    {'code': '+41',  'country': 'Switzerland',      'emoji': '🇨🇭'},
    // EU (alphabetical)
    {'code': '+43',  'country': 'Austria',          'emoji': '🇦🇹'},
    {'code': '+32',  'country': 'Belgium',          'emoji': '🇧🇪'},
    {'code': '+359', 'country': 'Bulgaria',         'emoji': '🇧🇬'},
    {'code': '+385', 'country': 'Croatia',          'emoji': '🇭🇷'},
    {'code': '+357', 'country': 'Cyprus',           'emoji': '🇨🇾'},
    {'code': '+420', 'country': 'Czech Republic',   'emoji': '🇨🇿'},
    {'code': '+45',  'country': 'Denmark',          'emoji': '🇩🇰'},
    {'code': '+372', 'country': 'Estonia',          'emoji': '🇪🇪'},
    {'code': '+358', 'country': 'Finland',          'emoji': '🇫🇮'},
    {'code': '+33',  'country': 'France',           'emoji': '🇫🇷'},
    {'code': '+49',  'country': 'Germany',          'emoji': '🇩🇪'},
    {'code': '+30',  'country': 'Greece',           'emoji': '🇬🇷'},
    {'code': '+36',  'country': 'Hungary',          'emoji': '🇭🇺'},
    {'code': '+353', 'country': 'Ireland',          'emoji': '🇮🇪'},
    {'code': '+39',  'country': 'Italy',            'emoji': '🇮🇹'},
    {'code': '+371', 'country': 'Latvia',           'emoji': '🇱🇻'},
    {'code': '+370', 'country': 'Lithuania',        'emoji': '🇱🇹'},
    {'code': '+352', 'country': 'Luxembourg',       'emoji': '🇱🇺'},
    {'code': '+356', 'country': 'Malta',            'emoji': '🇲🇹'},
    {'code': '+31',  'country': 'Netherlands',      'emoji': '🇳🇱'},
    {'code': '+48',  'country': 'Poland',           'emoji': '🇵🇱'},
    {'code': '+351', 'country': 'Portugal',         'emoji': '🇵🇹'},
    {'code': '+40',  'country': 'Romania',          'emoji': '🇷🇴'},
    {'code': '+421', 'country': 'Slovakia',         'emoji': '🇸🇰'},
    {'code': '+386', 'country': 'Slovenia',         'emoji': '🇸🇮'},
    {'code': '+34',  'country': 'Spain',            'emoji': '🇪🇸'},
    {'code': '+46',  'country': 'Sweden',           'emoji': '🇸🇪'},
  ];

  // Get default phone code for country
  String _getDefaultPhoneCode(String country) {
    switch (country) {
      case 'United States':   return '+1';
      case 'Canada':          return '+1';
      case 'Mexico':          return '+52';
      case 'United Kingdom':  return '+44';
      case 'Germany':         return '+49';
      case 'Austria':         return '+43';
      case 'Switzerland':     return '+41';
      case 'Belgium':         return '+32';
      case 'Bulgaria':        return '+359';
      case 'Croatia':         return '+385';
      case 'Cyprus':          return '+357';
      case 'Czech Republic':  return '+420';
      case 'Denmark':         return '+45';
      case 'Estonia':         return '+372';
      case 'Finland':         return '+358';
      case 'France':          return '+33';
      case 'Greece':          return '+30';
      case 'Hungary':         return '+36';
      case 'Ireland':         return '+353';
      case 'Italy':           return '+39';
      case 'Latvia':          return '+371';
      case 'Lithuania':       return '+370';
      case 'Luxembourg':      return '+352';
      case 'Malta':           return '+356';
      case 'Netherlands':     return '+31';
      case 'Poland':          return '+48';
      case 'Portugal':        return '+351';
      case 'Romania':         return '+40';
      case 'Slovakia':        return '+421';
      case 'Slovenia':        return '+386';
      case 'Spain':           return '+34';
      case 'Sweden':          return '+46';
      default:                return '+1';
    }
  }

  // Error states for validation
  bool _usdotError = false;
  bool _mcNumberError = false;
  bool _companyNameError = false;
  bool _companyStreetError = false;
  bool _companyStreetNumberError = false;
  bool _companyCityError = false;
  bool _companyZipError = false;
  bool _companyEmailError = false;
  bool _companyPhoneError = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Validate legal structure against localized list (needs context, can't do in initState)
    if (!_legalStructures.contains(_selectedLegalStructure)) {
      _selectedLegalStructure = _getDefaultLegalStructure(_selectedCountry);
    }
  }

  void _loadInitialData() {
    // Load single driver state first
    _isSingleDriver = widget.initialData['isSingleDriver'] == true;

    // Load existing company data if any
    _usdotController.text = widget.initialData['usdotNumber']?.toString() ?? '';
    _mcNumberController.text = widget.initialData['mcNumber']?.toString() ?? '';
    _companyNameController.text =
        widget.initialData['companyName']?.toString() ?? '';
    _dbaNameController.text = widget.initialData['dbaName']?.toString() ?? '';
    _companyStreetController.text =
        widget.initialData['companyStreet']?.toString() ?? '';
    _companyStreetNumberController.text =
        widget.initialData['companyStreetNumber']?.toString() ?? '';
    _companyCityController.text =
        widget.initialData['companyCity']?.toString() ?? '';
    _companyZipController.text =
        widget.initialData['companyZip']?.toString() ?? '';
    _companyEmailController.text =
        widget.initialData['companyEmail']?.toString() ?? '';
    _companyPhoneController.text =
        widget.initialData['companyPhone']?.toString() ?? '';

    // Use country from Step 1 as default, fallback to companyCountry if set
    _selectedCountry =
        widget.initialData['companyCountry']?.toString() ??
        widget.initialData['country']?.toString() ??
        'United States';

    // Set legal structure based on country, use saved value if valid
    _selectedLegalStructure =
        widget.initialData['legalStructure']?.toString() ??
        _getDefaultLegalStructure(_selectedCountry);

    // (Validation against localized list happens in didChangeDependencies)

    // Set default state based on country
    _selectedState =
        widget.initialData['companyState']?.toString() ??
        _getDefaultState(_selectedCountry);

    // Make sure state is valid for selected country
    if (!_statesList.contains(_selectedState)) {
      _selectedState = _getDefaultState(_selectedCountry);
    }

    // Set phone code based on country
    _selectedPhoneCountryCode =
        widget.initialData['phoneCountryCode']?.toString() ??
        _getDefaultPhoneCode(_selectedCountry);
  }

  @override
  void dispose() {
    _usdotController.dispose();
    _mcNumberController.dispose();
    _companyNameController.dispose();
    _dbaNameController.dispose();
    _companyStreetController.dispose();
    _companyStreetNumberController.dispose();
    _companyCityController.dispose();
    _companyZipController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    super.dispose();
  }

  // Validation method
  void _validateAndContinue() {
    bool isValid = true;

    // Reset all error states
    setState(() {
      _usdotError = false;
      _mcNumberError = false;
      _companyNameError = false;
      _companyStreetError = false;
      _companyStreetNumberError = false;
      _companyCityError = false;
      _companyZipError = false;
      _companyEmailError = false;
      _companyPhoneError = false;
    });

    // If single driver, skip company validation
    if (_isSingleDriver) {
      // Save single driver data
      widget.initialData.addAll({
        'isSingleDriver': true,
        'usdotNumber': '',
        'mcNumber': '',
        'legalStructure': 'Individual',
        'companyName': '',
        'dbaName': '',
        'companyStreet': '',
        'companyStreetNumber': '',
        'companyCity': '',
        'companyState': '',
        'companyZip': '',
        'companyEmail': '',
        'companyPhone': '',
        'phoneCountryCode': '',
        'companyCountry': _selectedCountry,
      });

      print('DEBUG Step 7: Saved single driver data');
      widget.onNext();
      return;
    }

    // Validate individual fields for company driver
    // USDOT and MC are only required for US
    if (_isUSCountry) {
      if (_usdotController.text.isEmpty || _usdotController.text.length != 8) {
        _usdotError = true;
        isValid = false;
      }

      if (_mcNumberController.text.isEmpty ||
          _mcNumberController.text.length < 6 ||
          _mcNumberController.text.length > 7) {
        _mcNumberError = true;
        isValid = false;
      }
    }

    if (_companyNameController.text.isEmpty) {
      _companyNameError = true;
      isValid = false;
    }

    if (_companyStreetController.text.isEmpty) {
      _companyStreetError = true;
      isValid = false;
    }

    if (_companyStreetNumberController.text.isEmpty) {
      _companyStreetNumberError = true;
      isValid = false;
    }

    if (_companyCityController.text.isEmpty) {
      _companyCityError = true;
      isValid = false;
    }

    if (_companyZipController.text.isEmpty) {
      _companyZipError = true;
      isValid = false;
    }

    if (_companyEmailController.text.isEmpty ||
        !RegExp(
          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
        ).hasMatch(_companyEmailController.text)) {
      _companyEmailError = true;
      isValid = false;
    }

    if (_companyPhoneController.text.isEmpty) {
      _companyPhoneError = true;
      isValid = false;
    }

    // Update UI to show errors
    if (!isValid) {
      setState(() {});
      return;
    }

    if (isValid) {
      // Save company data
      widget.initialData.addAll({
        'isSingleDriver': false,
        'usdotNumber': _usdotController.text,
        'mcNumber': _mcNumberController.text,
        'legalStructure': _selectedLegalStructure,
        'companyName': _companyNameController.text,
        'dbaName': _dbaNameController.text,
        'companyStreet': _companyStreetController.text,
        'companyStreetNumber': _companyStreetNumberController.text,
        'companyCity': _companyCityController.text,
        'companyState': _selectedState,
        'companyZip': _companyZipController.text,
        'companyEmail': _companyEmailController.text,
        'companyPhone': _companyPhoneController.text,
        'phoneCountryCode': _selectedPhoneCountryCode,
        'companyCountry': _selectedCountry,
      });

      print('DEBUG Step 7: Saved company data');

      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final bool isLight = appSettings.isLightMode(context);

    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + 20,
            24,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Step 1 Style
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isLight ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        CupertinoIcons.briefcase,
                        color: isLight ? Colors.white : Colors.black,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context)?.companyInformation ?? 'Company Information',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isUSCountry
                          ? (AppLocalizations.of(context)?.stepSevenCarrierDetails ?? 'Step 7 of 9 – Carrier registration details')
                          : '${AppLocalizations.of(context)?.stepSevenCarrierDetails ?? 'Step 7 of 9 – Carrier registration details'} ($_personalCountry)',
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // DRIVER TYPE SELECTION
              _buildSectionHeader('Driver Type', isLight),
              const SizedBox(height: 16),

              // Single Driver Toggle Card
              _buildDriverTypeSelector(isLight),

              const SizedBox(height: 32),

              // Show company fields only if NOT single driver
              if (!_isSingleDriver) ...[
                // DOT & MC NUMBERS SECTION (US only)
                if (_isUSCountry) ...[
                  _buildSectionHeader('DOT & MC Numbers', isLight),
                  const SizedBox(height: 16),

                  // USDOT Number
                  _buildModernTextField(
                    controller: _usdotController,
                    label: AppLocalizations.of(context)?.usdotNumber ?? 'USDOT Number',
                    icon: CupertinoIcons.cube_box,
                    isLight: isLight,
                    keyboardType: TextInputType.number,
                    hasError: _usdotError,
                    inputFormatters: [USDOTFormatter()],
                    hint: AppLocalizations.of(context)?.pleaseEnter8DigitCode.replaceAll('Please enter the ', '').replaceAll('-digit code', ' digits') ?? '8 digits',
                  ),

                  const SizedBox(height: 16),

                  // MC Number
                  _buildModernTextField(
                    controller: _mcNumberController,
                    label: AppLocalizations.of(context)?.mcNumber ?? 'MC Number',
                    icon: CupertinoIcons.doc_text,
                    isLight: isLight,
                    keyboardType: TextInputType.number,
                    hasError: _mcNumberError,
                    inputFormatters: [MCNumberFormatter()],
                    hint: AppLocalizations.of(context)?.sixToSevenDigits ??
                        '',
                  ),

                  const SizedBox(height: 16),
                ],

                // Legal Structure Dropdown
                _buildLegalStructureSelector(isLight),

                const SizedBox(height: 32),

                // COMPANY REGISTRATION SECTION
                _buildSectionHeader('Official Company Registration', isLight),
                const SizedBox(height: 16),

                // Official Company Name
                _buildModernTextField(
                  controller: _companyNameController,
                  label: AppLocalizations.of(context)?.officialCompanyName ?? 'Official Company Name',
                  icon: CupertinoIcons.briefcase,
                  isLight: isLight,
                  hasError: _companyNameError,
                ),

                const SizedBox(height: 16),

                // DBA Name (Optional)
                _buildModernTextField(
                  controller: _dbaNameController,
                  label: AppLocalizations.of(context)?.dbaNameOptional ?? 'DBA Name (Optional)',
                  icon: CupertinoIcons.bag,
                  isLight: isLight,
                ),

                const SizedBox(height: 32),

                // COMPANY ADDRESS SECTION
                _buildSectionHeader('Main Business Address', isLight),
                const SizedBox(height: 16),

                // Street and Number Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildModernTextField(
                        controller: _companyStreetController,
                        label: AppLocalizations.of(context)?.street ?? 'Street',
                        icon: CupertinoIcons.location,
                        isLight: isLight,
                        hasError: _companyStreetError,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildModernTextField(
                        controller: _companyStreetNumberController,
                        label: AppLocalizations.of(context)?.numberAbbreviation ?? 'No.',
                        icon: CupertinoIcons.tag,
                        isLight: isLight,
                        keyboardType: TextInputType.text,
                        hasError: _companyStreetNumberError,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // City and ZIP Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildModernTextField(
                        controller: _companyCityController,
                        label: AppLocalizations.of(context)?.city ?? 'City',
                        icon: CupertinoIcons.building_2_fill,
                        isLight: isLight,
                        hasError: _companyCityError,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildModernTextField(
                        controller: _companyZipController,
                        label: AppLocalizations.of(context)?.zip ?? 'ZIP',
                        icon: CupertinoIcons.placemark,
                        isLight: isLight,
                        keyboardType: TextInputType.number,
                        hasError: _companyZipError,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Country Selection
                _buildCountrySelector(isLight),

                const SizedBox(height: 16),

                // State Selection (dependent on country)
                _buildStateSelector(isLight),

                const SizedBox(height: 32),

                // CONTACT INFORMATION SECTION
                _buildSectionHeader('Company Contact Information', isLight),
                const SizedBox(height: 16),

                // Company Email
                _buildModernTextField(
                  controller: _companyEmailController,
                  label: AppLocalizations.of(context)?.companyEmail ?? 'Company Email',
                  icon: CupertinoIcons.mail,
                  isLight: isLight,
                  keyboardType: TextInputType.emailAddress,
                  hasError: _companyEmailError,
                ),

                const SizedBox(height: 16),

                // Company Phone with Country Code
                _buildPhoneField(isLight),
              ], // End of if (!_isSingleDriver)

              const SizedBox(height: 40),

              // Navigation Buttons
              Row(
                children: [
                  // Back Button
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: TradeRepublicButton.icon(
                            icon: Icon(CupertinoIcons.chevron_back, size: 18),
                            onPressed: widget.onBack,
                          ),
                  ),

                  const SizedBox(width: 12),

                  // Continue Button - Full Width with Gradient
                  Expanded(
                    child: TradeRepublicButton(
                            label: AppLocalizations.of(context)?.continueToVerification ?? 'Continue to Verification',
                            icon: Icon(CupertinoIcons.arrow_right, size: 18),
                            onPressed: _validateAndContinue,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  // Section Header Builder - Step 1 Style
  // Driver Type Selector - Single Driver vs Company Driver
  Widget _buildDriverTypeSelector(bool isLight) {
    // Android: Custom cards without border
    return Row(
      children: [
        // Single Driver Option
        Expanded(
          child: TradeRepublicTap(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _isSingleDriver = true;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 120,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isSingleDriver
                    ? (isLight ? Colors.black : Colors.white)
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.person_fill,
                    size: 32,
                    color: _isSingleDriver
                        ? (isLight ? Colors.white : Colors.black)
                        : ((isLight ? Colors.black : Colors.white).withOpacity(
                            0.5,
                          )),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)?.singleDriver ?? 'Single Driver',
                    style: TextStyle(
                      color: _isSingleDriver
                          ? (isLight ? Colors.white : Colors.black)
                          : (isLight ? Colors.black : Colors.white),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)?.independent ?? 'Independent',
                    style: TextStyle(
                      color: _isSingleDriver
                          ? (isLight ? Colors.white70 : Colors.black54)
                          : (isLight ? Colors.black45 : Colors.white54),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Company Driver Option
        Expanded(
          child: TradeRepublicTap(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _isSingleDriver = false;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 120,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: !_isSingleDriver
                    ? (isLight ? Colors.black : Colors.white)
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.building_2_fill,
                    size: 32,
                    color: !_isSingleDriver
                        ? (isLight ? Colors.white : Colors.black)
                        : ((isLight ? Colors.black : Colors.white).withOpacity(
                            0.5,
                          )),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)?.companyDriver ?? 'Company Driver',
                    style: TextStyle(
                      color: !_isSingleDriver
                          ? (isLight ? Colors.white : Colors.black)
                          : (isLight ? Colors.black : Colors.white),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)?.workForACompany ?? 'Work for a company',
                    style: TextStyle(
                      color: !_isSingleDriver
                          ? (isLight ? Colors.white70 : Colors.black54)
                          : (isLight ? Colors.black45 : Colors.white54),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 0),
      child: Text(
        title,
        style: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Modern TextField Builder - Step 1 Style
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isLight,
    TextInputType? keyboardType,
    bool hasError = false,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: hasError
            ? Colors.red.withOpacity(0.08)
            : (isLight ? Colors.white : Colors.transparent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with icon
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    color: isLight ? Colors.white : Colors.black,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // TradeRepublicTextField without extra wrapper
            TradeRepublicTextField(
              useFormField: true,
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              hintText: hint,
            ),
          ],
        ),
      ),
    );
  }

  // Legal Structure Selector - Step 1 Style
  Widget _buildLegalStructureSelector(bool isLight) {
    return TradeRepublicTap(
      onTap: () => _showLegalStructureBottomSheet(isLight),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      CupertinoIcons.building_2_fill,
                      color: isLight ? Colors.white : Colors.black,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.legalStructure ?? 'Legal Structure',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Selector field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.05,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedLegalStructure,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 16,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show Legal Structure Bottom Sheet - Settings Page Style
  void _showLegalStructureBottomSheet(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.building_2_fill, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      AppLocalizations.of(context)?.selectLegalStructure ?? 'Select Legal Structure',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                // Options
                ..._legalStructures.map((structure) {
                  final bool isSelected = _selectedLegalStructure == structure;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TradeRepublicTap(
                      onTap: () {
                        setState(() {
                          _selectedLegalStructure = structure;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isLight ? Colors.black : Colors.white)
                              : (isLight
                                    ? Colors.black.withOpacity(0.04)
                                    : const Color(0xFF121212)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                structure,
                                style: TextStyle(
                                  color: isSelected
                                      ? (isLight ? Colors.white : Colors.black)
                                      : (isLight ? Colors.black : Colors.white),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                CupertinoIcons.check_mark_circled,
                                color: isLight ? Colors.white : Colors.black,
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 12),

                // Cancel button
                TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
              ],
            ),
      );
  }

  // Phone Field with Country Code Selector
  Widget _buildPhoneField(bool isLight) {
    final selectedPhoneData = _phoneCountryCodes.firstWhere(
      (phone) => phone['code'] == _selectedPhoneCountryCode,
      orElse: () => _phoneCountryCodes[0],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 140,
      decoration: BoxDecoration(
        color: _companyPhoneError
            ? Colors.red.withOpacity(0.08)
            : (isLight ? Colors.white : Colors.transparent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    CupertinoIcons.phone,
                    color: isLight ? Colors.white : Colors.black,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.companyPhone ?? 'Company Phone',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Input field with country code selector
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.05,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    // Country code selector
                    TradeRepublicTap(
                      onTap: () => _showPhoneCountryCodeBottomSheet(isLight),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              selectedPhoneData['emoji']!,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedPhoneCountryCode,
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.chevron_down,
                              size: 12,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Vertical divider
                    Container(
                      width: 1,
                      height: 24,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.1),
                    ),
                    // Phone number input
                    Expanded(
                      child: TradeRepublicTextField(
                        controller: _companyPhoneController,
                        keyboardType: TextInputType.phone,
                        useFormField: true,
                        inputFormatters: _selectedPhoneCountryCode == '+1'
                            ? [USPhoneFormatter()]
                            : [GermanPhoneFormatter()],
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                        hintText: _selectedPhoneCountryCode == '+1'
                            ? '(555) 123-4567'
                            : '1234 5678901',
                        hintStyle: TextStyle(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.2,
                        ),
                        filled: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show Phone Country Code Bottom Sheet
  void _showPhoneCountryCodeBottomSheet(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.phone, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      AppLocalizations.of(context)?.selectCountryCode ?? 'Select Country Code',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                // Scrollable list for phone codes
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _phoneCountryCodes.map((phoneData) {
                        final bool isSelected =
                            _selectedPhoneCountryCode == phoneData['code'];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TradeRepublicTap(
                            onTap: () {
                              setState(() {
                                _selectedPhoneCountryCode = phoneData['code']!;
                                _companyPhoneController
                                    .clear(); // Clear phone when changing country code
                              });
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isLight ? Colors.black : Colors.white)
                                    : (isLight
                                          ? Colors.black.withOpacity(0.04)
                                          : const Color(0xFF121212)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  // Flag emoji
                                  Text(
                                    phoneData['emoji']!,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    phoneData['code']!,
                                    style: TextStyle(
                                      color: isSelected
                                          ? (isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (isLight
                                                ? Colors.black
                                                : Colors.white),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      phoneData['country']!,
                                      style: TextStyle(
                                        color: isSelected
                                            ? (isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      CupertinoIcons.check_mark_circled,
                                      color: isLight
                                          ? Colors.white
                                          : Colors.black,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel button
                TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
              ],
            ),
      );
  }

  // Country Selector - Step 1 Style with Flag
  Widget _buildCountrySelector(bool isLight) {
    final selectedCountryData = _countries.firstWhere(
      (country) => country['name'] == _selectedCountry,
      orElse: () => _countries[0],
    );

    return TradeRepublicTap(
      onTap: () => _showCountryBottomSheet(isLight),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      CupertinoIcons.globe,
                      color: isLight ? Colors.white : Colors.black,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.country ?? 'Country',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Selector field with flag
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.05,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Flag emoji
                      Text(
                        selectedCountryData['emoji']!,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedCountry,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 16,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // State Selector - Step 1 Style (dependent on country)
  Widget _buildStateSelector(bool isLight) {
    final stateLabel = _getStateLabel(_selectedCountry);

    return TradeRepublicTap(
      onTap: () => _showStateBottomSheet(isLight),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      CupertinoIcons.map,
                      color: isLight ? Colors.white : Colors.black,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stateLabel,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Selector field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.05,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedState,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 16,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show State Bottom Sheet - Settings Page Style
  void _showStateBottomSheet(bool isLight) {
    final stateLabel = _getStateLabel(_selectedCountry);

    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.location, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      'Select \$stateLabel',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                // Scrollable list for states
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _statesList.map((state) {
                        final bool isSelected = _selectedState == state;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TradeRepublicTap(
                            onTap: () {
                              setState(() {
                                _selectedState = state;
                              });
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isLight ? Colors.black : Colors.white)
                                    : (isLight
                                          ? Colors.black.withOpacity(0.04)
                                          : const Color(0xFF121212)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      state,
                                      style: TextStyle(
                                        color: isSelected
                                            ? (isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      CupertinoIcons.check_mark_circled,
                                      color: isLight
                                          ? Colors.white
                                          : Colors.black,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel button
                TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
              ],
            ),
      );
  }

  // Show Country Bottom Sheet - Settings Page Style with Flags
  void _showCountryBottomSheet(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.globe, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      AppLocalizations.of(context)?.selectCountry ?? 'Select Country',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                // Scrollable list for countries
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _countries.map((country) {
                        final bool isSelected =
                            _selectedCountry == country['name'];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TradeRepublicTap(
                            onTap: () {
                              setState(() {
                                final oldCountry = _selectedCountry;
                                _selectedCountry = country['name']!;
                                // Reset state, legal structure and phone code when country changes
                                if (oldCountry != _selectedCountry) {
                                  _selectedState = _getDefaultState(
                                    _selectedCountry,
                                  );
                                  _selectedLegalStructure =
                                      _getDefaultLegalStructure(
                                        _selectedCountry,
                                      );
                                  _selectedPhoneCountryCode =
                                      _getDefaultPhoneCode(_selectedCountry);
                                }
                              });
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isLight ? Colors.black : Colors.white)
                                    : (isLight
                                          ? Colors.black.withOpacity(0.04)
                                          : const Color(0xFF121212)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  // Flag emoji
                                  Text(
                                    country['emoji']!,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      country['name']!,
                                      style: TextStyle(
                                        color: isSelected
                                            ? (isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      CupertinoIcons.check_mark_circled,
                                      color: isLight
                                          ? Colors.white
                                          : Colors.black,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel button
                TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
              ],
            ),
      );
  }
}
