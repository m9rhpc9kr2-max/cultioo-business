import '../shared/services/app_localizations.dart';

String normalizeWagonTypeId(String? value) {
  final raw = (value ?? '').trim().toLowerCase();
  if (raw.isEmpty) return '';

  // Families mapped to scanner-localized buckets
  if (raw == 'grain_tipper' || raw == 'grain_tanker') return 'grain';
  if (raw == 'vegetable_oil') return 'oil';
  if (raw == 'milk_tanker' || raw == 'dairy_transport') return 'liquid_food';
  if (raw == 'charcuterie_delicatessen' || raw == 'poultry_transport') return 'meat';
  if (raw == 'fish_seafood' || raw == 'cheese_transport' || raw == 'eggs_transport') {
    return 'temperature_controlled';
  }
  if (raw == 'coffee_tea' || raw == 'wine_alcohol' || raw == 'honey_jam' || raw == 'nuts_seeds') {
    return 'dry_bulk';
  }
  if (raw == 'chocolate_confectionery' || raw == 'spices_herbs') return 'specialty';
  if (raw == 'meal_prep_catering' || raw == 'organic_bio' || raw == 'kosher_halal') {
    return 'specialty';
  }
  if (raw == 'pet_food') return 'dry_goods';

  if (raw == 'pharma_healthcare') return 'temperature_controlled';

  if (raw == 'food_safe' || raw == 'cold_chain') return 'refrigerated';

  if (raw == 'food_tanker') return 'liquid_food';
  if (raw == 'silo_trailer' || raw == 'cement_silo' || raw == 'powder_tanker') return 'dry_bulk';
  if (raw == 'bitumen_tanker') return 'oil';

  if (raw == 'adr_general' || raw == 'adr_tanker' || raw == 'fuel_tanker' || raw == 'chemical_tanker' || raw == 'gas_tanker' || raw == 'explosives_transport' || raw == 'flammable_liquids' || raw == 'corrosive_materials' || raw == 'hazardous_waste') {
    return 'specialty';
  }

  if (raw == 'box_truck' || raw == 'curtain_sider' || raw == 'flatbed' || raw == 'drop_deck' || raw == 'low_loader' || raw == 'container_chassis' || raw == 'swap_body' || raw == 'mega_trailer' || raw == 'car_carrier' || raw == 'livestock' || raw == 'moving_floor' || raw == 'side_loader' || raw == 'crane_truck') {
    return 'dry_goods';
  }
  if (raw == 'panel_van') return 'dry_goods';

  return raw;
}

