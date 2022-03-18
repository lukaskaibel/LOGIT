//
//  ExerciseDetailView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.01.22.
//

import SwiftUI
import CoreData


struct ExerciseDetailView: View {
    
    @Environment(\.dismiss) var dismiss
    
    @StateObject var exerciseDetail: ExerciseDetail
    
    @State private var showDeletionAlert = false
    @State private var showingEditExercise = false
    
    var body: some View {
        List {
            Section(content: {
                WeightView
            }, header: {
                Text("Weight")
                    .padding(.leading)
            })
            Section(content: {
                RepetitionsView
            }, header: {
                Text("Repetitions")
                    .padding(.leading)
            })
            Section(content: {
                ForEach(exerciseDetail.sets.indices, id:\.self) { index in
                    if let workoutSet = exerciseDetail.sets[index], workoutSet.repetitions > 0 || workoutSet.weight > 0 {
                        HStack {
                            Text(dateString(for: workoutSet))
                            Spacer()
                            if workoutSet.repetitions > 0 {
                                UnitView(value: String(workoutSet.repetitions), unit: "RPS")
                                    .padding(.horizontal, 8)
                            }
                            if workoutSet.weight > 0 {
                                if workoutSet.repetitions > 0 {
                                    dividerCircle
                                }
                                UnitView(value: String(convertWeightForDisplaying(workoutSet.weight)), unit: WeightUnit.used.rawValue.uppercased())
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
            }, header: {
                HStack {
                    Text("Sets")
                        .foregroundColor(.label)
                        .font(.title2.weight(.bold))
                        .fixedSize()
                    Spacer()
                }.padding(.vertical, 5)
                .listRowSeparator(.hidden, edges: .top)
            })
        }.listStyle(.plain)
        .navigationTitle(exerciseDetail.exercise.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu(content: {
                    Button(action: { showingEditExercise.toggle() }, label: { Label("Edit Name", systemImage: "pencil") })
                    Button(role: .destructive, action: { showDeletionAlert.toggle() }, label: { Label("Delete", systemImage: "trash") } )
                }) {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog(Text("Do you want to delete \(exerciseDetail.exercise.name ?? "")? This action can not be undone."), isPresented: $showDeletionAlert, titleVisibility: .visible) {
            Button("Delete \(exerciseDetail.exercise.name ?? "")", role: .destructive, action: {
                exerciseDetail.deleteExercise()
                dismiss()
            })
        }
        .sheet(isPresented: $showingEditExercise) {
            EditExerciseView(editExercise: EditExercise(exerciseToEdit: exerciseDetail.exercise))
        }
    }
    
    private var RepetitionsView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Personal Best")
                        .foregroundColor(.secondaryLabel)
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(exerciseDetail.personalBest(for: .repetitions)) reps")
                            .font(.title.weight(.medium))
                        Spacer()
                    }
                }
                Spacer()
            }.padding()
            BarGraph(xValues: exerciseDetail.getGraphXValues(for: .repetitions),
                      yValues: exerciseDetail.getGraphYValues(for: .repetitions),
                      barColors: [.accentColor, .accentColor, .accentColor, .accentColor, .accentColor])
                .frame(height: 120)
                .padding([.leading, .bottom])
                .padding(.trailing, 10)
            Picker("Select timeframe.", selection: $exerciseDetail.selectedCalendarComponentForRepetitions) {
                Text("Week").tag(Calendar.Component.weekOfYear)
                Text("Month").tag(Calendar.Component.month)
                Text("Year").tag(Calendar.Component.year)
            }.pickerStyle(.segmented)
                .padding([.horizontal, .bottom])
        }.background(Color.secondaryBackground)
            .cornerRadius(10)
            .listRowSeparator(.hidden)
    }
    
    private var WeightView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Personal Best")
                        .foregroundColor(.secondaryLabel)
                    HStack(alignment: .lastTextBaseline) {
                        Text("\(exerciseDetail.personalBest(for: .weight)) \(WeightUnit.used.rawValue)")
                            .font(.title.weight(.medium))
                        Spacer()
                    }
                }
                Spacer()
            }.padding()
            BarGraph(xValues: exerciseDetail.getGraphXValues(for: .weight),
                      yValues: exerciseDetail.getGraphYValues(for: .weight),
                      barColors: [.accentColor, .accentColor, .accentColor, .accentColor, .accentColor])
                .frame(height: 120)
                .padding([.leading, .bottom])
                .padding(.trailing, 10)
            Picker("Select timeframe.", selection: $exerciseDetail.selectedCalendarComponentForWeight) {
                Text("Week").tag(Calendar.Component.weekOfYear)
                Text("Month").tag(Calendar.Component.month)
                Text("Year").tag(Calendar.Component.year)
            }.pickerStyle(.segmented)
                .padding([.horizontal, .bottom])
        }.background(Color.secondaryBackground)
            .cornerRadius(10)
            .listRowSeparator(.hidden)
    }
    
    var dividerCircle: some View {
        Circle()
            .foregroundColor(.separator)
            .frame(width: 4, height: 4)
    }
    
    private func dateString(for workoutSet: WorkoutSet) -> String {
        if let date = workoutSet.setGroup?.workout?.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        } else {
            return ""
        }
    }
    
}

struct ExerciseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseDetailView(exerciseDetail: ExerciseDetail(context: Database.preview.container.viewContext, exerciseID: NSManagedObjectID()))
    }
}
