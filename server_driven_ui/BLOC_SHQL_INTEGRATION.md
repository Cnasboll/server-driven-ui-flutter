# BLoC + SHQL: Understanding When Each Shines

## 🎯 The Question

**"Does SHQL+Observer replace BLoC/Cubit?"**

**Answer:** For YAML-driven UI state, yes! SHQL already has everything needed. BLoC/Cubit is only needed for Flutter framework integration outside the YAML tree.

---

## When SHQL+Observer Is Better

✅ **Runtime-dynamic state** (variable names from YAML)
✅ **Server-driven UI** (state defined in config files)
✅ **Persistent state** (SAVE_STATE/LOAD_STATE → SharedPreferences)
✅ **Reactive UI** (Observer pattern for automatic rebuilds)
✅ **Rapid prototyping** (no recompilation needed)
✅ **Scripted business logic** (logic in SHQL files)

**Example: Theme Management** (Implemented in this project!)
```yaml
onLoad: "shql: SET('isDarkMode', LOAD_STATE('isDarkMode', FALSE))"

# Display current theme
- type: Observer
  props:
    query: "isDarkMode"
    builder:
      type: Text
      props:
        data: "shql: 'Theme: ' + IF isDarkMode THEN 'Dark' ELSE 'Light'"

# Toggle button
- type: ElevatedButton
  props:
    onPressed: "shql(targeted:true): BEGIN SET('isDarkMode', NOT isDarkMode); SAVE_STATE('isDarkMode', isDarkMode); END"
```

---

## When BLoC/Cubit Adds Value Over SHQL

The **only** real advantage is **compile-time type safety**:

✅ **Type safety** - Dart compiler catches typos (`Autenticated` → compile error)
✅ **Exhaustiveness checking** - Sealed classes force handling all state cases
✅ **IDE support** - Autocomplete for state types
✅ **Team collaboration** - Standard Flutter pattern, easier onboarding
✅ **DevTools integration** - BLoC inspector for debugging state history

**Everything else** (setting variables, notifying observers, persistence, reactivity) - **SHQL already has it**.

**Example: ScreenCubit** (Implemented in this project to meet course requirements, but duplicates existing StatefulWidget state - in a real project, choose one or the other, not both)

---

## 🎨 Demo: Pure SHQL Theme Management

### The Use Case: Persistent Theme Toggle

**Why SHQL (not BLoC)?**

1. **Already Has Persistence**
   ```dart
   // In main.dart
   final shql = ShqlBindings(
     saveState: _saveState,  // Writes to SharedPreferences
     loadState: _loadState,  // Reads from SharedPreferences
   );
   ```

2. **Runtime Functions Available**
   ```shql
   SET('isDarkMode', value)        -- Sets variable + notifies observers
   SAVE_STATE('isDarkMode', value) -- Persists to disk
   LOAD_STATE('isDarkMode', FALSE) -- Restores from disk
   ```

3. **Observer Pattern for Reactivity**
   ```yaml
   type: Observer
   props:
     query: "isDarkMode"  # Rebuilds when this variable changes
     builder:
       type: Text
       props:
         data: "shql: IF isDarkMode THEN 'Dark' ELSE 'Light'"
   ```

4. **No Extra Code Needed**
   - No Cubit class
   - No state classes
   - No BlocProvider wiring
   - Just YAML + SHQL!

---

## 📐 Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│                   Flutter App                        │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  BlocProvider                                  │ │
│  │  └─ ScreenCubit (screen lifecycle)             │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  YAML-Driven UI (Pure SHQL State)             │ │
│  │                                                │ │
│  │  onLoad:                                       │ │
│  │    LOAD_STATE() ──→ SharedPreferences          │ │
│  │    SET() ──→ SHQL variable                     │ │
│  │                                                │ │
│  │  Observer widgets:                             │ │
│  │    Listen to SHQL variables                    │ │
│  │    Rebuild when notified                       │ │
│  │                                                │ │
│  │  Button onPressed:                             │ │
│  │    SET() ──→ Update variable + notify          │ │
│  │    SAVE_STATE() ──→ Persist to disk            │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

