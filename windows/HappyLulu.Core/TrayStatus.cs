using System.Globalization;

namespace HappyLulu.Core;

public static class TrayStatus
{
    public static string Format(AttendanceState state, DateTimeOffset now, bool korean, TimeZoneInfo? timeZone = null)
    {
        if (Attendance.EffectiveDayType(state, now) == ManualDayType.AnnualLeave)
            return korean ? "연차 / 공가" : "Annual leave";
        Arrival? arrival = Attendance.Today(state, now);
        if (arrival is null)
            return state.SuppressedDays.Contains(Attendance.DayKey(now))
                ? (korean ? "오늘 쉬는 날" : "Day off")
                : (korean ? "출근 대기" : "Waiting for arrival");

        DateTimeOffset departure = Attendance.Departure(arrival, state.Settings);
        string clock = TimeZoneInfo.ConvertTime(departure, timeZone ?? TimeZoneInfo.Local)
            .ToString("HH:mm", CultureInfo.InvariantCulture);
        string departureText = korean ? $"퇴근 {clock}" : $"Leave {clock}";
        OvertimeStatus? overtime = Attendance.Overtime(state, now);
        if (overtime is { ElapsedMinutes: >= Attendance.ExtraTimeDisplayDelayMinutes } status)
        {
            string extra = korean ? $"추가 {status.ElapsedMinutes}분 중" : $"Extra {status.ElapsedMinutes} min in progress";
            return state.ShowDepartureInTray ? $"{departureText} · {extra}" : extra;
        }
        if (Attendance.RemainingMinutes(departure, now) == 0)
            return state.ShowDepartureInTray ? departureText : (korean ? "예정 퇴근 시각 지남" : "Planned departure passed");

        string remaining = RemainingTimeDisplay.Format(departure, now, state.RemainingTimeUnit, korean);
        if (state.ShowDepartureInTray)
            return korean ? $"{departureText} · {remaining} 남음" : $"{departureText} · {remaining} left";
        return korean ? $"퇴근 {remaining}" : $"Leave in {remaining}";
    }
}
