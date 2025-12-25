# server_driven_ui

UI expressions are evaluated in a restricted, non-iterative sandbox to ensure determinism and safety during widget rebuilds. All side effects and control flow are confined to explicit execution contexts triggered by user event