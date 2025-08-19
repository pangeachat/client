import 'course_plans_repo.dart';

/// Test script to run the courses repository with full CRUD operations
Future<void> main(List<String> args) async {
  print('Running CoursesRepo CRUD test...\n');

  // Parse command line arguments for access token
  String? accessToken;
  String? baseUrl;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '-t' && i + 1 < args.length) {
      accessToken = args[i + 1];
      continue;
    }
    if (args[i] == '-b' && i + 1 < args.length) {
      baseUrl = args[i + 1];
      continue;
    }
  }

  if (accessToken == null) {
    print('Error: Access token is required. Use -t <token> to provide it.');
    print(
      'Usage: dart run lib/pangea/courses/run_courses_repo.dart -t <access_token>',
    );
    return;
  }

  if (baseUrl == null) {
    print('Error: Base URL is required. Use -b <url> to provide it.');
    print(
      'Usage: dart run lib/pangea/courses/run_courses_repo.dart -t <access_token> -b <base_url>',
    );
    return;
  }

  // Initialize CoursesRepo
  print('🔧 Initializing CoursesRepo with access token...');
  final coursesRepo = CoursesRepo(
    accessToken: accessToken,
    baseUrl: baseUrl,
    baseApiPath: "/cms/api",
  );
  print('✅ CoursesRepo initialized\n');

  String? testCourseId;

  try {
    // Test 1: CREATE - Create a new course
    print('📝 CREATE TEST - Creating a new course...');
    final newCourseData = {
      'title': 'Test Course ${DateTime.now().millisecondsSinceEpoch}',
      'description': 'This is a test course created by the CRUD test script',
      'cefrLevel': 'A1',
      'l1': 'en',
      'l2': 'es',
    };

    try {
      final createdCourse = await coursesRepo.create(newCourseData);
      testCourseId = createdCourse.id;
      print('✅ Course created successfully!');
      print('   ID: ${createdCourse.id}');
      print('   Title: ${createdCourse.title}');
      print('   Description: ${createdCourse.description}');
      print('   CEFR Level: ${createdCourse.cefrLevel.value}');
      print('   Languages: ${createdCourse.l1} → ${createdCourse.l2}');
      print('   Created at: ${createdCourse.createdAt}');
    } catch (e) {
      print('❌ Create test failed: $e');
    }

    print('\n${'─' * 50}\n');

    // Test 2: READ (Find All) - Get courses with pagination
    print('📖 READ TEST (Find All) - Fetching courses with pagination...');
    try {
      final coursesResponse = await coursesRepo.find(page: 1, limit: 5);
      print('✅ Find method executed successfully!');
      print('   Total docs: ${coursesResponse.totalDocs}');
      print('   Current page: ${coursesResponse.page}');
      print('   Limit: ${coursesResponse.limit}');
      print('   Total pages: ${coursesResponse.totalPages}');
      print('   Has next page: ${coursesResponse.hasNextPage}');
      print('   Has prev page: ${coursesResponse.hasPrevPage}');
      print('   Courses found: ${coursesResponse.docs.length}');

      if (coursesResponse.docs.isNotEmpty) {
        print('   📚 Course list:');
        for (int i = 0; i < coursesResponse.docs.length; i++) {
          final course = coursesResponse.docs[i];
          print(
            '     ${i + 1}. "${course.title}" (${course.l1} → ${course.l2}) - ${course.cefrLevel.value}',
          );
        }
      }
    } catch (e) {
      print('❌ Find test failed: $e');
    }

    print('\n${'─' * 50}\n');

    // Test 3: READ (Find By ID) - Get specific course by ID
    if (testCourseId != null) {
      print('🔍 READ TEST (Find By ID) - Fetching course by ID...');
      try {
        final course = await coursesRepo.findById(testCourseId);
        print('✅ FindById method executed successfully!');
        print('   ID: ${course.id}');
        print('   Title: ${course.title}');
        print('   Description: ${course.description}');
        print('   CEFR Level: ${course.cefrLevel.value}');
        print('   Languages: ${course.l1} → ${course.l2}');
        print('   Modules: ${course.coursePlanModules.docs.length} items');
        print('   Created at: ${course.createdAt}');
        print('   Updated at: ${course.updatedAt}');
        if (course.createdBy != null) {
          print(
            '   Created by: ${course.createdBy!.relationTo}:${course.createdBy!.value}',
          );
        }
        if (course.updatedBy != null) {
          print(
            '   Updated by: ${course.updatedBy!.relationTo}:${course.updatedBy!.value}',
          );
        }
      } catch (e) {
        print('❌ FindById test failed: $e');
      }
    } else {
      print('⚠️ Skipping FindById test - no test course ID available');
    }

    print('\n${'─' * 50}\n');

    // Test 4: UPDATE - Update the created course
    if (testCourseId != null) {
      print('📝 UPDATE TEST - Updating the created course...');
      final updateData = {
        'title': 'Updated Test Course ${DateTime.now().millisecondsSinceEpoch}',
        'description': 'This course has been updated by the CRUD test script',
        'cefrLevel': 'A2',
      };

      try {
        final updatedCourse =
            await coursesRepo.update(testCourseId, updateData);
        print('✅ Course updated successfully!');
        print('   ID: ${updatedCourse.id}');
        print('   New Title: ${updatedCourse.title}');
        print('   New Description: ${updatedCourse.description}');
        print('   New CEFR Level: ${updatedCourse.cefrLevel.value}');
        print('   Languages: ${updatedCourse.l1} → ${updatedCourse.l2}');
        print('   Updated at: ${updatedCourse.updatedAt}');
      } catch (e) {
        print('❌ Update test failed: $e');
      }
    } else {
      print('⚠️ Skipping Update test - no test course ID available');
    }

    print('\n${'─' * 50}\n');

    // Test 5: DELETE - Delete the created course
    if (testCourseId != null) {
      print('🗑️ DELETE TEST - Deleting the created course...');
      try {
        final deletedCourse = await coursesRepo.deleteCourse(testCourseId);
        print('✅ Course deleted successfully!');
        print('   Deleted course ID: ${deletedCourse.id}');
        print('   Deleted course title: ${deletedCourse.title}');

        // Verify deletion by trying to fetch the course
        print('🔍 Verifying deletion...');
        try {
          await coursesRepo.findById(testCourseId);
          print('⚠️ Warning: Course still exists after deletion');
        } catch (e) {
          print(
            '✅ Confirmed: Course no longer exists (expected error: ${e.toString().substring(0, 50)}...)',
          );
        }
      } catch (e) {
        print('❌ Delete test failed: $e');
      }
    } else {
      print('⚠️ Skipping Delete test - no test course ID available');
    }
  } catch (e, stackTrace) {
    print('❌ Unexpected error during CRUD tests: $e');
    print('Stack trace: $stackTrace');
  }

  print('\n${'=' * 50}');
  print('🎯 CRUD test completed!');
  print('=' * 50);
}
