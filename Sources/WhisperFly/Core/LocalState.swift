import Foundation

/// View-local mutable state that does not depend on SwiftUI's `@State` macro.
///
/// `@State` is implemented as an `@attached` macro in the macOS 26+ SDK, and the
/// macro plugin (`SwiftUIMacros`) ships only inside a full Xcode installation.
/// Building this package with a Command Line Tools–only toolchain — which is
/// exactly what the README tells users to do — therefore fails the moment a view
/// declares `@State`.
///
/// `@StateObject` is a plain property wrapper and is available with every
/// toolchain, so view-local state is modelled as a tiny `ObservableObject`
/// instead. Semantics match `@State`: the box is created once when the view is
/// first rendered and survives re-renders.
@MainActor
final class LocalState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func update(_ transform: (inout Value) -> Void) {
        var copy = value
        transform(&copy)
        value = copy
    }
}

/// Convenience alias for the overwhelmingly common `@State private var flag = false` case.
typealias LocalFlag = LocalState<Bool>
