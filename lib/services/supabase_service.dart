import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/nearby_alert_model.dart';
import 'storage_service.dart';

class SupabaseService {
  final StorageService _storageService;

  SupabaseService(this._storageService);

  String get _url => _storageService.loadSupabaseConfig()['url'] ?? '';
  String get _anonKey => _storageService.loadSupabaseConfig()['anonKey'] ?? '';
  bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  /// Full SQL Schema script for the user's Supabase backend
  static const String sqlSchemaScript = '''
-- ====================================================================
-- APRAJITA SAFETY APP - SUPABASE DATABASE SCHEMA
-- Run this script in the Supabase SQL Editor to initialize your backend
-- ====================================================================

-- 1. Create table for SOS Emergency Alerts
CREATE TABLE IF NOT EXISTS public.sos_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    user_phone TEXT,
    source TEXT NOT NULL DEFAULT 'APP_SOS_BUTTON',
    status TEXT NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'RESOLVED', 'CANCELLED'
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION DEFAULT 10.0,
    google_maps_url TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    resolved_at TIMESTAMP WITH TIME ZONE
);

-- 2. Create table for Nearby Community Distress Broadcasts
CREATE TABLE IF NOT EXISTS public.nearby_broadcasts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_id UUID REFERENCES public.sos_alerts(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    user_phone TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION DEFAULT 10.0,
    radius_km DOUBLE PRECISION DEFAULT 3.0,
    message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'RESPONDING', 'RESOLVED'
    responders_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Create table for Synchronized Emergency Contacts
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    is_primary BOOLEAN DEFAULT false,
    is_emergency_recipient BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nearby_broadcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;

-- 5. Create Permissive Policies for Demo/Safety Access
CREATE POLICY "Public read nearby broadcasts" ON public.nearby_broadcasts
    FOR SELECT USING (true);

CREATE POLICY "Public insert nearby broadcasts" ON public.nearby_broadcasts
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Public update nearby broadcasts" ON public.nearby_broadcasts
    FOR UPDATE USING (true);

CREATE POLICY "Public insert sos alerts" ON public.sos_alerts
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Public select sos alerts" ON public.sos_alerts
    FOR SELECT USING (true);

-- 6. Enable Realtime Broadcasting on nearby_broadcasts
ALTER PUBLICATION supabase_realtime ADD TABLE public.nearby_broadcasts;
''';

  /// Broadcasts an active distress alert to Supabase
  Future<bool> broadcastNearbyAlert(NearbyCommunityAlert alert) async {
    if (!isConfigured) {
      debugPrint('Supabase not configured yet. Alert kept in local cache.');
      return false;
    }

    try {
      final endpoint = Uri.parse('$_url/rest/v1/nearby_broadcasts');
      final response = await http.post(
        endpoint,
        headers: {
          'apikey': _anonKey,
          'Authorization': 'Bearer $_anonKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        body: jsonEncode(alert.toJson()),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Supabase broadcast error: $e');
      return false;
    }
  }

  /// Fetches active nearby alerts from Supabase
  Future<List<NearbyCommunityAlert>> fetchNearbyBroadcasts() async {
    if (!isConfigured) return [];

    try {
      final endpoint = Uri.parse(
          '$_url/rest/v1/nearby_broadcasts?status=eq.ACTIVE&order=created_at.desc&limit=25');
      final response = await http.get(
        endpoint,
        headers: {
          'apikey': _anonKey,
          'Authorization': 'Bearer $_anonKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => NearbyCommunityAlert.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Supabase fetch error: $e');
      return [];
    }
  }

  /// Updates status in Supabase (e.g. 'RESOLVED' or increments responder count)
  Future<bool> updateBroadcastStatus(String id, String status) async {
    if (!isConfigured) return false;

    try {
      final endpoint = Uri.parse('$_url/rest/v1/nearby_broadcasts?id=eq.$id');
      final response = await http.patch(
        endpoint,
        headers: {
          'apikey': _anonKey,
          'Authorization': 'Bearer $_anonKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
