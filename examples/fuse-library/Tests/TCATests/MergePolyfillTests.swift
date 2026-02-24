#if !SKIP
#if canImport(Combine)
import Combine
#else
import OpenCombineShim
#endif
@testable import ComposableArchitecture
import Testing

// MARK: - Publishers.Merge polyfill isolation tests
//
// These tests isolate the root cause of the Android dismiss-action bug:
// TCA's custom Publishers.Merge polyfill subscribes the downstream to a
// PassthroughSubject AFTER sinking both upstreams, so synchronous emissions
// from Just are sent to the subject before any subscriber is attached and
// are silently lost.
//
// Tests 1 & 8 document (pre-fix) or guard (post-fix) the merge polyfill bug.
// Tests 2-7 rule out every other OpenCombine operator in the chain.

@Suite("Merge Polyfill Isolation")
struct MergePolyfillTests {

  // MARK: - Merge polyfill tests (Android-only, where the polyfill is compiled)

  #if !canImport(Combine)
  @Test("Merge polyfill forwards synchronous emission from Just")
  func mergePolyfillForwardsSynchronousEmission() {
    var received: [String] = []
    let cancellable = Publishers.Merge(
      Just("a"),
      Empty<String, Never>(completeImmediately: false)
    )
    .sink { _ in } receiveValue: { received.append($0) }
    #expect(received == ["a"], "Just(\"a\") merged with Empty should deliver \"a\" synchronously")
    cancellable.cancel()
  }

  @Test("Merge polyfill forwards async emission from PassthroughSubject")
  func mergePolyfillWithAsyncEmission() {
    var received: [String] = []
    let subject = PassthroughSubject<String, Never>()
    let cancellable = Publishers.Merge(
      subject,
      Empty<String, Never>(completeImmediately: false)
    )
    .sink { _ in } receiveValue: { received.append($0) }
    subject.send("b")
    #expect(received == ["b"], "Value sent after subscription should be received")
    cancellable.cancel()
  }
  #endif

  // MARK: - OpenCombine operator tests (rule out each operator in the _cancellable chain)

  @Test("Deferred forwards synchronous value from Just")
  func openCombineDeferredForwardsSynchronousValue() {
    var received: [String] = []
    let cancellable = Deferred { Just("a") }
      .sink { _ in } receiveValue: { received.append($0) }
    #expect(received == ["a"], "Deferred { Just(\"a\") } should deliver synchronously")
    cancellable.cancel()
  }

  @Test("PrefixUntilOutput preserves inner value")
  func openCombinePrefixUntilOutputPreservesInnerValue() {
    var received: [String] = []
    let cancellable = Just("a")
      .prefix(untilOutputFrom: Empty<Void, Never>(completeImmediately: false))
      .sink { _ in } receiveValue: { received.append($0) }
    #expect(received == ["a"], "prefix(untilOutputFrom: Empty) should not suppress Just value")
    cancellable.cancel()
  }

  @Test("HandleEvents preserves value")
  func openCombineHandleEventsPreservesValue() {
    var received: [String] = []
    let cancellable = Just("a")
      .handleEvents(receiveCancel: {})
      .sink { _ in } receiveValue: { received.append($0) }
    #expect(received == ["a"], "handleEvents should not suppress Just value")
    cancellable.cancel()
  }

  @Test("Concatenate preserves first publisher value")
  func openCombineConcatenatePreservesFirstValue() {
    var received: [String] = []
    let cancellable = Just("a")
      .append(Empty<String, Never>(completeImmediately: false))
      .sink { _ in } receiveValue: { received.append($0) }
    #expect(received == ["a"], "Just(\"a\").append(Empty) should deliver \"a\" before parking")
    cancellable.cancel()
  }

  @Test("Full cancellable chain preserves value")
  func fullCancellableChainPreservesValue() async {
    // Reproduce the 3-layer _cancellable wrapping that PresentationReducer uses
    enum ID1: Hashable { case id }
    enum ID2: Hashable { case id }
    enum ID3: Hashable { case id }

    let effect = Effect<String>.send("a")
      .cancellable(id: ID1.id)
      .cancellable(id: ID2.id)
      .cancellable(id: ID3.id)

    var received: [String] = []
    // Extract the publisher from the effect and subscribe
    if case let .publisher(publisher) = effect.operation {
      let cancellable = publisher
        .sink { _ in } receiveValue: { received.append($0) }
      // Give async effects a moment to deliver
      try? await Task.sleep(nanoseconds: 50_000_000)
      #expect(received == ["a"], "3-layer cancellable wrapping should not suppress the value")
      cancellable.cancel()
    } else {
      // On Android with the workaround, Effect.send uses .run — still valid
      Issue.record("Expected .publisher operation but got .run — the workaround may still be active")
    }
  }

  #if !canImport(Combine)
  @Test("Merge with cancellable chain forwards value")
  func mergeWithCancellableChainForwardsValue() async {
    // This reproduces the exact production failure path:
    // PresentationReducer merges cancellable-wrapped dismiss effects with other effects
    enum ID1: Hashable { case id }
    enum ID2: Hashable { case id }
    enum ID3: Hashable { case id }

    let justEffect = Effect<String>.send("a")
      .cancellable(id: ID1.id)
      .cancellable(id: ID2.id)
      .cancellable(id: ID3.id)

    let emptyEffect = Effect<String>(
      operation: .publisher(Empty<String, Never>(completeImmediately: false).eraseToAnyPublisher())
    )

    let merged = justEffect.merge(with: emptyEffect)

    var received: [String] = []
    if case let .publisher(publisher) = merged.operation {
      let cancellable = publisher
        .sink { _ in } receiveValue: { received.append($0) }
      // Give async effects a moment to deliver
      try? await Task.sleep(nanoseconds: 50_000_000)
      #expect(received == ["a"], "Merged cancellable-wrapped Just should deliver the value")
      cancellable.cancel()
    } else {
      Issue.record("Expected .publisher operation for merged effects")
    }
  }
  #endif
}
#endif
