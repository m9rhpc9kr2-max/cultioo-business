import '../services/app_localizations.dart';

class WagonTypeOption {
  final String id;
  final String icon;

  const WagonTypeOption({required this.id, required this.icon});
}

class WagonTypesCatalog {
  static const List<WagonTypeOption> all = [
    // Food & temperature-controlled
    WagonTypeOption(id: 'grain_tipper', icon: '🌾'),
    WagonTypeOption(id: 'grain_tanker', icon: '🚛'),
    WagonTypeOption(id: 'oil', icon: '🛢️'),
    WagonTypeOption(id: 'vegetable_oil', icon: '🌻'),
    WagonTypeOption(id: 'liquid_food', icon: '🥛'),
    WagonTypeOption(id: 'milk_tanker', icon: '🥛'),
    WagonTypeOption(id: 'dairy_transport', icon: '🧈'),
    WagonTypeOption(id: 'meat', icon: '🥩'),
    WagonTypeOption(id: 'poultry_transport', icon: '🐔'),
    WagonTypeOption(id: 'charcuterie_delicatessen', icon: '🥓'),
    WagonTypeOption(id: 'fish_seafood', icon: '🐟'),
    WagonTypeOption(id: 'cheese_transport', icon: '🧀'),
    WagonTypeOption(id: 'eggs_transport', icon: '🥚'),
    WagonTypeOption(id: 'refrigerated', icon: '❄️'),
    WagonTypeOption(id: 'frozen', icon: '🧊'),
    WagonTypeOption(id: 'fresh_produce', icon: '🥬'),
    WagonTypeOption(id: 'temperature_controlled', icon: '🌡️'),
    WagonTypeOption(id: 'bakery', icon: '🍞'),
    WagonTypeOption(id: 'beverage', icon: '🥤'),
    WagonTypeOption(id: 'coffee_tea', icon: '☕'),
    WagonTypeOption(id: 'wine_alcohol', icon: '🍷'),
    WagonTypeOption(id: 'chocolate_confectionery', icon: '🍫'),
    WagonTypeOption(id: 'honey_jam', icon: '🍯'),
    WagonTypeOption(id: 'spices_herbs', icon: '🌶️'),
    WagonTypeOption(id: 'nuts_seeds', icon: '🥜'),
    WagonTypeOption(id: 'dry_bulk', icon: '📦'),
    WagonTypeOption(id: 'dry_goods', icon: '📦'),
    WagonTypeOption(id: 'meal_prep_catering', icon: '🍱'),
    WagonTypeOption(id: 'organic_bio', icon: '♻️'),
    WagonTypeOption(id: 'kosher_halal', icon: '✡️'),
    WagonTypeOption(id: 'pharma_healthcare', icon: '⚕️'),
    WagonTypeOption(id: 'pet_food', icon: '🐾'),
    WagonTypeOption(id: 'specialty', icon: '⭐'),

    // General logistics
    WagonTypeOption(id: 'box_truck', icon: '🚚'),
    WagonTypeOption(id: 'panel_van', icon: '🚐'),
    WagonTypeOption(id: 'curtain_sider', icon: '🧵'),
    WagonTypeOption(id: 'flatbed', icon: '🛻'),
    WagonTypeOption(id: 'drop_deck', icon: '⬇️'),
    WagonTypeOption(id: 'low_loader', icon: '🏗️'),
    WagonTypeOption(id: 'container_chassis', icon: '📦'),
    WagonTypeOption(id: 'swap_body', icon: '🔁'),
    WagonTypeOption(id: 'mega_trailer', icon: '📐'),
    WagonTypeOption(id: 'car_carrier', icon: '🚗'),
    WagonTypeOption(id: 'livestock', icon: '🐄'),
    WagonTypeOption(id: 'moving_floor', icon: '↔️'),
    WagonTypeOption(id: 'side_loader', icon: '↕️'),
    WagonTypeOption(id: 'crane_truck', icon: '🏗️'),

    // Tank / silo / industrial
    WagonTypeOption(id: 'silo_trailer', icon: '🏭'),
    WagonTypeOption(id: 'cement_silo', icon: '🧱'),
    WagonTypeOption(id: 'powder_tanker', icon: '🌫️'),
    WagonTypeOption(id: 'bitumen_tanker', icon: '🛣️'),
    WagonTypeOption(id: 'food_tanker', icon: '🥣'),

    // ADR / dangerous goods
    WagonTypeOption(id: 'adr_general', icon: '☣️'),
    WagonTypeOption(id: 'adr_tanker', icon: '🛢️'),
    WagonTypeOption(id: 'fuel_tanker', icon: '⛽'),
    WagonTypeOption(id: 'chemical_tanker', icon: '🧪'),
    WagonTypeOption(id: 'gas_tanker', icon: '🔥'),
    WagonTypeOption(id: 'explosives_transport', icon: '💥'),
    WagonTypeOption(id: 'flammable_liquids', icon: '🧯'),
    WagonTypeOption(id: 'corrosive_materials', icon: '⚗️'),
    WagonTypeOption(id: 'hazardous_waste', icon: '🗑️'),
  ];

