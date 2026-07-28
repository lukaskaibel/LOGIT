//
//  UIConstants.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 03.11.22.
//

import CoreGraphics
import Foundation

let CELL_PADDING: CGFloat = 14

/// Height of the Summary's side-by-side Strength / Balance tiles. Fixed rather than intrinsic so the
/// two charts share a baseline: each tile's graphic fills whatever the header and figure leave, and
/// an intrinsic height would let one half's wrapped caption shorten only that half's chart.
let PAIRED_TILE_HEIGHT: CGFloat = 178
let CELL_SPACING: CGFloat = 5

let SCROLLVIEW_BOTTOM_PADDING: CGFloat = 100

let SET_GROUP_FIRST_COLUMN_WIDTH: CGFloat = 100

let SECTION_HEADER_SPACING: CGFloat = 10
let SECTION_SPACING: CGFloat = 25
