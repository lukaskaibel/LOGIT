//
//  Date+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.09.21.
//

import Foundation

extension Date {
    var startOfWeek: Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)) ?? self
    }

    var endOfWeek: Date {
        guard let lastDayOfWeek = Calendar.current.date(byAdding: .day, value: 6, to: startOfWeek) else {
            return self
        }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: lastDayOfWeek)?
            .addingTimeInterval(0.999) ?? lastDayOfWeek
    }

    var startOfMonth: Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }

    var endOfMonth: Date {
        let startOfNextMonth = Calendar.current.date(byAdding: .month, value: 1, to: startOfMonth)
        return Calendar.current.date(byAdding: .second, value: -1, to: startOfNextMonth ?? self) ?? self
    }

    var startOfYear: Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.year], from: self)) ?? self
    }

    var endOfYear: Date {
        let startOfNextYear = Calendar.current.date(byAdding: .year, value: 1, to: startOfYear)
        return Calendar.current.date(byAdding: .second, value: -1, to: startOfNextYear ?? self) ?? self
    }

    func inSameWeekOfYear(as date: Date) -> Bool {
        return startOfWeek == date.startOfWeek
    }

    func description(_ style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(self) {
            return NSLocalizedString("today", comment: "")
        } else if Calendar.current.isDateInYesterday(self) {
            return NSLocalizedString("yesterday", comment: "")
        } else if self > Calendar.current.date(byAdding: .day, value: -7, to: Date.now)! {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateStyle = style
        }
        return formatter.string(from: self)
    }

    var weekDescription: String {
        if Calendar.current.isDate(self, equalTo: .now, toGranularity: [.weekOfYear, .year]) {
            return NSLocalizedString("thisWeek", comment: "")
        } else if Calendar.current.isDate(self, equalTo: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now)!, toGranularity: [.weekOfYear, .year]) {
            return NSLocalizedString("lastWeek", comment: "")
        } else {
            return "\(startOfWeek.formatted(.dateTime.day().month())) - \(endOfWeek.formatted(.dateTime.day().month()))"
        }
    }

    var monthDescription: String {
        return formatted(.dateTime.month(.wide).year())
    }

    var yearDescription: String {
        return formatted(.dateTime.year())
    }

    var timeString: String {
        let minute = Calendar.current.component(.minute, from: self)
        return "\(Calendar.current.component(.hour, from: self)):\(minute / 10)\(minute % 10)"
    }
    
    var isInCurrentYear: Bool {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let givenYear   = calendar.component(.year, from: self)
        return currentYear == givenYear
    }
}
