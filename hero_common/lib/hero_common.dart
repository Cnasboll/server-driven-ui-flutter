/// Shared domain logic for the Herodex superhero application.
library hero_common;

// Amendable field system
export 'amendable/amendable.dart';
export 'amendable/field.dart';
export 'amendable/field_base.dart';
export 'amendable/field_provider.dart';
export 'amendable/parsing_context.dart';

// Callbacks
export 'callbacks.dart';

// Environment / API configuration
export 'env/env.dart';

// Job queue
export 'jobs/job_queue.dart';

// Managers
export 'managers/hero_data_manager.dart';
export 'managers/hero_data_managing.dart';

// Models
export 'models/appearance_model.dart';
export 'models/biography_model.dart';
export 'models/connections_model.dart';
export 'models/hero_model.dart';
export 'models/image_model.dart';
export 'models/power_stats_model.dart';
export 'models/search_response_model.dart';
export 'models/work_model.dart';

// Persistence
export 'persistence/hero_repositing.dart';
export 'persistence/hero_repository.dart';

// Predicates
export 'predicates/hero_predicate.dart';

// Services
export 'services/hero_service.dart';
export 'services/hero_servicing.dart';

// SHQL™ engine (re-exported from shql package)
export 'package:shql/engine/engine.dart';
export 'package:shql/execution/runtime/runtime.dart' show Runtime;
export 'package:shql/parser/constants_set.dart';
export 'package:shql/parser/parse_tree.dart';
export 'package:shql/parser/parser.dart';
export 'package:shql/tokenizer/tokenizer.dart';

// SHQL™ adapter
export 'models/hero_shql_adapter.dart';

// Utilities
export 'utils/ascii_art.dart';
export 'utils/enum_parsing.dart';
export 'utils/json_parsing.dart';

// Value types
export 'value_types/conflict_resolver.dart';
export 'value_types/height.dart';
export 'value_types/percentage.dart';
export 'value_types/value_type.dart';
export 'value_types/weight.dart';