String wagonLabelFromType(String? type, AppLocalizations l10n) {
  final raw = (type ?? '').trim().toLowerCase();
  switch (raw) {
    case 'grain_tipper':
      return l10n.grainHopper;
    case 'grain_tanker':
      return l10n.grainTanker;
    case 'oil':
      return l10n.oilTanker;
    case 'vegetable_oil':
      return l10n.vegetableOilTanker;
    case 'liquid_food':
      return l10n.liquidFoodTanker;
    case 'milk_tanker':
      return l10n.milkTanker;
    case 'dairy_transport':
      return l10n.dairyTransport;
    case 'meat':
      return l10n.meatTransport;
    case 'poultry_transport':
      return l10n.poultryTransport;
    case 'charcuterie_delicatessen':
      return l10n.charcuterieDelicatessen;
    case 'fish_seafood':
      return l10n.fishSeafood;
    case 'cheese_transport':
      return l10n.cheeseTransport;
    case 'eggs_transport':
      return l10n.eggsTransport;
    case 'refrigerated':
      return l10n.refrigeratedTruck;
    case 'frozen':
      return l10n.frozenTransport;
    case 'fresh_produce':
      return l10n.freshProduceVan;
    case 'temperature_controlled':
      return l10n.temperatureControlled;
    case 'bakery':
      return l10n.bakeryTruck;
    case 'beverage':
      return l10n.beverageCarrier;
    case 'coffee_tea':
      return l10n.coffeeTea;
    case 'wine_alcohol':
      return l10n.wineAlcohol;
    case 'chocolate_confectionery':
      return l10n.chocolateConfectionery;
    case 'honey_jam':
      return l10n.honeyJam;
    case 'spices_herbs':
      return l10n.spicesHerbs;
    case 'nuts_seeds':
      return l10n.nutsSeeds;
    case 'dry_bulk':
      return l10n.dryBulkCarrier;
    case 'dry_goods':
      return l10n.dryGoodsVan;
    case 'meal_prep_catering':
      return l10n.mealPrepCatering;
    case 'organic_bio':
      return l10n.organicBio;
    case 'kosher_halal':
      return l10n.kosherHalal;
    case 'pharma_healthcare':
      return l10n.pharmaHealthcare;
    case 'pet_food':
      return l10n.petFood;
    case 'specialty':
      return l10n.specialtyFoodTransport;
    case 'box_truck':
      return l10n.boxTruck;
    case 'panel_van':
      return l10n.panelVan;
    case 'curtain_sider':
      return l10n.curtainSider;
    case 'flatbed':
      return l10n.flatbed;
    case 'drop_deck':
      return l10n.dropDeck;
    case 'low_loader':
      return l10n.lowLoader;
    case 'container_chassis':
      return l10n.containerChassis;
    case 'swap_body':
      return l10n.swapBody;
    case 'mega_trailer':
      return l10n.megaTrailer;
    case 'car_carrier':
      return l10n.carCarrier;
    case 'livestock':
      return l10n.livestock;
    case 'moving_floor':
      return l10n.movingFloor;
    case 'side_loader':
      return l10n.sideLoader;
    case 'crane_truck':
      return l10n.craneTruck;
    case 'silo_trailer':
      return l10n.siloTrailer;
    case 'cement_silo':
      return l10n.cementSilo;
    case 'powder_tanker':
      return l10n.powderTanker;
    case 'bitumen_tanker':
      return l10n.bitumenTanker;
    case 'food_tanker':
      return l10n.foodTanker;
    case 'adr_general':
      return l10n.adrGeneral;
    case 'adr_tanker':
      return l10n.adrTanker;
    case 'fuel_tanker':
      return l10n.fuelTanker;
    case 'chemical_tanker':
      return l10n.chemicalTanker;
    case 'gas_tanker':
      return l10n.gasTanker;
    case 'explosives_transport':
      return l10n.explosivesTransport;
    case 'flammable_liquids':
      return l10n.flammableLiquids;
    case 'corrosive_materials':
      return l10n.corrosiveMaterials;
    case 'hazardous_waste':
      return l10n.hazardousWaste;
  }

  switch (normalizeWagonTypeId(raw)) {
    case 'grain':
      return l10n.grainHopper;
    case 'dry_bulk':
      return l10n.dryBulkCarrier;
    case 'oil':
      return l10n.oilTanker;
    case 'liquid_food':
      return l10n.liquidFoodTanker;
    case 'refrigerated':
      return l10n.refrigeratedTruck;
    case 'fresh_produce':
      return l10n.freshProduceVan;
    case 'frozen':
      return l10n.frozenTransport;
    case 'temperature_controlled':
      return l10n.temperatureControlled;
    case 'meat':
      return l10n.meatTransport;
    case 'bakery':
      return l10n.bakeryTruck;
    case 'beverage':
      return l10n.beverageCarrier;
    case 'specialty':
      return l10n.specialtyFoodTransport;
  }

  if (raw.isEmpty) return '';
  return raw
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String wagonDescriptionFromType(String? type, AppLocalizations l10n) {
  switch (normalizeWagonTypeId(type)) {
    case 'grain':
      return l10n.grainHopperDesc;
    case 'dry_bulk':
      return l10n.dryBulkCarrierDesc;
    case 'oil':
      return l10n.oilTankerDesc;
    case 'liquid_food':
      return l10n.liquidFoodTankerDesc;
    case 'refrigerated':
      return l10n.refrigeratedTruckDesc;
    case 'fresh_produce':
      return l10n.freshProduceVanDesc;
    case 'frozen':
      return l10n.frozenTransportDesc;
    case 'temperature_controlled':
      return l10n.temperatureControlledWagonDesc;
    case 'meat':
      return l10n.meatTransportDesc;
    case 'bakery':
      return l10n.bakeryTruckDesc;
    case 'beverage':
      return l10n.beverageCarrierDesc;
    case 'specialty':
      return l10n.specialtyFoodTransportDesc;
    default:
      return l10n.specialtyFoodTransportDesc;
  }
}
