import Charts
import SwiftUI

struct PreferencesActivityTab: View {
    let intentStore: IntentStore

    private var days: [(date: Date, count: Int)] { intentStore.last7DaysCompletionCounts }

    private var maxInASingleDay: Int {
        days.map(\.count).max() ?? 0
    }

    private var averagePerDay: Double {
        guard !days.isEmpty else { return 0 }
        return Double(days.reduce(0) { $0 + $1.count }) / Double(days.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Completed per day, last 7 days")
                .font(.system(size: 12))
                .foregroundStyle(Color.panelTextSecondary)

            // The x-axis uses the actual Date (not a pre-formatted day-name
            // string) so Swift Charts orders bars chronologically -- a
            // categorical String axis sorts alphabetically instead (e.g. Fri
            // before Mon), which scrambled real data out of date order.
            Chart(days, id: \.date) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
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
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.panelTextSecondary)
                }
            }
            .frame(height: 160)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Most Tasks In a Single Day")
                        .foregroundStyle(Color.panelTextSecondary)
                    Text("\(maxInASingleDay)")
                        .foregroundStyle(Color.panelTextPrimary)
                }
                GridRow {
                    Text("Average Tasks / Day")
                        .foregroundStyle(Color.panelTextSecondary)
                    Text(averagePerDay.formatted(.number.precision(.fractionLength(1))))
                        .foregroundStyle(Color.panelTextPrimary)
                }
            }
            .font(.system(size: 12))
        }
    }
}
