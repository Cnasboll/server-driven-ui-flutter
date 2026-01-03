import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

part 'screen_state.dart';

/// Cubit for managing screen-level state following the BLoC pattern.
///
/// This wraps the existing StatefulWidget screen state to demonstrate
/// BLoC architecture without breaking existing functionality.
///
/// States:
/// - [ScreenLoading]: Screen is loading/resolving YAML
/// - [ScreenLoaded]: Screen successfully rendered
/// - [ScreenError]: Error occurred during loading
class ScreenCubit extends Cubit<ScreenState> {
  ScreenCubit() : super(const ScreenLoading());

  void setLoading() {
    emit(const ScreenLoading());
  }

  void setLoaded() {
    emit(const ScreenLoaded());
  }

  void setError(String message) {
    emit(ScreenError(message));
  }
}
