import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/environment.dart';
import '../network/urls.dart';

class ImageRequestModel {
  final String lemma;
  final String userL1;
  final String userL2;
  final String? langCode;
  final bool? usePexels;
  final bool? useUnsplash;
  final bool? useDalle2;

  ImageRequestModel({
    required this.lemma,
    required this.userL1,
    required this.userL2,
    this.langCode,
    this.usePexels,
    this.useUnsplash,
    this.useDalle2,
  });

  Map<String, dynamic> toJson() {
    return {
      'lemma': lemma,
      'user_l1': userL1,
      'user_l2': userL2,
      'lang_code': langCode,
      'use_pexels': usePexels,
      'use_unsplash': useUnsplash,
      'use_dalle2': useDalle2,
    };
  }

  @override
  int get hashCode => toJson().hashCode;

  @override
  bool operator ==(Object other) {
    return other is ImageRequestModel && hashCode == other.hashCode;
  }
}

class ImageResponseModel {
  final String? imageUrl;
  final String method;
  final String? message;

  ImageResponseModel({
    this.imageUrl,
    required this.method,
    this.message,
  });

  factory ImageResponseModel.fromJson(Map<String, dynamic> json) {
    return ImageResponseModel(
      imageUrl: json['image_url'],
      method: json['method'],
      message: json['message'],
    );
  }
}

class ImageGenerationController {
  // Cache and API URL as static properties
  static final Map<int, _CacheItem> _cache = {};
  static final String apiUrl = PApiUrls.image;

  static Future<ImageResponseModel> generateImage(
    ImageRequestModel requestModel,
  ) async {
    final int cacheKey = requestModel.hashCode;

    // Check cache
    if (_cache.containsKey(cacheKey) && !_cache[cacheKey]!.isExpired) {
      debugPrint('Cache hit for request: $requestModel');
      return _cache[cacheKey]!.data;
    }

    // Make network call if not cached or cache expired
    final body = jsonEncode(requestModel.toJson());

    try {
      final response = await http.post(
        Uri.parse(PApiUrls.image),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Environment.choreoApiKey}',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final imageResponse = ImageResponseModel.fromJson(json);

        // Add response to cache with 1-minute TTL
        _cache[cacheKey] = _CacheItem(
          data: imageResponse,
          expiryTime: DateTime.now().add(const Duration(minutes: 1)),
        );

        return imageResponse;
      } else {
        debugPrint('Error generating image: ${response.body}');
        throw Exception('Failed to generate image');
      }
    } catch (e) {
      debugPrint('Exception occurred while generating image: $e');
      throw Exception('Exception occurred while generating image');
    }
  }
}

// Private cache item class
class _CacheItem {
  final ImageResponseModel data;
  final DateTime expiryTime;

  _CacheItem({
    required this.data,
    required this.expiryTime,
  });

  bool get isExpired => DateTime.now().isAfter(expiryTime);
}
