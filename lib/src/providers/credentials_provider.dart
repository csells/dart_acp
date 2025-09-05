abstract class CredentialsProvider {
  /// Return opaque params to send to `authenticate` for a given method id.
  Future<Map<String, Object?>> getCredentials(String methodId);
}
