import 'package:fluffychat/pangea/course_plans/course_plans_repo.dart';

void main() async {
  // Example of how to use the new CoursesRepo
  final coursesRepo = CoursesRepo(
    accessToken: 'your-access-token-here',
  );

  try {
    // Find courses with pagination
    final courses = await coursesRepo.find(page: 1, limit: 10);
    print('Found ${courses.docs.length} courses');

    // Find a specific course by ID (example)
    if (courses.docs.isNotEmpty) {
      final firstCourseId = courses.docs.first.id;
      final course = await coursesRepo.findById(firstCourseId);
      print('Found course: ${course.title}');

      // Update the course
      final updatedCourse = await coursesRepo.update(firstCourseId, {
        'title': 'Updated Title',
      });
      print('Updated course: ${updatedCourse.title}');

      // Create a new course
      final newCourse = await coursesRepo.create({
        'title': 'New Course',
        'description': 'A new course description',
        'cefrLevel': 'A1',
        'l1': 'en',
        'l2': 'es',
      });
      print('Created course: ${newCourse.title}');

      // Delete a course
      final deletedCourse = await coursesRepo.deleteCourse(newCourse.id);
      print('Deleted course: ${deletedCourse.title}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
