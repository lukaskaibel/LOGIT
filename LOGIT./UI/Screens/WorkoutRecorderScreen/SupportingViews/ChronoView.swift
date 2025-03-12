//
//  ChronoView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 08.06.23.
//

import SwiftUI

struct ChronoView: View {

    // MARK: - Properties

    @ObservedObject var chronograph: Chronograph

    @State private var selectedTimerDurationIndex = 0

    // MARK: - Constants

    private let timerValues = [
        0, 10, 15, 30, 45, 60, 90, 120, 150, 180, 240, 300, 360, 420, 480, 540, 600,
    ]
    private let opacityOfTimeWhenPaused = 0.7

    // MARK: - Computed Properties

    private var remainingTimeString: String {
        "\(Int(chronograph.seconds)/60 / 10 % 6 )\(Int(chronograph.seconds)/60 % 10):\(Int(chronograph.seconds) % 60 / 10)\(Int(chronograph.seconds) % 60 % 10)"
    }

    // MARK: - View

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    if chronograph.mode != .timer {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    chronograph.mode = .timer
                } label: {
                    Text(NSLocalizedString("timer", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(chronograph.mode == .timer ? .white : .placeholder)
                }
                Spacer()
                Button {
                    if chronograph.mode != .stopwatch {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    chronograph.mode = .stopwatch
                } label: {
                    Text(NSLocalizedString("stopwatch", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(chronograph.mode == .stopwatch ? .white : .placeholder)
                }
            }
            Spacer()
            HStack {
                Spacer()
                if chronograph.mode == .timer {
                    timerIncreaseButton
                }
                Spacer()
                Text(remainingTimeString)
                    .font(.system(size: 70, weight: .regular).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer()
                if chronograph.mode == .timer {
                    timerDecreaseButton
                }
                Spacer()
            }
            Spacer()
            HStack {
                Button {
                    chronograph.cancel()
                } label: {
                    Label(NSLocalizedString("cancel", comment: ""), systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .background(Color.secondary.secondaryTranslucentBackground)
                        .cornerRadius(15)
                        .opacity(chronograph.seconds == 0 ? 0.5 : 1.0)
                }
                .disabled(chronograph.seconds == 0)
                Button {
                    chronograph.status == .running ? chronograph.stop() : chronograph.start()
                } label: {
                    Label(NSLocalizedString(chronograph.status == .running ? "pause" : "start", comment: ""), systemImage: chronograph.status == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                        .padding()
                        .background(Color.accentColor.secondaryTranslucentBackground)
                        .cornerRadius(15)
                }
                .disabled(chronograph.mode == .timer && chronograph.seconds == 0)
            }
        }
    }

    // MARK: - Subviews

    private var pickerView: some View {
        Picker("Select Timer or Stopwatch", selection: $chronograph.mode) {
            Image(systemName: "timer")
                .tag(Chronograph.Mode.timer)
            Image(systemName: "stopwatch")
                .tag(Chronograph.Mode.stopwatch)
        }
        .pickerStyle(.segmented)
    }

    private var controlButtons: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.interactiveSpring()) {
                    chronograph.status == .running ? chronograph.stop() : chronograph.start()
                }
            } label: {
                Image(systemName: chronograph.status == .running ? "pause.fill" : "play.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .font(.title2.weight(.heavy))
                    .padding()
                    .background(Color.accentColor.opacity(0.25))
                    .clipShape(Circle())
            }
            .disabled(chronograph.mode == .timer && chronograph.seconds == 0)
            if chronograph.mode == .stopwatch && chronograph.status != .idle
                || chronograph.mode == .timer && chronograph.status == .paused
            {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chronograph.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .font(.title2.weight(.heavy))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.fill)
                        .clipShape(Circle())
                }
            }
        }
    }

    private var timerIncreaseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard
                let firstLargerTimerValueIndex = timerValues.firstIndex(where: {
                    $0 >= Int(chronograph.seconds)
                }), firstLargerTimerValueIndex > 0
            else { return }
            chronograph.seconds = TimeInterval(timerValues[firstLargerTimerValueIndex - 1]) + 0.99
        } label: {
            Image(systemName: "minus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .font(.title2.weight(.heavy))
                .padding(10)
                .background(Color.fill)
                .clipShape(Circle())
        }
    }

    private var timerDecreaseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard
                let firstLargerTimerValueIndex = timerValues.firstIndex(where: {
                    $0 > Int(chronograph.seconds)
                }), firstLargerTimerValueIndex > 0
            else { return }
            chronograph.seconds = TimeInterval(timerValues[firstLargerTimerValueIndex]) + 0.99
        } label: {
            Image(systemName: "plus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .font(.title2.weight(.heavy))
                .padding(10)
                .background(Color.fill)
                .clipShape(Circle())
        }
    }

}

struct TimerView_Previews: PreviewProvider {
    static var previews: some View {
        ChronoView(chronograph: Chronograph())
            .padding()
            .tileStyle()
    }
}
