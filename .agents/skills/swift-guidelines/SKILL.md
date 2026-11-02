---
name: swift-guidelines
description: Swift design and coding conventions covering naming, terminology, comments, control flow, protocols, extensions, fluent APIs, argument labels, error handling, file and package structure, and Swift Testing. Use this whenever Swift comes up in any form — writing, editing, refactoring, reviewing, or explaining Swift code; reviewing a diff or PR that touches .swift files or Package.swift; or answering a Swift API-design or style question — even if the user never asks for "guidelines" or a "style guide".
---

# Swift Programming Guidelines

These are conventions for writing Swift, not rigid rules. Treat every section here as a tool to reach for, not a rule to enforce. Treat every code snippet below as an example of the pattern, not a template to copy verbatim. When a guideline and the user's existing codebase conventions disagree, match the codebase and mention the tension briefly.

## Design Process

- Design and build software to be tried early, and don't hesitate to throw away the clumsy parts and rebuild them.
- Design through constant iteration and refinement. Treat a first pass, a draft API, a first naming attempt, as a starting point to revise together, not a final answer, and expect it to change as the conversation continues. This can mean detouring to build a tool first, when that's what lightens the task; expect to throw some of those tools out once you're done with them.
- Use structured, conversational Q&A to keep critical thinking with the user. When a design decision is genuinely open, e.g. which protocol to reach for, how monolithic a project actually is, whether an abstraction earns its keep, ask rather than deciding on the user's behalf.
- Favor Occam's razor: entities must not be multiplied beyond necessity. In practice this means weighing the language feature or abstraction against how easily a programmer can actually reach for its power, not against the feature's theoretical ceiling. Where it holds, the simplest way to write the code is also the most pragmatic one.[^backcompat]

[^backcompat]: Backward compatibility is the standing exception. Swift itself can target systems as old as macOS 10.13, though 10.15 is the baseline in practice, and Apple's newer libraries, or newer Foundation features (rarer), routinely simplify a workflow at the cost of dropping support for those older platforms. Code that has to stay compatible with 10.x is often the more complex version by comparison, and that complexity isn't a violation of the razor: it's the cost of the constraint, not a failure to look for the simplest path within it.

## 1. Fundamentals

Clarity at the point of use is the goal that everything else here serves. When a naming choice, an argument label, or a comment could go two ways, pick whichever reads more clearly at the call site, even if it costs a few extra characters. Clarity beats brevity.

- If you don't have direct access to Swift's toolchain to compile or run code itself, the user can run it themselves the way they'd download and try a program, so hand off drafts for them to try rather than holding code back until it feels finished.
- Make it easy to write, test, and run programs.
- Write programs, and functions, to do one thing and do it well. A function or an executable (command-line tools especially) can take on as much functionality as it needs, as long as all of it still serves that one intended purpose; the constraint is about scope, not size. (Recommended, but not required, for GUIs.)

## 2. Naming Conventions

- Name variables, parameters, and associated types after the role they play, not the type they happen to be. A parameter constrained to `String` might still be named `title` or `identifier` depending on what it's for.
- Include every word needed to remove ambiguity for someone reading the *call site*, not just the declaration.
- Omit words that don't carry information at the use site. Every word in a name should earn its place.
- When a type alone is too weak to convey a parameter's role (e.g. two `Int` parameters in a row), the name has to do that work instead.
- In the rare case where the most natural name for a value collides with one of Swift's own native types or keywords, add a prefix rather than fight the collision. For example, a `Bool` case naturally called `true` becomes `isTrue`.

## 3. Use Terminology Well

A term of art is a word or phrase with a precise, specialized meaning inside a particular field.

- Reach for a common word over an obscure one when both convey the same meaning. Don't say "epidermis" if "skin" works. Save terms of art for when they capture something that would otherwise be lost.
- If you do use a term of art, use it correctly, in its established sense.
- Avoid abbreviations, especially nonstandard ones. An abbreviation is effectively its own term of art: the reader has to know the expansion to understand it.
- Follow existing Swift and platform precedent rather than optimizing a name for a total beginner at the cost of conflicting with established convention.

## 4. Comments

- Keep comments sparse. Well-named code needs fewer of them.
- Write documentation comments where naming alone can't carry the meaning, and always for `public` APIs. A `public` API deserves fuller DocC-style treatment.
- Comments describe what the code does *now*, not its history. Skip past-tense, changelog-style notes ("renamed from X", "previously did Y", "refactored to..."). A comment is documentation, not a commit message.
- Write plain, short sentences without em dashes.
- Document the complexity of any computed property that isn't O(1). Readers default to treating property access as free, because stored properties trained them to. Flag it explicitly whenever that assumption doesn't hold.

## 5. Control Flow

