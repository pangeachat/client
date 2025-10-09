import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/map/map.dart' as map_controller;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late map_controller.MapController controller;

  @override
  void initState() {
    super.initState();
    controller = map_controller.MapController(context);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 10.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined),
            Text(L10n.of(context).languages), // TODO: Add proper localization
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Row(
            children: [
              // Side Navigation
              _buildSideNavigation(),

              // Main Map Area
              Expanded(
                child: Column(
                  children: [
                    // Search Bar
                    _buildSearchBar(),

                    // Map
                    Expanded(
                      child: _buildMap(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSideNavigation() {
    return Container(
      width: 80,
      color: Theme.of(context).cardColor,
      child: Column(
        children: [
          const SizedBox(height: 16),
          // User Avatar (placeholder)
          GestureDetector(
            onTap: () {
              // TODO: Navigate to user analytics
            },
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.person, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          // Courses section
          Expanded(
            child: ListView.builder(
              itemCount: controller.userCourses.length,
              itemBuilder: (context, index) {
                final course = controller.userCourses[index];
                final isSelected = controller.selectedCourseId == course.uuid;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4.0,
                    horizontal: 8.0,
                  ),
                  child: GestureDetector(
                    onTap: () => controller.selectCourse(
                      isSelected ? null : course.uuid,
                    ),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          course.title.isEmpty
                              ? '?'
                              : course.title[0].toUpperCase(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // New Course Button
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: IconButton(
              onPressed: () {
                // TODO: Navigate to new course creation
              },
              icon: const Icon(Icons.add),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search locations...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: controller.updateSearchQuery,
      ),
    );
  }

  Widget _buildMap() {
    if (controller.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final locations = controller.filteredLocations;

    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(0, 0), // Global center
        initialZoom: 2.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          maxZoom: 18,
        ),
        MarkerLayer(
          markers: locations.map((location) => _buildMarker(location)).toList(),
        ),
      ],
    );
  }

  Marker _buildMarker(map_controller.MapLocationData location) {
    final isAnyTopicUnlocked = location.topics.any(controller.isTopicUnlocked);

    return Marker(
      key: Key(location.id),
      point: LatLng(location.latitude, location.longitude),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          controller.selectLocation(location);
          _showLocationBottomSheet(location);
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isAnyTopicUnlocked ? Colors.green : Colors.grey,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            isAnyTopicUnlocked ? Icons.location_on : Icons.lock,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  void _showLocationBottomSheet(map_controller.MapLocationData location) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildLocationBottomSheet(location),
    );
  }

  Widget _buildLocationBottomSheet(map_controller.MapLocationData location) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    location.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Image placeholder
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.image, size: 64),
            ),
            const SizedBox(height: 16),

            // Topics
            ...location.topics.map((topic) => _buildTopicCard(topic)),

            const SizedBox(height: 16),

            // Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Activities',
                    location.totalActivities.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Completed',
                    location.completedActivities.toString(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Action Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: location.topics.isNotEmpty
                    ? () async {
                        Navigator.of(context).pop();
                        await controller.goToTopic(location.topics.first);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Go', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicCard(map_controller.MapTopicData topic) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              topic.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (topic.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                topic.description,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
