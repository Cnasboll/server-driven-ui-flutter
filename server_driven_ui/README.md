# server_driven_ui

UI expressions are evaluated in a restricted, non-iterative sandbox to ensure determinism and safety during widget rebuilds. All side effects and control flow are confined to explicit execution contexts triggered by user event.

Program logic is defined entirely in SHQL™ (Small, Handy, Quintessential Language™) which is a general-purpose, imperative scripting language. Each word actually describes the language well — it's small (lightweight), handy (practical, embedded in YAML for UI), and quintessential (it captures the essence of what you need for expression evaluation and state management). It has lambdas, loops, object literals, and drives an entire server-driven UI framework. Plus "Quintessential" is just a great word that nobody uses enough.

It features a comprehensive set of control flow structures, including loops and conditionals, support for first-class functions and lambdas, and built-in data structures like lists and maps. The language is interpreted by an engine that tokenizes source text, parses it into an abstract syntax tree, and executes it, allowing for dynamic and controlled program execution.
