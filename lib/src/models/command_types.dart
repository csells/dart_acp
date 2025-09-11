/// Command and plan types for ACP.

/// Available command that can be executed.
class AvailableCommand {
  /// Creates an available command.
  const AvailableCommand({
    required this.name,
    this.description,
    this.parameters,
  });

  /// Create from JSON.
  factory AvailableCommand.fromJson(Map<String, dynamic> json) =>
      AvailableCommand(
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        parameters: json['parameters'] as Map<String, dynamic>?,
      );

  /// Name/identifier of the command.
  final String name;

  /// Human-readable description.
  final String? description;

  /// Parameters for the command (agent-specific).
  final Map<String, dynamic>? parameters;

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (parameters != null) 'parameters': parameters,
  };
}

/// A block in an execution plan.
class PlanBlock {
  /// Creates a plan block.
  const PlanBlock({
    required this.id,
    required this.content,
    this.status,
    this.metadata,
  });

  /// Create from JSON.
  factory PlanBlock.fromJson(Map<String, dynamic> json) => PlanBlock(
    id: json['id'] as String? ?? '',
    content: json['content'] as String? ?? '',
    status: json['status'] as String?,
    metadata: json['metadata'] as Map<String, dynamic>?,
  );

  /// Unique identifier for this block.
  final String id;

  /// Content/description of this plan step.
  final String content;

  /// Status of this block (pending, in_progress, completed).
  final String? status;

  /// Additional metadata (agent-specific).
  final Map<String, dynamic>? metadata;

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    if (status != null) 'status': status,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Execution plan with structured blocks.
class Plan {
  /// Creates a plan.
  const Plan({
    required this.blocks,
    this.title,
    this.description,
    this.metadata,
  });

  /// Create from JSON.
  factory Plan.fromJson(Map<String, dynamic> json) {
    final blocksList =
        (json['blocks'] as List?)
            ?.map((b) => PlanBlock.fromJson(b as Map<String, dynamic>))
            .toList() ??
        const [];

    return Plan(
      blocks: blocksList,
      title: json['title'] as String?,
      description: json['description'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// List of plan blocks/steps.
  final List<PlanBlock> blocks;

  /// Title of the plan.
  final String? title;

  /// Overall description.
  final String? description;

  /// Additional metadata (agent-specific).
  final Map<String, dynamic>? metadata;

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (metadata != null) 'metadata': metadata,
  };
}
