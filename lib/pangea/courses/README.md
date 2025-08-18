# PayloadCMS Client

A comprehensive Dart client for interacting with [PayloadCMS](https://payloadcms.com/) REST API. This client provides a clean, type-safe interface for all PayloadCMS operations with built-in error handling and caching support.

## Official PayloadCMS Documentation

- [PayloadCMS REST API Documentation](https://payloadcms.com/docs/rest-api/overview)
- [Collection Operations](https://payloadcms.com/docs/rest-api/collections)
- [Global Operations](https://payloadcms.com/docs/rest-api/globals)
- [Authentication](https://payloadcms.com/docs/authentication/overview)
- [Querying & Pagination](https://payloadcms.com/docs/queries/overview)

## PayloadClient Features

The `PayloadClient` class provides a complete HTTP client specifically designed for PayloadCMS:

- 🚀 **Full REST API Support** - GET, POST, PUT, DELETE operations
- 📄 **Built-in Pagination** - Handles PayloadCMS pagination automatically
- 🔒 **Authentication Ready** - Support for JWT tokens and API keys
- 🛡️ **Error Handling** - Comprehensive error handling with Sentry integration
- 📝 **Type Safety** - Full TypeScript-style error checking
- 🏗️ **Environment Integration** - Automatically uses CMS API URL from environment config
- 🧹 **Resource Management** - Proper disposal of HTTP resources

## Quick Start

```dart
import 'package:fluffychat/pangea/payloadcms_client/payload_client.dart';

final client = PayloadClient();

// Get all documents from a collection
final response = await client.get('/api/courses');
print('Found ${response['docs'].length} courses');

// Create a new document
final newDocument = await client.post('/api/courses', {
  'title': 'Advanced Spanish',
  'language': 'en',
  'targetLanguage': 'es',
  'level': 'advanced',
});

// Update a document
final updatedDocument = await client.put('/api/courses/123', {
  'title': 'Updated Course Title',
});

// Delete a document
await client.delete('/api/courses/123');

// Don't forget to dispose when done
client.dispose();
```

## Type-Safe Query System

The PayloadCMS client includes a comprehensive type-safe query system that provides compile-time safety and better developer experience:

```dart
// Build queries using the fluent query builder
final query = client.queryBuilder()
  .equals('language', 'en')
  .contains('title', 'spanish')
  .inList('level', ['beginner', 'intermediate'])
  .greaterThan('createdAt', '2023-01-01T00:00:00.000Z')
  .sortDescending('updatedAt')
  .selectFields(['id', 'title', 'description', 'level'])
  .populateFields(['author', 'category'])
  .paginate(1, 10)
  .build();

// Execute the typed query
final response = await client.getWithQuery('/api/courses', query);

// Or use with pagination specifically
final paginatedResponse = await client.getPaginatedWithQuery('/api/courses', query);
```

### Query Operators

All PayloadCMS operators are supported with type safety:

```dart
final query = client.queryBuilder()
  // Comparison operators
  .equals('field', 'value')
  .notEquals('field', 'value')
  .greaterThan('date', '2023-01-01')
  .lessThan('date', '2024-01-01')
  
  // Text operators
  .contains('title', 'search term')
  .like('description', 'pattern')
  
  // Array operators
  .inList('level', ['beginner', 'intermediate'])
  .notIn('status', ['draft', 'archived'])
  
  // Existence operators
  .exists('description', true)
  .build();
```

### Complex Conditions (OR/AND)

Build complex logical conditions:

```dart
// OR conditions
final orQuery = client.queryBuilder()
  .whereOr([
    FieldCondition(field: 'level', operator: PayloadOperator.equals, value: 'beginner'),
    FieldCondition(field: 'level', operator: PayloadOperator.equals, value: 'advanced'),
  ])
  .build();

// AND conditions
final andQuery = client.queryBuilder()
  .whereAnd([
    FieldCondition(field: 'language', operator: PayloadOperator.equals, value: 'en'),
    FieldCondition(field: 'status', operator: PayloadOperator.notEquals, value: 'draft'),
  ])
  .build();

// Mixed complex conditions
final complexQuery = client.queryBuilder()
  .equals('language', 'en')
  .whereOr([
    FieldCondition(field: 'level', operator: PayloadOperator.equals, value: 'intermediate'),
    FieldCondition(field: 'level', operator: PayloadOperator.equals, value: 'advanced'),
  ])
  .greaterThan('createdAt', '2023-01-01')
  .build();
```

### Relationship Population and Field Selection

```dart
final query = client.queryBuilder()
  // Select only specific fields
  .selectFields(['id', 'title', 'author.name', 'category.title'])
  
  // Populate relationships
  .populateFields(['author', 'category', 'tags'])
  
  // Control population depth
  .withDepth(2)
  
  .build();
```

### Query Reusability

Create reusable query templates:

```dart
PayloadQuery createBaseQuery({String? language, List<String>? levels}) {
  final builder = client.queryBuilder()
    .notEquals('status', 'draft')
    .exists('title', true)
    .sortDescending('updatedAt');
  
  if (language != null) builder.equals('language', language);
  if (levels != null) builder.inList('level', levels);
  
  return builder.build();
}

// Use the template
final englishCourses = createBaseQuery(
  language: 'en', 
  levels: ['beginner', 'intermediate']
);

final spanishCourses = createBaseQuery(
  language: 'es',
  levels: ['advanced']
);
```

## Pagination Support

PayloadCMS uses pagination for large datasets. The client provides both traditional and type-safe methods for paginated requests:

### Traditional Pagination

```dart
// Get paginated results with query parameters
final paginatedResponse = await client.getPaginated(
  '/api/courses',
  page: 1,
  limit: 10,
  queryParams: {
    'where[level][equals]': 'beginner',
    'where[language][equals]': 'en',
    'sort': '-createdAt',
  },
);

print('Total documents: ${paginatedResponse['totalDocs']}');
print('Current page: ${paginatedResponse['page']}');
print('Has next page: ${paginatedResponse['hasNextPage']}');
```

### Type-Safe Pagination

```dart
// Build type-safe paginated query
final query = client.queryBuilder()
  .equals('level', 'beginner')
  .equals('language', 'en')
  .sortDescending('createdAt')
  .paginate(1, 10) // Built-in pagination
  .build();

final response = await client.getPaginatedWithQuery('/api/courses', query);
```

## Advanced Querying

The client supports all PayloadCMS query operators. Here are some examples:

```dart
// Complex where conditions
final queryParams = {
  // Equals
  'where[level][equals]': 'intermediate',
  
  // Not equals
  'where[status][not_equals]': 'draft',
  
  // Greater than
  'where[createdAt][greater_than]': '2023-01-01',
  
  // In array
  'where[language][in]': 'en,es,fr',
  
  // Contains (for text fields)
  'where[title][contains]': 'spanish',
  
  // And/Or operators
  'where[or][0][level][equals]': 'beginner',
  'where[or][1][level][equals]': 'intermediate',
  
  // Sorting
  'sort': '-updatedAt', // Descending by updatedAt
  
  // Limit fields returned
  'select': 'title,description,level',
  
  // Population/relationships
  'populate': 'author,category',
};

final response = await client.getPaginated(
  '/api/courses',
  queryParams: queryParams,
);
```

## Working with Relationships

PayloadCMS supports complex relationships between collections:

```dart
// Populate related documents
final courseWithAuthor = await client.get('/api/courses/123?populate=author');

// Deep population
final deepPopulated = await client.get(
  '/api/courses/123?populate=author,category.parent'
);

// Limit populated fields
final limitedPopulation = await client.get(
  '/api/courses/123?populate=author&select=title,author.name,author.email'
);
```

## Authentication

If your PayloadCMS instance requires authentication:

```dart
// The client automatically uses environment configuration
// Make sure your Environment.cmsApi includes auth tokens if needed

// For manual token management, you can extend the client
class AuthenticatedPayloadClient extends PayloadClient {
  String? _authToken;
  
  void setAuthToken(String token) {
    _authToken = token;
  }
  
  @override
  Map<String, String> get _headers => {
    ...super._headers,
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };
}
```

## Error Handling

The client provides comprehensive error handling:

```dart
try {
  final response = await client.get('/api/courses');
  // Handle success
} on http.ClientException catch (e) {
  // Handle HTTP errors (4xx, 5xx)
  print('HTTP Error: $e');
} catch (e) {
  // Handle other errors (network, parsing, etc.)
  print('Error: $e');
}
```

## Configuration

Ensure your environment configuration includes the CMS API URL:

```dart
// In your environment.dart file
static String get cmsApi {
  final envEntry = appConfigOverride?.cmsApi ?? dotenv.env['CMS_API'];
  if (envEntry == null) {
    return "Not found";
  }
  return envEntry;
}
```

## Best Practices

### 1. Resource Management
Always dispose of the client when done:

```dart
final client = PayloadClient();
try {
  // Use client...
} finally {
  client.dispose();
}
```

### 2. Error Handling
Handle errors gracefully:

```dart
Future<Map<String, dynamic>?> safeGet(String endpoint) async {
  try {
    return await client.get(endpoint);
  } catch (e) {
    logger.error('Failed to fetch $endpoint: $e');
    return null;
  }
}
```

### 3. Caching
For frequently accessed data, consider implementing caching (see `CoursesRepo` as an example):

```dart
class CachedPayloadClient {
  final PayloadClient _client = PayloadClient();
  final Map<String, dynamic> _cache = {};
  
  Future<Map<String, dynamic>> getCached(String endpoint) async {
    if (_cache.containsKey(endpoint)) {
      return _cache[endpoint];
    }
    
    final result = await _client.get(endpoint);
    _cache[endpoint] = result;
    return result;
  }
}
```

## Example Implementation: CoursesRepo

This package includes `CoursesRepo` as a real-world example of how to build a repository pattern around the PayloadClient:

```dart
import 'package:fluffychat/pangea/courses/courses.dart';

// High-level repository with caching
final coursesResponse = await CoursesRepo.getCourses(
  page: 1,
  limit: 10,
  language: 'en',
  targetLanguage: 'es',
);
```

See the `CoursesRepo` class and models for a complete implementation example.

## Testing

The package includes comprehensive tests:

```bash
# Run the tests
flutter test lib/pangea/courses/courses_test.dart
```

## API Reference

### PayloadClient Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `get(endpoint)` | GET request | `endpoint`: API endpoint path |
| `post(endpoint, data)` | POST request | `endpoint`: API path, `data`: JSON data |
| `put(endpoint, data)` | PUT request | `endpoint`: API path, `data`: JSON data |
| `delete(endpoint)` | DELETE request | `endpoint`: API endpoint path |
| `getPaginated(endpoint, ...)` | Paginated GET | `endpoint`, `page`, `limit`, `queryParams` |
| `dispose()` | Clean up resources | None |

### Environment Configuration

| Property | Description | Required |
|----------|-------------|----------|
| `Environment.cmsApi` | PayloadCMS API base URL | Yes |

## Contributing

When extending this client:

1. Follow the existing error handling patterns
2. Add comprehensive tests for new features
3. Update documentation
4. Use proper TypeScript-style type checking
5. Implement proper resource disposal

## Links

- [PayloadCMS Official Website](https://payloadcms.com/)
- [PayloadCMS GitHub](https://github.com/payloadcms/payload)
- [REST API Documentation](https://payloadcms.com/docs/rest-api/overview)
- [Query Documentation](https://payloadcms.com/docs/queries/overview)
