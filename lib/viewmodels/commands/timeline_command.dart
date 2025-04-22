abstract class TimelineCommand {
  Future<void> execute();
  Future<void> undo();
}
