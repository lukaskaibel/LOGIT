//
//  SectionedFetchRequestWrapper.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.01.25.
//

import CoreData
import SwiftUI


struct SectionedFetchRequestWrapper<Content: View, SectionIdentifier: Hashable, Result: Exercise>: View  {
    
    @SectionedFetchRequest var sections: SectionedFetchResults<SectionIdentifier, Result>
    
    let content: (SectionedFetchResults<SectionIdentifier, Result>) -> Content
    
    init(
        sectionIdentifier: KeyPath<Result, SectionIdentifier>,
        sortDescriptors: [SortDescriptor<Result>] = [],
        predicate: NSPredicate? = nil,
        animation: Animation? = nil,
        content: @escaping (SectionedFetchResults<SectionIdentifier, Result>) -> Content
    ) {
        _sections = SectionedFetchRequest(
            sectionIdentifier: sectionIdentifier,
            sortDescriptors: sortDescriptors,
            predicate: predicate,
            animation: animation
        )
        self.content = content
    }
    
    var body: some View {
        content(sections)
    }
    
}
