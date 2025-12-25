part of 'screen_cubit.dart';

/// Base state for screen loading lifecycle
sealed class ScreenState extends Equatable {
  const ScreenState();

  @override
  List<Object?> get props => [];
}

/// Screen is currently loading/resolving
final class ScreenLoading extends ScreenState {
  const ScreenLoading();
}

/// Screen has been successfully loaded
final class ScreenLoaded extends ScreenState {
  const ScreenLoaded();
}

/// An error occurred during screen loading
final class ScreenError extends ScreenState {
  final String message;

  const ScreenError(this.message);

  @override
  List<Object?> get props => [message];
}
