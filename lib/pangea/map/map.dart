import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/course_plans/course_location_model.dart';
import 'package:fluffychat/pangea/course_plans/course_plan_model.dart';
import 'package:fluffychat/pangea/course_plans/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/course_plans/course_plans_repo.dart';
import 'package:fluffychat/pangea/course_plans/course_topic_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class MapController extends ChangeNotifier {
  final BuildContext context;
  bool _isLoading = false;
  String _searchQuery = '';
  String? _selectedCourseId;
  List<MapLocationData> _locations = [];
  MapLocationData? _selectedLocation;

  MapController(this.context) {
    _loadLocations();
  }

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String? get selectedCourseId => _selectedCourseId;
  List<MapLocationData> get locations => _locations;
  MapLocationData? get selectedLocation => _selectedLocation;

  List<MapLocationData> get filteredLocations {
    var filtered = _locations;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (location) => location.name
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    // Filter by selected course
    if (_selectedCourseId != null) {
      filtered = filtered
          .where(
            (location) => location.courseIds.contains(_selectedCourseId),
          )
          .toList();
    }

    return filtered;
  }

  List<CoursePlanModel> get userCourses {
    // Return courses that have been loaded during location loading
    final courseIds =
        _locations.expand((location) => location.courseIds).toSet().toList();

    final courses = <CoursePlanModel>[];
    for (final courseId in courseIds) {
      final course = _loadedCourses[courseId];
      if (course != null) {
        courses.add(course);
      }
    }

    return courses;
  }

  // Cache loaded courses
  final Map<String, CoursePlanModel> _loadedCourses = {};

  Future<void> _loadLocations() async {
    _isLoading = true;
    notifyListeners();

    try {
      final allLocations = <MapLocationData>[];
      final client = Matrix.of(context).client;

      debugPrint(
        'Map: Starting to load locations from ${client.rooms.length} rooms',
      );

      // Get all course topics and their locations
      for (final room in client.rooms) {
        if (room.isSpace && room.membership == Membership.join) {
          debugPrint('Map: Found space room: ${room.id} - ${room.name}');
          final coursePlanEvent = room.coursePlan;
          if (coursePlanEvent != null) {
            debugPrint('Map: Room has course plan: ${coursePlanEvent.uuid}');
            try {
              final coursePlan =
                  await CoursePlansRepo.get(coursePlanEvent.uuid);
              debugPrint(
                'Map: Loaded course plan: ${coursePlan.title} with ${coursePlan.topicIds.length} topics',
              );
              await _loadLocationsForCourse(coursePlan, allLocations);
            } catch (e) {
              debugPrint(
                'Error loading course plan ${coursePlanEvent.uuid}: $e',
              );
            }
          } else {
            debugPrint('Map: Room has no course plan: ${room.name}');
          }
        }
      }

      debugPrint('Map: Loaded ${allLocations.length} total locations');

      // If no locations found, add some sample locations for testing
      if (allLocations.isEmpty) {
        debugPrint('Map: No real locations found, adding sample locations');
        allLocations.addAll(_createSampleLocations());
      }

      _locations = allLocations;
    } catch (e) {
      debugPrint('Error loading map locations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<MapLocationData> _createSampleLocations() {
    return [
      MapLocationData(
        id: 'sample-paris',
        name: 'Paris',
        coordinates: [2.3522, 48.8566], // [longitude, latitude]
        courseIds: ['sample-course-1'],
        topics: [
          MapTopicData(
            id: 'sample-topic-1',
            title: 'French Conversation',
            description: 'Practice French conversation skills',
            courseId: 'sample-course-1',
            activityCount: 5,
            completedActivities: 2,
          ),
        ],
      ),
      MapLocationData(
        id: 'sample-tokyo',
        name: 'Tokyo',
        coordinates: [139.6917, 35.6895], // [longitude, latitude]
        courseIds: ['sample-course-2'],
        topics: [
          MapTopicData(
            id: 'sample-topic-2',
            title: 'Japanese Basics',
            description: 'Learn basic Japanese phrases',
            courseId: 'sample-course-2',
            activityCount: 8,
            completedActivities: 0,
          ),
        ],
      ),
      MapLocationData(
        id: 'sample-madrid',
        name: 'Madrid',
        coordinates: [-3.7038, 40.4168], // [longitude, latitude]
        courseIds: ['sample-course-3'],
        topics: [
          MapTopicData(
            id: 'sample-topic-3',
            title: 'Spanish Culture',
            description: 'Explore Spanish culture and traditions',
            courseId: 'sample-course-3',
            activityCount: 6,
            completedActivities: 3,
          ),
        ],
      ),
    ];
  }

  Future<void> _loadLocationsForCourse(
    CoursePlanModel course,
    List<MapLocationData> allLocations,
  ) async {
    try {
      // Store the course for later reference
      _loadedCourses[course.uuid] = course;

      final topics = await course.fetchTopics();
      debugPrint('Map: Course ${course.title} fetched ${topics.length} topics');

      for (final topic in topics) {
        final locations = await topic.fetchLocations();
        debugPrint(
          'Map: Topic ${topic.title} has ${locations.length} locations',
        );

        for (final location in locations) {
          // Check if location already exists
          var existingLocation = allLocations.firstWhereOrNull(
            (existing) => existing.id == location.uuid,
          );

          if (existingLocation == null) {
            // Create new location with coordinates (or generate random ones if not available)
            final coordinates = await _getOrGenerateCoordinates(location);
            debugPrint(
              'Map: Creating location ${location.name} at coordinates: $coordinates',
            );

            existingLocation = MapLocationData(
              id: location.uuid,
              name: location.name,
              coordinates: coordinates,
              courseIds: [course.uuid],
              topics: [MapTopicData.fromTopic(topic, course.uuid)],
            );
            allLocations.add(existingLocation);
          } else {
            // Add course and topic to existing location
            if (!existingLocation.courseIds.contains(course.uuid)) {
              existingLocation.courseIds.add(course.uuid);
            }
            existingLocation.topics
                .add(MapTopicData.fromTopic(topic, course.uuid));
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading locations for course ${course.uuid}: $e');
    }
  }

  Future<List<double>> _getOrGenerateCoordinates(
    CourseLocationModel location,
  ) async {
    // Use actual coordinates if available, otherwise generate random ones
    if (location.coordinates != null && location.coordinates!.length == 2) {
      return location.coordinates!;
    }

    // Generate random coordinates as fallback
    final random = Random();
    return [
      -180 + random.nextDouble() * 360, // longitude: -180 to 180
      -90 + random.nextDouble() * 180, // latitude: -90 to 90
    ];
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectCourse(String? courseId) {
    _selectedCourseId = courseId;
    notifyListeners();
  }

  void selectLocation(MapLocationData? location) {
    _selectedLocation = location;
    notifyListeners();
  }

  void clearSelection() {
    _selectedLocation = null;
    notifyListeners();
  }

  bool isTopicUnlocked(MapTopicData topic) {
    // TODO: Implement actual unlock logic based on user progress
    // This should check if the user has completed prerequisite topics
    return true; // Placeholder
  }

  int getCompletedActivitiesCount(MapTopicData topic) {
    // TODO: Implement actual progress tracking
    // This should return the number of completed activities for the topic
    return 0; // Placeholder
  }

  Future<void> goToTopic(MapTopicData topic) async {
    // Find the room that contains this course
    final client = Matrix.of(context).client;

    for (final room in client.rooms) {
      if (room.isSpace && room.membership == Membership.join) {
        final coursePlanEvent = room.coursePlan;
        if (coursePlanEvent != null && coursePlanEvent.uuid == topic.courseId) {
          // Navigate to the space details page
          if (context.mounted) {
            context.go('/rooms/spaces/${room.id}/details');
          }
          return;
        }
      }
    }

    // If no room found, show a message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Course not found. You may not be enrolled in this course.'),
        ),
      );
    }
  }
}

class MapLocationData {
  final String id;
  final String name;
  final List<double> coordinates; // [longitude, latitude]
  final List<String> courseIds;
  final List<MapTopicData> topics;

  MapLocationData({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.courseIds,
    required this.topics,
  });

  double get longitude => coordinates[0];
  double get latitude => coordinates[1];

  int get totalActivities =>
      topics.fold(0, (sum, topic) => sum + topic.activityCount);
  int get completedActivities =>
      topics.fold(0, (sum, topic) => sum + topic.completedActivities);
}

class MapTopicData {
  final String id;
  final String title;
  final String description;
  final String courseId;
  final String? imageUrl;
  final int activityCount;
  final int completedActivities;

  MapTopicData({
    required this.id,
    required this.title,
    required this.description,
    required this.courseId,
    this.imageUrl,
    required this.activityCount,
    required this.completedActivities,
  });

  static MapTopicData fromTopic(CourseTopicModel topic, String courseId) {
    return MapTopicData(
      id: topic.uuid,
      title: topic.title,
      description: topic.description,
      courseId: courseId,
      imageUrl: topic.imageUrl,
      activityCount: topic.activityIds.length,
      completedActivities: 0, // TODO: Implement actual completion tracking
    );
  }
}
