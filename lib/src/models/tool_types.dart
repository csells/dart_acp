/// Tool call related types for ACP.

/// Tool call status.
enum ToolCallStatus {
  /// Tool call has started.
  started,

  /// Tool call is in progress.
  progress,

  /// Tool call completed successfully.
  completed,

  /// Tool call encountered an error.
  error,

  /// Tool call was cancelled.
  cancelled;

  /// Parse from wire format.
  static ToolCallStatus fromWire(String? value) {
    switch (value) {
      case 'started':
        return ToolCallStatus.started;
      case 'progress':
        return ToolCallStatus.progress;
      case 'completed':
        return ToolCallStatus.completed;
      case 'error':
        return ToolCallStatus.error;
      case 'cancelled':
        return ToolCallStatus.cancelled;
      default:
        return ToolCallStatus.error;
    }
  }

  /// Convert to wire format.
  String toWire() => name;
}

/// Tool call information.
class ToolCall {
  /// Creates a tool call.
  const ToolCall({
    required this.id,
    required this.status,
    this.name,
    this.title,
    this.kind,
    this.params,
    this.result,
    this.error,
    this.message,
    this.locations,
    this.rawInput,
    this.rawOutput,
  });

  /// Create from JSON.
  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
    id: json['id'] as String? ?? '',
    status: ToolCallStatus.fromWire(json['status'] as String?),
    name: json['name'] as String?,
    title: json['title'] as String?,
    kind: json['kind'] as String?,
    params: json['params'] as Map<String, dynamic>?,
    result: json['result'],
    error: json['error'] as Map<String, dynamic>?,
    message: json['message'] as String?,
    locations: (json['locations'] as List?)
        ?.map((e) => (e as Map).cast<String, dynamic>())
        .toList(),
    rawInput: json['raw_input'],
    rawOutput: json['raw_output'],
  );

  /// Unique identifier for this tool call.
  final String id;

  /// Current status of the tool call.
  final ToolCallStatus status;

  /// Name of the tool being called.
  final String? name;

  /// Human‑readable title for the tool call (if provided by agent).
  final String? title;

  /// Kind of tool (read, edit, delete, move, search, execute, think, fetch,
  /// other).
  final String? kind;

  /// Parameters passed to the tool (agent-specific structure).
  final Map<String, dynamic>? params;

  /// Result of the tool call (when completed).
  final dynamic result;

  /// Error information (when status is error).
  final Map<String, dynamic>? error;

  /// Progress message (when status is progress).
  final String? message;

  /// Optional locations related to the tool (paths/URIs), agent-specific shape.
  final List<Map<String, dynamic>>? locations;

  /// Optional raw input payload reported by the agent.
  final dynamic rawInput;

  /// Optional raw output payload reported by the agent.
  final dynamic rawOutput;

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.toWire(),
    if (name != null) 'name': name,
    if (title != null) 'title': title,
    if (kind != null) 'kind': kind,
    if (params != null) 'params': params,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
    if (message != null) 'message': message,
    if (locations != null) 'locations': locations,
    if (rawInput != null) 'raw_input': rawInput,
    if (rawOutput != null) 'raw_output': rawOutput,
  };
}
