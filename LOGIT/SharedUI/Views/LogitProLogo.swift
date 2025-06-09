//
//  LogitProLogo.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.09.23.
//

import SwiftUI

struct LogitProLogo: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("LOGIT")
                .foregroundColor(.primary)
                .fontWeight(.bold)
                .fontDesign(.default)
            Text("Pro")
                .foregroundColor(.secondary)
                .fontDesign(.rounded)
                .fontWeight(.regular)
        }
    }
}

struct LogitProLogo_Previews: PreviewProvider {
    static var previews: some View {
        LogitProLogo()
    }
}