  static List<Map<String, String>> localized(AppLocalizations? loc) {
    return all
        .map((item) => {
              'id': item.id,
              'name': _name(loc, item.id),
              'description': _description(loc, item.id),
              'icon': item.icon,
            })
        .toList(growable: false);
  }

  static Map<String, String> localizedById(AppLocalizations? loc, String? id) {
    final selectedId = (id == null || id.isEmpty) ? 'refrigerated' : id;
    final list = localized(loc);
    return list.firstWhere(
      (e) => e['id'] == selectedId,
      orElse: () => list.first);
  }

  static String _name(AppLocalizations? loc, String id) {
    final legacy = _legacyName(loc, id);
    if (legacy != null && legacy.isNotEmpty) return legacy;

    final key = 'wagon_type_name_$id';
    final t = loc?.tr(key) ?? key;
    if (t != key) return t;
    return _humanize(id);
  }

  static String _description(AppLocalizations? loc, String id) {
    final legacy = _legacyDescription(loc, id);
    if (legacy != null && legacy.isNotEmpty) return legacy;

    final key = 'wagon_type_desc_$id';
    final t = loc?.tr(key) ?? key;
    if (t != key) return t;
    return id;
  }

  static String? _legacyName(AppLocalizations? loc, String id) {
    if (loc == null) return null;
    switch (id) {
      case 'grain_tipper':
        return loc.grainHopper;
      case 'oil':
        return loc.oilTanker;
      case 'liquid_food':
        return loc.liquidFoodTanker;
      case 'dry_bulk':
        return loc.dryBulkCarrier;
      case 'refrigerated':
        return loc.refrigeratedTruck;
      case 'meat':
        return loc.meatTransport;
      case 'specialty':
        return loc.specialtyFoodTransport;
      default:
        return null;
    }
  }

  static String? _legacyDescription(AppLocalizations? loc, String id) {
    if (loc == null) return null;
    switch (id) {
      case 'grain_tipper':
        return loc.grainHopperDesc;
      case 'oil':
        return loc.oilTankerDesc;
      case 'liquid_food':
        return loc.liquidFoodTankerDesc;
      case 'dry_bulk':
        return loc.dryBulkCarrierDesc;
      case 'refrigerated':
        return loc.refrigeratedTruckDesc;
      case 'meat':
        return loc.meatTransportDesc;
      case 'specialty':
        return loc.specialtyFoodTransportDesc;
      default:
        return null;
    }
  }

  static String _humanize(String id) {
    final normalized = id.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return id;
    return normalized
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// English label for a canonical wagon id (e.g. from `products.wagon_type`).
  /// Does not use app locale — same string in every language for logistics/API clarity.
  static String englishLabel(String? id) {
    final raw = (id == null || id.trim().isEmpty) ? 'refrigerated' : id.trim();
    return _humanize(raw);
  }
}