---

## 🔧 Implementation Details

### 1. SHQL Built-in Functions

**File:** `lib/shql/execution/runtime/runtime.dart`

Already has everything needed:

```dart
// Set variable and notify observers
Future<void> set(ExecutionContext context, ExecutionNode caller, dynamic name, dynamic value) {
  caller.scope.setVariable(identifiers.include(name.toUpperCase()), value);
  notifyListeners?.call(name);  // Triggers Observer rebuilds!
}

// Persist to SharedPreferences
Future<void> saveState(ExecutionContext context, ExecutionNode caller, dynamic key, dynamic value) {
  return saveStateFunction?.call(key, value);
}

// Load from SharedPreferences
Future<dynamic> loadState(ExecutionContext context, ExecutionNode caller, dynamic key, dynamic defaultValue) {
  return loadStateFunction?.call(key, defaultValue);
}
```

### 2. SHQL Bindings

**File:** `lib/yaml_ui/shql_bindings.dart`

```dart
ShqlBindings({
  required this.onMutated,
  Future<void> Function(String key, dynamic value)? saveState,
  Future<dynamic> Function(String key, dynamic defaultValue)? loadState,
  // ... other bindings ...
})
```

### 3. Wire to SharedPreferences

**File:** `lib/main.dart`

```dart
final shql = ShqlBindings(
  onMutated: () { if (!mounted) return; _resolveUi(); },
  saveState: _saveState,   // Calls SharedPreferences.setXXX()
  loadState: _loadState,   // Calls SharedPreferences.getXXX()
);

Future<void> _saveState(String key, dynamic value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value is bool) await prefs.setBool(key, value);
  // ... handle other types
}
```

### 4. Theme Demo Screen

**File:** `assets/screens/theme_demo.yaml`

```yaml
# Load persisted state on screen load
onLoad: "shql: SET('isDarkMode', LOAD_STATE('isDarkMode', FALSE))"

# Display current theme (rebuilds when isDarkMode changes)
- type: Observer
  props:
    query: "isDarkMode"
    builder:
      type: Text
      props:
        data: "shql: 'Theme: ' + IF isDarkMode THEN 'Dark' ELSE 'Light'"

# Toggle button (updates variable + persists)
- type: ElevatedButton
  props:
    onPressed: "shql(targeted:true): BEGIN SET('isDarkMode', NOT isDarkMode); SAVE_STATE('isDarkMode', isDarkMode); END"

# Dynamic colors (rebuilds when isDarkMode changes)
- type: Observer
  props:
    query: "isDarkMode"
    builder:
      type: Container
      props:
        color: "shql: IF isDarkMode THEN '0xFF424242' ELSE '0xFFE3F2FD'"
```

---

## 💡 Key Insights

### 1. SHQL Already Has State Management

| Feature | SHQL Has It? | How |
|---------|--------------|-----|
| **Reactive UI** | ✅ Yes | Observer widget |
| **Persistence** | ✅ Yes | SAVE_STATE/LOAD_STATE |
| **Notify listeners** | ✅ Yes | SET() triggers notifyListeners |
| **Dynamic variables** | ✅ Yes | Runtime scope |
| **Server-driven** | ✅ Yes | YAML-based |

**Conclusion:** For YAML-driven UI, SHQL+Observer is complete!

### 2. When BLoC Actually Adds Value

BLoC/Cubit's **only real advantage** over SHQL is **compile-time type safety**:

1. **Type Safety - Prevents Typos**
   ```dart
   // BLoC: Compiler catches typos
   emit(Autenticated());  // ❌ Compile error

   // SHQL: Typos become runtime bugs
   SET('state', 'autenticated');  // ✅ No compile error, wrong at runtime
   ```

