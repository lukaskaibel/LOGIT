//
//  SectionedFetchRequestWrapper.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import SwiftUI


struct FetchRequestWrapper<Content: View, Object: NSManagedObject>: View  {
    
    @FetchRequest var sections: FetchedResults<Object>
    
    let content: ([Object]) -> Content
    
    init(
        _ type: Object.Type,
        sortDescriptors: [SortDescriptor<Object>] = [],
        predicate: NSPredicate? = nil,
        animation: Animation? = nil,
        @ViewBuilder content: @escaping ([Object]) -> Content
    ) {
        _sections = FetchRequest<Object>(
            sortDescriptors: sortDescriptors,
            predicate: predicate,
            animation: animation
        )
        self.content = content
    }
    
    var body: some View {
        content(Array(sections))
            .id(sections.count)
    }
    
}
