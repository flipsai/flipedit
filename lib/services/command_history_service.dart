import 'package:flutter/foundation.dart';

abstract class Command {
  final Map<String, dynamic> oldState;
  final Map<String, dynamic> newState;

  Command(this.oldState, this.newState);

  void execute();
  void undo();
}

class ClipCommand extends Command {
  final Function(Map<String, dynamic>) updateFunction;

  ClipCommand(super.oldState, super.newState, this.updateFunction);

  @override
  void execute() {
    updateFunction(newState);
  }

  @override
  void undo() {
    updateFunction(oldState);
  }
}

class CommandHistoryService {
  final ValueNotifier<List<Command>> historyNotifier =
      ValueNotifier<List<Command>>([]);
  final ValueNotifier<int> positionNotifier = ValueNotifier<int>(-1);

  List<Command> get history => historyNotifier.value;
  int get position => positionNotifier.value;

  bool get canUndo => position >= 0;
  bool get canRedo => position < history.length - 1;

  void addCommand(Command command) {
    final newHistory = position >= 0 ? history.sublist(0, position + 1) : [];

    command.execute();

    historyNotifier.value = [...newHistory, command];
    positionNotifier.value = historyNotifier.value.length - 1;
  }

  void undo() {
    if (!canUndo) return;

    final command = history[position];
    command.undo();
    positionNotifier.value = position - 1;
  }

  void redo() {
    if (!canRedo) return;

    final command = history[position + 1];
    command.execute();
    positionNotifier.value = position + 1;
  }

  void clear() {
    historyNotifier.value = [];
    positionNotifier.value = -1;
  }
}