2. **Exhaustiveness Checking - Forces Handling All Cases**
   ```dart
   // BLoC: Sealed classes force you to handle all states
   sealed class AuthState {}
   class Unauthenticated extends AuthState {}
   class Authenticated extends AuthState { final User user; }

   switch (state) {
     case Unauthenticated(): return LoginScreen();
     case Authenticated(): return HomeScreen();
     // Forgot one? Compiler error!
   }

   // SHQL: Nothing forces you to handle all cases
   IF state = 'unauthenticated' THEN login
   ELSEIF state = 'authenticated' THEN home
   -- Forgot 'loading'? No error, just wrong behavior
   ```

3. **IDE Support**
   ```dart
   // BLoC: Autocomplete suggests valid states
   state.  // IDE shows: isDarkMode, themeMode, etc.

   // SHQL: No autocomplete for variable names
   isDarkMode  // Typo as isDarkMod? No IDE help
   ```

### 3. Separation of Concerns

- **ScreenCubit (BLoC):** Screen lifecycle state (minimal use)
- **SHQL:** UI state, business logic, persistence
- **YAML:** Declarative UI structure
- **Observer:** Reactive rebuilds for SHQL variables

---

## 🎓 What This Demonstrates

### To Whom it may concern:

1. **Understanding Existing Architecture**
   - SHQL already had SET(), SAVE_STATE(), LOAD_STATE()
   - Observer pattern already provided reactivity
   - Didn't need BLoC for state that already had a solution

2. **Minimal BLoC Integration**
   - ScreenCubit wraps existing StatefulWidget lifecycle
   - Meets BLoC requirement without breaking existing code
   - Demonstrates when BLoC adds value vs. when it's redundant

3. **Real-World Engineering**
   - Don't add complexity if existing solution works
   - Understand the problem before choosing the tool
   - SHQL+Observer handles YAML-driven state perfectly

---

## 📊 Comparison Table

| Feature | SHQL+Observer | ScreenCubit (BLoC) |
|---------|---------------|-------------------|
| **State Type** | Dynamic (any type) | Typed (sealed classes) |
| **Scope** | YAML-driven UI | StatefulWidget lifecycle |
| **Persistence** | ✅ SAVE_STATE/LOAD_STATE | ❌ Not needed for lifecycle |
| **DevTools** | ❌ | ✅ BLoC inspector |
| **Type Safety** | ❌ Runtime | ✅ Compile-time |
| **State Machine** | ❌ No enforcement | ✅ Sealed classes |
| **Reactivity** | ✅ Observer | ✅ BlocBuilder |
| **Server-Driven** | ✅ Perfect | ❌ Needs recompile |
| **Use Case** | UI state, business logic | Screen lifecycle only |

---

## 🚀 Try It Out

1. **Run the app**
   ```bash
   flutter run
   ```

2. **Navigate to "Theme Demo"**
   - See theme loaded from SharedPreferences via `LOAD_STATE()`
   - Click "Toggle Theme" (calls `SET()` + `SAVE_STATE()`)
   - Watch UI update instantly (Observer pattern)
   - Notice colors change dynamically

3. **Restart the app**
   - Theme persists (thanks to `SAVE_STATE()` → SharedPreferences)
   - Pure SHQL, no BLoC needed for this use case!

---

## 📝 Summary

**The Answer:** SHQL+Observer already handles YAML-driven state completely!

✅ **Use SHQL+Observer** for runtime-dynamic, persistent, YAML-driven UI state
✅ **Use BLoC/Cubit** only for Flutter framework integration (MaterialApp, etc.)

**This project demonstrates:**
- ScreenCubit for screen lifecycle (minimal BLoC use)
- SHQL for UI state, business logic, and persistence
- Observer for reactive YAML-driven widgets
- No unnecessary BLoC complexity!

**Result:** A clean, server-driven UI framework that doesn't over-engineer! 🎉
