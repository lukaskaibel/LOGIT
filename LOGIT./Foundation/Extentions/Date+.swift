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
        return Calendar.current.date(byAdding: .day, value: 6, to: startOfWeek) ?? self
    }
        
    var startOfMonth: Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
    
    var startOfYear: Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.year], from: self)) ?? self
    }

    func inSameWeekOfYear(as date: Date) -> Bool {
        return self.startOfWeek == date.startOfWeek
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
            return "\(self.startOfWeek.formatted(.dateTime.day().month())) - \(self.endOfWeek.formatted(.dateTime.day().month()))"
        }
    }

    var monthDescription: String {
        return self.formatted(.dateTime.month(.wide).year())
    }

    var timeString: String {
        let minute = Calendar.current.component(.minute, from: self)
        return "\(Calendar.current.component(.hour, from: self)):\(minute/10)\(minute%10)"
    }

}
