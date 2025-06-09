//
//  SetChangerView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.12.21.
//

import SwiftUI

struct SetChangerView: View {
    @Binding var workoutSet: WorkoutSet

    var body: some View {
        List {
            Section(
                content: {
                    Picker(
                        "Repetitions",
                        selection: $workoutSet.repetitions,
                        content: {
                            ForEach(0 ..< 10000, id: \.self) { i in
                                Text(String(i))
                            }
                        }
                    )
                    .pickerStyle(WheelPickerStyle())
                },
                header: {
                    Text("Repetitions")
                }
            )
            Section(
                content: {
                    Picker(
                        "Weight",
                        selection: $workoutSet.weight,
                        content: {
                            ForEach(0 ..< 10000, id: \.self) { i in
                                Text(String(i))
                            }
                        }
                    )
                    .pickerStyle(WheelPickerStyle())
                },
                header: {
                    Text("Weight")
                }
            )
            Section(
                content: {
                    Picker(
                        "time",
                        selection: $workoutSet.time,
                        content: {
                            ForEach(0 ..< 10000, id: \.self) { i in
                                Text(String(i))
                            }
                        }
                    )
                    .pickerStyle(WheelPickerStyle())
                },
                header: {
                    Text("Duration")
                }
            )
        }
    }
}

struct SetChangerView_Previews: PreviewProvider {
    static var previews: some View {
        SetChangerView(workoutSet: .constant(Workout.testWorkout.sets!.array.first as! WorkoutSet))
    }
}
