/// Type-safe query builder for PayloadCMS REST API
/// Based on PayloadCMS query operators and structure
library;

/// Comparison operators for where conditions
enum PayloadOperator {
  equals('equals'),
  notEquals('not_equals'),
  greaterThan('greater_than'),
  greaterThanEqual('greater_than_equal'),
  lessThan('less_than'),
  lessThanEqual('less_than_equal'),
  like('like'),
  contains('contains'),
  inList('in'),
  notIn('not_in'),
  exists('exists'),
  near('near');

  const PayloadOperator(this.value);
  final String value;
}

/// Sort direction for ordering results
enum SortDirection {
  ascending(''),
  descending('-');

  const SortDirection(this.prefix);
  final String prefix;
}

/// Base interface for all query conditions
abstract class PayloadQueryCondition {
  Map<String, dynamic> toQueryParams();
}

/// Simple field condition
class FieldCondition implements PayloadQueryCondition {
  final String field;
  final PayloadOperator operator;
  final dynamic value;

  const FieldCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  @override
  Map<String, dynamic> toQueryParams() {
    return {
      'where[$field][${operator.value}]': _formatValue(value),
    };
  }

  String _formatValue(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).join(',');
    }
    return value.toString();
  }
}

/// OR condition combining multiple conditions
class OrCondition implements PayloadQueryCondition {
  final List<PayloadQueryCondition> conditions;

  const OrCondition(this.conditions);

  @override
  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    for (int i = 0; i < conditions.length; i++) {
      final conditionParams = conditions[i].toQueryParams();
      for (final entry in conditionParams.entries) {
        // Convert where[field][op] to where[or][index][field][op]
        final whereKey = entry.key;
        if (whereKey.startsWith('where[') && whereKey.endsWith(']')) {
          final innerPart = whereKey.substring(6, whereKey.length - 1);
          params['where[or][$i][$innerPart]'] = entry.value;
        }
      }
    }
    return params;
  }
}

/// AND condition combining multiple conditions
class AndCondition implements PayloadQueryCondition {
  final List<PayloadQueryCondition> conditions;

  const AndCondition(this.conditions);

  @override
  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    for (int i = 0; i < conditions.length; i++) {
      final conditionParams = conditions[i].toQueryParams();
      for (final entry in conditionParams.entries) {
        // Convert where[field][op] to where[and][index][field][op]
        final whereKey = entry.key;
        if (whereKey.startsWith('where[') && whereKey.endsWith(']')) {
          final innerPart = whereKey.substring(6, whereKey.length - 1);
          params['where[and][$i][$innerPart]'] = entry.value;
        }
      }
    }
    return params;
  }
}

/// Sort configuration
class PayloadSort {
  final String field;
  final SortDirection direction;

  const PayloadSort({
    required this.field,
    this.direction = SortDirection.ascending,
  });

  String toSortString() {
    return '${direction.prefix}$field';
  }
}

/// Complete query configuration
class PayloadQuery {
  final List<PayloadQueryCondition> conditions;
  final List<PayloadSort> sorts;
  final List<String>? select;
  final List<String>? populate;
  final int? page;
  final int? limit;
  final int? depth;

  const PayloadQuery({
    this.conditions = const [],
    this.sorts = const [],
    this.select,
    this.populate,
    this.page,
    this.limit,
    this.depth,
  });

  /// Convert to query parameters map
  Map<String, String> toQueryParams() {
    final params = <String, String>{};

    // Add where conditions
    for (final condition in conditions) {
      final conditionParams = condition.toQueryParams();
      for (final entry in conditionParams.entries) {
        params[entry.key] = entry.value.toString();
      }
    }

    // Add sorting
    if (sorts.isNotEmpty) {
      params['sort'] = sorts.map((s) => s.toSortString()).join(',');
    }

    // Add field selection
    if (select != null && select!.isNotEmpty) {
      params['select'] = select!.join(',');
    }

    // Add population
    if (populate != null && populate!.isNotEmpty) {
      params['populate'] = populate!.join(',');
    }

    // Add pagination
    if (page != null) {
      params['page'] = page.toString();
    }
    if (limit != null) {
      params['limit'] = limit.toString();
    }
    if (depth != null) {
      params['depth'] = depth.toString();
    }

    return params;
  }

