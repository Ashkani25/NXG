import '../storage/local_store.dart';
import 'profile_service.dart';

/// Records the first visit to a world (World Traveler achievement: 7 worlds). Used by `/world/<id>` pages and by
/// the Social tab, which hosts Nova Gallery, Orbit Network and Social Station as sub-tabs.
void recordWorldVisit(ProfileService p, String id) {
  final LocalStore store = LocalStore.instance;
  final Set<String> visited = (store.getJsonList('hub.visited') ?? const <dynamic>[]).map((dynamic e) => '$e').toSet();
  if (visited.add(id)) {
    store.setJson('hub.visited', visited.toList());
    p.bump('worlds.visited');
    p.award('world.first_visit.$id', xp: 20, coins: 10);
  }
}
