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
    @State private var selectedIndexInGraph: Int? = nil
    
    var body: some View {
        List {
            VStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("personalBest", comment: ""))
                        .foregroundColor(.secondaryLabel)
                    HStack {
                        Text("\(exerciseDetail.personalBest(for: exerciseDetail.selectedAttribute)) \(exerciseDetail.selectedAttribute == .repetitions ? "reps" : WeightUnit.used.rawValue)")
                            .font(.title.weight(.medium))
                        Spacer()
                        if let selectedIndexInGraph = selectedIndexInGraph {
                            Text("\(exerciseDetail.getGraphYValues(for: exerciseDetail.selectedAttribute)[selectedIndexInGraph]) \(exerciseDetail.selectedAttribute == .repetitions ? "reps" : WeightUnit.used.rawValue)")
                                .foregroundColor(.accentColor)
                                .font(.title.weight(.medium))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                LineGraph(xValues: exerciseDetail.getGraphXValues(for: exerciseDetail.selectedAttribute),
                          yValues: exerciseDetail.getGraphYValues(for: exerciseDetail.selectedAttribute),
                          selectedIndex: $selectedIndexInGraph)
                    .frame(height: 180)
                Picker("Calendar Component", selection: $exerciseDetail.selectedCalendarComponentForWeight) {
                    Text(NSLocalizedString("weekly", comment: "")).tag(Calendar.Component.weekOfYear)
                    Text(NSLocalizedString("monthly", comment: "")).tag(Calendar.Component.month)
                    Text(NSLocalizedString("yearly", comment: "")).tag(Calendar.Component.year)
                }.pickerStyle(.segmented)
                    .padding(.top)

            }.tileStyle()
                .listRowSeparator(.hidden)
            Section(content: {
                ForEach(exerciseDetail.sets) { workoutSet in
                    if workoutSet.hasEntry {
                        HStack {
                            Text(dateString(for: workoutSet))
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.vertical, 5)
                            Spacer()
                            WorkoutSetCell(workoutSet: workoutSet)
                        }
                    }
                }
            }, header: {
                HStack {
                    Text(NSLocalizedString("sets", comment: ""))
                        .foregroundColor(.label)
                        .font(.title2.weight(.bold))
                        .fixedSize()
                    Spacer()
                    Menu(NSLocalizedString("sortBy", comment: "")) {
                        Button(action: {
                            exerciseDetail.setSortingKey = .date
                        }) {
                            Label(NSLocalizedString("date", comment: ""), systemImage: "calendar")
                        }
                        Button(action: {
                            exerciseDetail.setSortingKey = .maxRepetitions
                        }) {
                            Label(NSLocalizedString("repetitions", comment: ""), systemImage: "arrow.counterclockwise")
                        }
                        Button(action: {
                            exerciseDetail.setSortingKey = .maxWeight
                        }) {
                            Label(NSLocalizedString("weight", comment: ""), systemImage: "scalemass")
                        }
                    }
                }.padding(.vertical, 5)
                .listRowSeparator(.hidden, edges: .top)
            }, footer: {
                Text("\(exerciseDetail.sets.filter { $0.hasEntry }.count) \(NSLocalizedString("set\(exerciseDetail.sets.count == 1 ? "" : "s")", comment: ""))")
                    .foregroundColor(.secondaryLabel)
                    .font(.footnote)
                    .padding(.top, 5)
                    .padding(.bottom, 50)
                    .listRowSeparator(.hidden, edges: .bottom)
            })
        }.listStyle(.plain)
        .navigationTitle(exerciseDetail.exercise.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu(content: {
                    Button(action: { showingEditExercise.toggle() }, label: { Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil") })
                    Button(role: .destructive, action: { showDeletionAlert.toggle() }, label: { Label(NSLocalizedString("delete", comment: ""), systemImage: "trash") } )
                }) {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(Text(NSLocalizedString("deleteExerciseConfirmation", comment: "")), isPresented: $showDeletionAlert, titleVisibility: .visible) {
            Button("\(NSLocalizedString("delete", comment: ""))", role: .destructive, action: {
                exerciseDetail.deleteExercise()
                dismiss()
            })
        }
        .sheet(isPresented: $showingEditExercise) {
            EditExerciseView(editExercise: EditExercise(exerciseToEdit: exerciseDetail.exercise))
        }
    }
    
    private var WeightView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("personalBest", comment: ""))
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
                Text(NSLocalizedString("weekly", comment: "")).tag(Calendar.Component.weekOfYear)
                Text(NSLocalizedString("monthly", comment: "")).tag(Calendar.Component.month)
                Text(NSLocalizedString("yearly", comment: "")).tag(Calendar.Component.year)
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
            formatter.locale = Locale.current
            formatter.dateStyle = .short
            return formatter.string(from: date)
        } else {
            return ""
        }
    }
    
}

struct ExerciseDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseDetailView(exerciseDetail: ExerciseDetail(exerciseID: NSManagedObjectID()))
    }
}
