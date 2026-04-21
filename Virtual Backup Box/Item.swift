//
//  Item.swift
//  Virtual Backup Box
//
//  Created by Scott Frey on 4/21/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
