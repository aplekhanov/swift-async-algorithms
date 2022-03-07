//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension AsyncSequence {

  @inlinable
  public func chunked<Subject : Equatable, Collected: RangeReplaceableCollection>(on projection: @escaping @Sendable (Element) -> Subject, into: Collected.Type) -> AsyncChunkedOnProjectionSequence<Self, Subject, Collected> {
    AsyncChunkedOnProjectionSequence(self, projection: projection)
  }

  @inlinable
  public func chunked<Subject : Equatable>(on projection: @escaping @Sendable (Element) -> Subject) -> AsyncChunkedOnProjectionSequence<Self, Subject, [Element]> {
    chunked(on: projection, into: [Element].self)
  }

}

public struct AsyncChunkedOnProjectionSequence<Base: AsyncSequence, Subject: Equatable, Collected: RangeReplaceableCollection>: AsyncSequence where Collected.Element == Base.Element {
  public typealias Element = (Subject, Collected)

  @frozen
  public struct Iterator: AsyncIteratorProtocol {

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    let projection: @Sendable (Base.Element) -> Subject

    @usableFromInline
    init(base: Base.AsyncIterator, projection: @escaping @Sendable (Base.Element) -> Subject) {
      self.base = base
      self.projection = projection
    }

    @usableFromInline
    var hangingNext: (Subject, Base.Element)?

    @inlinable
    public mutating func next() async rethrows -> (Subject, Collected)? {
      var firstOpt = hangingNext
      if firstOpt == nil {
        let nextOpt = try await base.next()
        if let next = nextOpt {
          firstOpt = (projection(next), next)
        }
      } else {
        hangingNext = nil
      }

      guard let first = firstOpt else {
        return nil
      }

      var result: Collected = .init()
      result.append(first.1)

      while let next = try await base.next() {
        let subj = projection(next)
        if subj == first.0 {
          result.append(next)
        } else {
          hangingNext = (subj, next)
          break
        }
      }
      return (first.0, result)
    }
  }

  @usableFromInline
  let base : Base

  @usableFromInline
  let projection : @Sendable (Base.Element) -> Subject

  @inlinable
  init(_ base: Base, projection: @escaping @Sendable (Base.Element) -> Subject) {
    self.base = base
    self.projection = projection
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base: base.makeAsyncIterator(), projection: projection)
  }
}

extension AsyncChunkedOnProjectionSequence : Sendable where Base : Sendable, Base.Element : Sendable { }
extension AsyncChunkedOnProjectionSequence.Iterator : Sendable where Base.AsyncIterator : Sendable, Base.Element : Sendable, Subject : Sendable { }
