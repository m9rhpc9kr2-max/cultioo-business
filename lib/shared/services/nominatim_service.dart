import 'dart:convert';
import 'package:http/http.dart' as http;

class NominatimService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org/search';

  static Future<List<String>> searchAddresses(String query) async {
    if (query.isEmpty || query.length < 3) {
      return [];
    }

    try {
      // Build the search query with business-focused parameters
      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'q': query,
          'format': 'json',
          'addressdetails': '1',
          'limit': '10',
          'countrycodes': 'us,de', // Support US and Germany addresses
          'bounded': '1',
          'extratags': '1',
        });

      print('🌍 Nominatim request: $uri');

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'CultiooBusinessApp/1.0 (business-address-search)',
        });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('📍 Nominatim response: Found ${data.length} results');

        List<String> addresses = [];

        for (var item in data) {
          final displayName = item['display_name'] as String?;
          if (displayName != null) {
            // Format the address for business use
            String formattedAddress = _formatBusinessAddress(item);
            if (formattedAddress.isNotEmpty &&
                !addresses.contains(formattedAddress)) {
              addresses.add(formattedAddress);
            }
          }
        }

        print('✅ Formatted ${addresses.length} unique addresses');
        return addresses;
      } else {
        print('❌ Nominatim error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('💥 Nominatim exception: $e');
      return [];
    }
  }

  static String _formatBusinessAddress(Map<String, dynamic> data) {
    try {
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) {
        // Fallback to display_name if no structured address
        return data['display_name'] as String? ?? '';
      }

      List<String> parts = [];

      // House number and street
      final houseNumber = address['house_number'] as String?;
      final street = address['road'] as String?;

      if (houseNumber != null && street != null) {
        parts.add('$street $houseNumber');
      } else if (street != null) {
        parts.add(street);
      }

      // City
      final city =
          address['city'] as String? ??
          address['town'] as String? ??
          address['village'] as String?;

      // State
      final state = address['state'] as String?;

      // Postal code
      final postcode = address['postcode'] as String?;

      // Country
      final country = address['country'] as String?;
      final countryCode = address['country_code'] as String?;

      // Build formatted address based on country
      if (parts.isNotEmpty) {
        String formattedAddress = parts.join(', ');

        // Format based on country (German vs US format)
        if (countryCode == 'de') {
          // German format: Street Number, PLZ City, Germany
          if (postcode != null && city != null) {
            formattedAddress += ', $postcode $city';
          } else if (city != null) {
            formattedAddress += ', $city';
          }

          if (state != null) {
            formattedAddress += ', $state';
          }

          formattedAddress += ', Germany';
        } else {
          // US format: Street Number, City State ZIP, USA
          if (city != null && postcode != null) {
            if (state != null) {
              formattedAddress += ', $city, $state $postcode';
            } else {
              formattedAddress += ', $postcode $city';
            }
          } else if (city != null) {
            formattedAddress += ', $city';
            if (state != null) {
              formattedAddress += ', $state';
            }
          }

          if (country != null &&
              !country.toLowerCase().contains('united states')) {
            formattedAddress += ', $country';
          } else if (countryCode == 'us') {
            formattedAddress += ', USA';
          }
        }

        return formattedAddress;
      }

      return '';
    } catch (e) {
      print('🔧 Address formatting error: $e');
      return data['display_name'] as String? ?? '';
    }
  }
}
