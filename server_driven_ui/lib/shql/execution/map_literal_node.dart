import 'package:server_driven_ui/shql/engine/cancellation_token.dart';
import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/execution_node.dart';
import 'package:server_driven_ui/shql/execution/lazy_execution_node.dart';
import 'package:server_driven_ui/shql/execution/operators/objects/colon_execution_node.dart';
import 'package:server_driven_ui/shql/execution/runtime/execution.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';

class MapLiteralNode extends LazyExecutionNode {
  List<NameValuePairExecutionNode>? children;

  MapLiteralNode(super.node, {required super.thread, required super.scope});

  @override
  Future<TickResult> doTick(
    Execution execution,
    CancellationToken? cancellationToken,
  ) async {
    if (children == null) {
      List<NameValuePairExecutionNode> r = [];
      for (var child in node.children.reversed) {
        if (child.symbol != Symbols.colon) {
          error = 'Map literal children must be name-value pairs.';
          return TickResult.completed;
        }
        NameValuePairExecutionNode? executionNode =
            Engine.tryCreateNameValuePairExecutionNode(child, thread, scope);
        if (executionNode == null) {
          error = 'Failed to create execution node for child node.';
          return TickResult.completed;
        }

        r.add(executionNode);
      }
      children = r.reversed.toList();
      return TickResult.delegated;
    }
    Map<dynamic, dynamic> map = {};
    for (var child in children!) {
      map[child.lhs!.result] = child.rhs!.result;
    }
    result = map;
    return TickResult.completed;
  }
}