- Keep control flow to simple constructs, and prefer flat, linear logic over deep branching.
- Avoid nesting conditions:
  - Reach for `switch` where it fits.
  - Where `switch` isn't the right shape, use `if`, and invert it when that removes a level of nesting.
  - Use `where` inside `for` loops to filter, instead of wrapping the loop body in an `if`. For example: `for value in values where value > 500 { }`.

## 6. Protocols

> A protocol defines a blueprint of methods, properties, and other requirements suited to a particular task. A class, structure, or enumeration adopts a protocol to provide a real implementation of those requirements. Any type that satisfies a protocol's requirements is said to conform to it.

This isn't just a workaround for Swift lacking multiple inheritance. Protocol-oriented programming is Swift's own, more fully realized take on compositional design, and it holds up as good practice on its own terms, library boundary or not.

Prefer composing a type's behavior from several small, single-purpose protocols over sharing it through class inheritance. Each protocol should represent one capability: one thing the conforming type can do, or have done to it, not a bundle of unrelated behavior. A concrete type conforms to as many of these protocols as it actually needs, so its full behavior comes from the union of them rather than from a shared base class only part of which is relevant.

```swift
// Composing a type's behavior from multiple small protocols, instead of
// bundling every capability into one and inheriting it.
protocol Adoptable {
    var ownerName: String { get set }
    var name: String { get }
    func feed()
    func play()
}

protocol Protecting {
    func protect()
}

// Cat's full behavior is the union of two protocols, not inheritance from
// one shared Pet base class.
struct Cat: Adoptable, Protecting {
    var ownerName: String
    var name: String
    var emoji = "🐈"

    func feed() { print("\(emoji) \(name) eats.") }
    func play() { print("\(emoji) \(name) plays.") }
    func protect() { print("\(emoji) \(name) protects the home.") }
}

func adopt(_ pet: Adoptable) {
    print("\(pet.ownerName) adopted \(pet.name).")
}

let josie = Cat(ownerName: "Catarina", name: "Josie")
adopt(josie) // Catarina adopted Josie.
```

This gets the practical benefits inheritance offers, shared behavior and interchangeable types, without its costs: no forced single lineage, no base class bloated with behavior only some subclasses use, no subclass stuck inheriting something it has to override away. "Composition" here means exactly this: a type conforming to several independently useful protocols at once, assembling its behavior from separate pieces, rather than extending one continuous hierarchy.

Naming:
- If the implementer *is something*, name the protocol with a noun: `Sequence`, `View`, `Repository`.
- If the implementer *is doing something*, name it with an `ing` adjective: `Loading`, `Generating`, `Coordinating`.
- If *something is done to* the implementer, name it with an `able` or `ible` adjective: `Comparable`, `Codable`, `Cacheable`.

Other tools:
- Used sparingly, a protocol can carry a generic constraint through an `associatedtype` (e.g. `associatedtype C: Collection`) or a function's `Self` return type.
- Group related protocols with a `typealias`, e.g. `typealias CityData = WeatherData & LocationData & Displayable`.
- Take extra care with unconstrained polymorphism (`Any`, `AnyObject`, unconstrained generic parameters); it's easy to create ambiguous overload sets this way.
- A protocol can also describe an opaque (boxed) return type without naming a concrete type. Apple leans on this throughout Foundation for the optimization, interoperability, and backward-compatibility benefits it offers.
  - A variable or function parameter can be typed as a protocol directly, e.g. `let items: CacheableOrder` or `var orders: Orderable`.
  - When the protocol has no generic constraints, a function or variable can return an opaque type with `some`, e.g. `-> some View` or `var body: some View`, to describe the return type without naming a concrete one.
  - The same opaque-type approach works for parameters.
  - In rare cases, an opaque type resolves a backward-compatibility problem: if a newer, cleaner API is only available on newer platforms, `@available()` on the type plus `if #available() {} else {}` at the call site lets both paths coexist.

## 7. Extensions

> Extensions add new functionality to an existing class, structure, enumeration, or protocol, including types you don't have the source for (retroactive modeling).

```swift
protocol NameContaining {
    var firstName: String { get }
    var lastName: String { get }
    var fullName: String { get }
}

extension NameContaining {
    /// Default implementation of the `NameContaining` protocol's full name.
    var fullName: String {
        firstName + " " + lastName
    }
}

// Extending a type without access to its source.
extension Date {
    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self)!
    }
}
```

An extension needs a reason to exist beyond splitting a file into more pieces. A useful test: if you removed every extension of a type and pasted its contents into the type's main declaration, would anything about what the type does change? If not, those extensions weren't necessary, and the type should not have been split apart in the first place. The recommended reasons to reach for an extension are the ones below: separating a type's public API from its private one, giving a protocol a default implementation, or adding a common utility to the standard library or a third-party type.

