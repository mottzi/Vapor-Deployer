# Codebase Structure & Organization Guidelines

This document describes the preferred conventions for organizing this codebase. These are guidelines rather than strict rules; pragmatism and readability always take precedence. If deviating from these conventions yields superior clarity, maintainability, or reasoning, developers should adapt accordingly.

## 1. Domain- and Feature-Scoped Folders

The codebase is structured around domain or feature concepts rather than technical layers. All types, business logic, persistence layers, and UI components relating to a single domain concept are kept together in a dedicated directory under the source root.

### Nesting Limits & Structure
* **Parent Folders**: Main entry-point types, central domain definitions, shared helpers, and core configurations reside directly in the top-level directory of the domain.
* **Passive Grouping Directories**: Passive folders (e.g., directories categorizing UI components or commands) can be used to organize files administratively.
* **Functional Sub-components**: Functional sub-components (directories containing executable domain logic) are limited to a single level of nesting. If a functional sub-component grows complex enough to require its own sub-components, it should be extracted as a top-level parent folder at the project source root to prevent deep nested folder trees.
* **Single-File Directories**: Avoid creating a subdirectory to house only a single file. Keep files in the parent directory until the domain grows enough to warrant a dedicated folder containing multiple files.

### The Bootstrapping Module
* A dedicated entry-point directory is reserved for application startup configurations, global variables, service initialization, and cross-cutting infrastructure utilities (such as logging or file-locking systems) that are shared universally. Individual domain and feature folders must remain clean of global setup and configuration logic.

### Separation of Interfaces and Core Logic
* User interfaces, such as command-line entry points and web dashboard controllers, should be grouped into their own centralized, interface-specific directories rather than distributed inside feature-specific folders. This keeps domain-scoped folders focused entirely on core business logic, data structures, and services.

---

## 2. File Layout & Extension Extraction Heuristics

To balance file cleanliness with cognitive navigation, files are organized iteratively:

### Primary Type Declarations
The primary file for a type defines the core structure:
* Core type definition, schema, and stored properties.
* Initializers.
* Core high-level functions (typically public or internal methods that serve as the main interface).

### Method Ordering (The Step-Down Rule)
* Within any struct, class, or extension block, functions are ideally ordered sequentially from the highest level of abstraction to the lowest.
* It is helpful to place caller orchestrators (e.g., bulk processing or database loop methods) first, immediately followed by the helper/callee methods they execute (e.g., single-item worker methods).

### Extension Extraction Guidelines
* **In-File Extensions**: Extensions providing secondary helpers, protocol conformances, or private implementation details are initially kept in the primary type file to keep related logic grouped together.
* **Static Utility Segregation**: Stateless `static` helper functions should generally be kept distinct from stateful instance declarations. Placing pure utility functions in a dedicated static utilities extension block at the bottom of the file is preferred.
* **No MARK Comments**: The use of `// MARK:` comments should be avoided. Logical segregation is best achieved through clean file splitting, separate extension blocks, and descriptive function names rather than inline section headers.
* **Unidirectional Dependencies**: To keep coupling clean, a core type definition file should avoid depending on helpers defined exclusively in downstream extension files. If a helper utility is required by methods in the primary file, it is best to define that utility directly in the primary file (using a static utilities extension if stateless).
* **Extraction Trigger (200 Lines)**: As a general guideline, when a file exceeds 200 lines, or when logical boundaries become clear, extensions should be extracted into separate files.
* **Early Extraction Sites**: Extract extensions earlier than the 200-line threshold if:
  * There is a strong semantic boundary (e.g., database migrations).
  * The extension requires importing a framework that is otherwise unnecessary for the primary type definition, keeping the main file's imports clean.
  * Private helper functions are extracted into their own semantically grouped extensions or files to keep the core high-level functions in the main file clean.
* **Access-Control Segregation (Public vs. Private)**: Within extracted extension files, group methods by visibility when possible. A clean pattern is to declare public and internal API surface methods in the first extension block at the top, and put private implementation helpers in trailing extension blocks at the bottom. For complex files, splitting private helpers across multiple blocks (for example, keeping high-level policy algorithms separate from low-level database queries or file checks) is preferred.
* **Naming**: Extracted files use the `Type+Group.swift` naming convention, where `Type` is the base type and `Group` represents the semantic area of the extension.
