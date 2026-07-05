---
applyTo: "lib/**/*.dart"
---

# Code Style (Client)

Conventions for Dart/Flutter code in this repo, beyond what `dart format` and `flutter analyze` already enforce.

- Keep it DRY. Before making a class, function, or constant, do a THOROUGH search for variables/constants/functions/widgets to reuse.
- This also applies to terminology. Semantics and word choice matter. Whenever describing a concept or choosing a variable name, search for established conventions and re-use existing language.
- Keep it well-typed. Passing around `Map`s with `dynamic` is NOT COOL.
- Use descriptive function/class/variable names always.
- NEVER hard-code values. Search for constants to use and add where they don't exist.
- Code should generally be self-documenting with clear class / variable names. Use minimal code comments when necessary. If you find yourself writing more than two lines for a function/class/etc, it likely needs to be restructured.
- Try to maintain single-responsibility, unit-testable classes. In general, file lengths should not exceed 400 lines. Extremely long files are almost always doing too many things. Keep code readable and short.
- Prefer to keep Flutter widgets together rather than splitting them up into smaller widgets, unless they are used in multiple places, in which case they should be their own widget.
- NEVER return widgets from functions. Flutter's build tools optimize for widgets-as-classes.
- Functionality that directly extends the Matrix Client's functionality belongs in a Client extension. Functionality that directly extends Matrix Rooms' functionality belongs in a Room extension.
- Keep functions inside of classes. When functions do not necessarily need to be in a certain class, group them as static functions within a class with a name that reflects the similarities between these functions. These will generally be Utility classes.
- When solving an error, find a root cause and resolve the underlying problem instead of adding a bandaid fix. Err on the side of "scope creep" over "bandaid."
- Keep functions short. Functions should do one thing. If a function is difficult to name, that's a smell that it's not doing one thing.
- Reduce the number of widget rebuilds. Prefer `ValueNotifier`s and `ChangeNotifier`s to calling `setState` unless a change in state requires a full widget rebuild.
- Each file should contain only one class. The only exception is small, private utility classes used by the main class in the file.
- Prefer classes to typedefs.
- Never put functions inside of other functions.
- Don't write pointless tests. Tests should confirm that the explicit functionalities of the given class are working, and that edge cases do not cause error. Prefer to write tests first and then write code that makes those tests pass. This ensures that tests are targeting the correct functionality, and that tests don't know about any of the internal workings of the code they're testing.
- Keep widgets well encapsulated. Child classes / widgets shouldn't need to know too much information about their parents. Only pass necessary information into widgets.
- Cache the results of heavy computations.