  /// Create a copy with modified parameters
  PayloadQuery copyWith({
    List<PayloadQueryCondition>? conditions,
    List<PayloadSort>? sorts,
    List<String>? select,
    List<String>? populate,
    int? page,
    int? limit,
    int? depth,
  }) {
    return PayloadQuery(
      conditions: conditions ?? this.conditions,
      sorts: sorts ?? this.sorts,
      select: select ?? this.select,
      populate: populate ?? this.populate,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      depth: depth ?? this.depth,
    );
  }
}

/// Fluent query builder for creating PayloadQuery instances
class PayloadQueryBuilder {
  List<PayloadQueryCondition> _conditions = [];
  List<PayloadSort> _sorts = [];
  List<String>? _select;
  List<String>? _populate;
  int? _page;
  int? _limit;
  int? _depth;

  /// Add a where condition
  PayloadQueryBuilder where(
    String field,
    PayloadOperator operator,
    dynamic value,
  ) {
    _conditions.add(
      FieldCondition(
        field: field,
        operator: operator,
        value: value,
      ),
    );
    return this;
  }

  /// Add multiple conditions with OR logic
  PayloadQueryBuilder whereOr(List<PayloadQueryCondition> conditions) {
    _conditions.add(OrCondition(conditions));
    return this;
  }

  /// Add multiple conditions with AND logic
  PayloadQueryBuilder whereAnd(List<PayloadQueryCondition> conditions) {
    _conditions.add(AndCondition(conditions));
    return this;
  }

  /// Convenience methods for common operators
  PayloadQueryBuilder equals(String field, dynamic value) =>
      where(field, PayloadOperator.equals, value);

  PayloadQueryBuilder notEquals(String field, dynamic value) =>
      where(field, PayloadOperator.notEquals, value);

  PayloadQueryBuilder greaterThan(String field, dynamic value) =>
      where(field, PayloadOperator.greaterThan, value);

  PayloadQueryBuilder lessThan(String field, dynamic value) =>
      where(field, PayloadOperator.lessThan, value);

  PayloadQueryBuilder contains(String field, String value) =>
      where(field, PayloadOperator.contains, value);

  PayloadQueryBuilder inList(String field, List<dynamic> values) =>
      where(field, PayloadOperator.inList, values);

  PayloadQueryBuilder exists(String field, bool exists) =>
      where(field, PayloadOperator.exists, exists);

  /// Add sorting
  PayloadQueryBuilder sortBy(String field,
      [SortDirection direction = SortDirection.ascending]) {
    _sorts.add(PayloadSort(field: field, direction: direction));
    return this;
  }

  PayloadQueryBuilder sortAscending(String field) =>
      sortBy(field, SortDirection.ascending);

  PayloadQueryBuilder sortDescending(String field) =>
      sortBy(field, SortDirection.descending);

  /// Select specific fields
  PayloadQueryBuilder selectFields(List<String> fields) {
    _select = fields;
    return this;
  }

  /// Populate relationships
  PayloadQueryBuilder populateFields(List<String> fields) {
    _populate = fields;
    return this;
  }

  /// Set pagination
  PayloadQueryBuilder paginate(int page, int limit) {
    _page = page;
    _limit = limit;
    return this;
  }

  /// Set depth for relationships
  PayloadQueryBuilder withDepth(int depth) {
    _depth = depth;
    return this;
  }

  /// Build the final query
  PayloadQuery build() {
    return PayloadQuery(
      conditions: List.from(_conditions),
      sorts: List.from(_sorts),
      select: _select != null ? List.from(_select!) : null,
      populate: _populate != null ? List.from(_populate!) : null,
      page: _page,
      limit: _limit,
      depth: _depth,
    );
  }

  /// Reset the builder
  PayloadQueryBuilder reset() {
    _conditions = [];
    _sorts = [];
    _select = null;
    _populate = null;
    _page = null;
    _limit = null;
    _depth = null;
    return this;
  }
}
