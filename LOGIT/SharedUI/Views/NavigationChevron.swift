//
//  NavigationChevron.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 16.11.22.
//

import SwiftUI

struct NavigationChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.bold))
    }
}

struct NavigationChevron_Previews: PreviewProvider {
    static var previews: some View {
        NavigationChevron()
    }
}
