//
//  LinkReference.swift
//  swift-markdown
//
//  Created by Ben Davis on 29/05/2025.
//

import Foundation

public struct LinkReference {
  public let label: String
  public let url: String
  public let title: String?
  public let sourceRange: SourceRange
}
