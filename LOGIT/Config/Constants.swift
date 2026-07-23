//
//  Constants.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 10.03.25.
//

import CoreGraphics

let BOTTOM_SHEET_SMALL: CGFloat = 80

/// The shared support / feedback inbox — used by both the "Suggest a Feature" and "Contact
/// Support" rows in Settings (the dot matches the existing support link).
let FEEDBACK_EMAIL = "logit.fitness@gmail.com"

/// The App Store write-review deep link for the "Rate LOGIT" row. An explicit rate button
/// must open the store's review page directly — `requestReview` is only a *request* that
/// the system rate-limits (a handful of prompts per year) and silently drops otherwise.
let APP_STORE_WRITE_REVIEW_URL = "https://apps.apple.com/app/id6444813640?action=write-review"