- **Protocol defaults.** Give a protocol a default implementation only for the protocol's own established functions, and use this sparingly. A conforming type can still drop parts of the default it doesn't need, for example removing `async` if the conformance doesn't require it.
- **Public API.** When there's enough separation between the internal and public surface, put the public API in an `extension` directly below the concrete type, marked with `// MARK: - Public API`. The bar for "enough separation" is low; Apple does this constantly, and the concrete type or the extension can be small or large. What matters is that anything private stays in the concrete type; if a type is entirely public, skip the split. Properties are the one exception, since they must stay in the concrete type; a public extension can still hold a computed variable or constant as long as it implements something. Note that everything inside a `public` extension becomes public.
- **Expanding existing libraries.** Extensions aren't limited to your own types or third-party ones; they're also how you add general-purpose utilities to Foundation itself. If `clamped(to:)`, a function that keeps a value inside a range, is going to be reused everywhere, put it on `extension Comparable` rather than on one specific type. An extension is also the way to define protocol conformance outside the type's own source file, or for a type you don't have the source for.

## 8. Fluent API Design

- Favor method and function names that read as grammatical English phrases at the call site.
- Name factory methods starting with `make`, e.g. `x.makeIterator()`.
- The first argument to an initializer or factory method shouldn't form a phrase with the base name, e.g. `x.makeWidget(cogCount: 47)`.
- Name a function or method after its side effects:
  - No side effects: read as a noun phrase, e.g. `x.distance(to: y)`, `i.successor()`.
  - Has side effects: read as an imperative verb phrase, e.g. `print(x)`, `x.sort()`, `x.append(y)`.
  - For a mutating/nonmutating pair with similar semantics (the nonmutating version returns a new value instead of updating in place), name them consistently:
    - If the operation is naturally a verb, use its imperative for the mutating form and add `ed`/`ing` for the nonmutating counterpart.
    - If the operation is naturally a noun, use the noun for the nonmutating form and add a `form` prefix for the mutating counterpart.
- A Boolean method or property should read as an assertion about the receiver when used nonmutatingly, e.g. `x.isEmpty`, `line1.intersects(line2)`.

## 9. Argument Labels

```swift
func move(from start: Point, to end: Point)
x.move(from: x, to: y)
```

- Omit all labels when the arguments can't usefully be told apart, e.g. `min(number1, number2)`, `zip(sequence1, sequence2)`.
- In an initializer that performs a value-preserving type conversion, omit the first argument label, e.g. `Int64(someUInt32)`.
- When the first argument is part of a prepositional phrase, give it a label starting at the preposition, e.g. `x.removeBoxes(havingLength: 12)`.
- Otherwise, if the first argument is part of a grammatical phrase, fold its words into the base name and omit the label, e.g. `x.addSubview(y)`.

## 10. Error Handling

- Use `guard` for early exits.
- Use `try` to propagate errors instead of force-unwrapping with `try!`.
- Use `defer` to delay a block of code until the current scope exits; it's especially useful for cleanup and for work that has to run regardless of which return path a function takes.

## 11. File Structure

This covers anything that outgrows a single code block: a library, a multi-target codebase, a monolithic project, or just a task that needs more than a snippet to solve.

- Library-shaped conventions, the public/private extension split among them, assume a project meant to be consumed by other code. If it's an executable, they're irrelevant: apply them where they still serve clarity, and skip them where they'd just add ceremony to a program nothing else will ever import. Some projects are monolithic instead.
  - "Monolithic" here means the package has no separation into library, demo, and executable targets: there's just the one library or executable, and all its code lives in that single target. The code can still be spread across as many files as makes sense for organization; monolithic describes the package's target structure, not its file count.
  - Small executables, command-line tools, and GUIs are typically monolithic. This also covers SwiftUI, and drop-in replacements for it such as SwiftCrossUI.
  - A demo can graduate into a fully functional executable or GUI over time. Treat "monolithic" as a snapshot of the package's current target structure, not a permanent label; revisit it as the project grows.
- Large-scale file I/O changes should ship in named phases (Phase A/B, Phase 1/2, or a three-to-five-phase plan), always in a predictable sequence, and always starting with scaffolding.
  - As a guide rather than a rule, close each phase out with a bulleted task list of the phases already done and the ones still coming, marking off (`[x]`) whatever's complete. It's a lightweight form of memory retention across a rollout, not a required deliverable.

## 12. Unit Tests

This section applies to file-based projects with unit tests.

- Use Swift Testing (`import Testing`, `@Test`), not XCTest, for new tests.
- Reduce duplication:
  - Put commonly used helper functions, structs, protocols, and variables at the top level of the test file, or above the tests that share them.
  - Use `@Test(arguments:)` to generate multiple cases from one test function, e.g. `@Test(arguments: ["1", "🦊", "fox"], ["jumped", "leaped", "flew"])`. If pairing two argument lists positionally rather than taking their cross product, zip them first with `zip()`.
- Protocols and extensions can shape test fixtures the same way they shape production code.
- Cover both the internal pipeline and the public API. A test suite that only exercises the public surface can miss bugs in the internals it doesn't observe directly, and one that only exercises internals can miss integration problems the public API surface would catch.