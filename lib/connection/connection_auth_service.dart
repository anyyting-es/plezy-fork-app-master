import 'connection.dart';

abstract class ConnectionAuthService {
  Future<bool> validate(Connection connection);
  Future<Connection> refresh(Connection connection);
  Future<void> signOut(Connection connection);
}
