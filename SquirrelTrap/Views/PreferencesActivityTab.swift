import Charts
import SwiftUI

struct PreferencesActivityTab: View {
    let intentStore: IntentStore

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed per day, last 7 days")
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextSecondary)

            Chart(intentStore.last7DaysCompletionCounts, id: \.date) { day in
                BarMark(
                    x: .value("Day", dayFormatter.string(from: day.date)),
                    y: .value("Completed", day.count)
                )
                .foregroundStyle(Color.accentColor)
                .annotation(position: .top) {
                    if day.count > 0 {
                        Text("\(day.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.panelTextSecondary)
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }
            .frame(height: 160)
        }
    }
}
