using System.Drawing;
using System.Globalization;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal sealed class TodayForm : Form
{
    private readonly AppController controller;
    private readonly Panel viewport = new() { Dock = DockStyle.Fill, AutoScroll = true, BackColor = UiPalette.Page };
    private readonly FlowLayoutPanel stack = new()
    {
        Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
        FlowDirection = FlowDirection.TopDown, WrapContents = false,
        Padding = new Padding(16), BackColor = UiPalette.Page
    };
    private readonly Panel header = new() { Height = 36, BackColor = UiPalette.Page };
    private readonly Label dateLabel = Label(9, false, UiPalette.Muted, UiPalette.Page, 20);
    private readonly RoundedCard attendanceCard = new(UiPalette.Card) { Height = 164 };
    private readonly ComboBox dayType = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly Label stateNote = Label(9, false, UiPalette.Muted, UiPalette.Card, 24);
    private readonly Label arrivalTitle = Label(9, false, UiPalette.Muted, UiPalette.Card, 20);
    private readonly Button arrivalTime = new();
    private readonly TextBox clockInput = new();
    private readonly Label arrivalNote = Label(8, false, UiPalette.Muted, UiPalette.Card, 22);
    private readonly Label departureTitle = Label(9, false, UiPalette.Muted, UiPalette.Card, 20);
    private readonly Label departureTime = Label(26, true, UiPalette.Mint, UiPalette.Card, 46);
    private readonly Label departureNote = Label(8, false, UiPalette.Muted, UiPalette.Card, 22);
    private readonly Label countdown = Label(14, true, UiPalette.Ink, UiPalette.Page, 30);
    private readonly MintProgressTrack progress = new() { Height = 6 };
    private readonly RoundedCard overtimeCard = new(UiPalette.MintWash) { Height = 128, Visible = false };
    private readonly Label overtimeTitle = Label(11, true, UiPalette.Ink, UiPalette.MintWash, 28);
    private readonly Label mealStatus = Label(9, true, UiPalette.MintDeep, UiPalette.MintWash, 36);
    private readonly Label overtimeNote = Label(8, false, UiPalette.Muted, UiPalette.MintWash, 42);
    private readonly Label lastUnlock = Label(8, false, UiPalette.Muted, UiPalette.Page, 32);
    private readonly Label errorLabel = Label(9, false, UiPalette.Warning, UiPalette.Page, 36);
    private readonly Button dayOffButton = new();
    private readonly Button editButton = new();
    private readonly TableLayoutPanel actions = new() { Height = 32, ColumnCount = 2, RowCount = 1, BackColor = UiPalette.Page };
    private readonly ContextMenuStrip moreMenu = new();
    private readonly ToolTip hints = new();
    private bool editing;
    private bool saving;
    private string editDay = "";
    private string originalClock = "";
    private string? inputError;

    public TodayForm(AppController controller, Action showSettings, Icon appIcon)
    {
        this.controller = controller;
        Text = "happylulu";
        Icon = appIcon;
        Font = new Font("Segoe UI", 10);
        BackColor = UiPalette.Page;
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(380, 414);
        MinimumSize = new Size(360, 390);
        Controls.Add(viewport);
        viewport.Controls.Add(stack);

        BuildHeader(appIcon, showSettings);
        BuildAttendanceCard();
        BuildOvertimeCard();
        BuildActions();
        AddRow(header, 4);
        AddRow(dateLabel, 8);
        AddRow(attendanceCard, 10);
        AddRow(countdown, 4);
        progress.AccessibleName = Words.T("오늘의 근무 진행률", "Today's work progress");
        AddRow(progress, 10);
        AddRow(overtimeCard, 10);
        AddRow(lastUnlock, 4);
        errorLabel.Visible = false;
        AddRow(errorLabel, 6);
        AddRow(actions, 0);
        viewport.Resize += (_, _) => LayoutWidths();
        Shown += (_, _) => LayoutWidths();
        FormClosing += (_, args) =>
        {
            if (args.CloseReason != CloseReason.UserClosing) return;
            args.Cancel = true;
            if (SaveClock()) Hide();
        };
        LayoutWidths();
        RefreshView();
    }

    private static Label Label(float size, bool bold, Color color, Color background, int height) => new()
    {
        AutoSize = false, Height = height, BackColor = background, ForeColor = color,
        Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular),
        TextAlign = ContentAlignment.MiddleLeft
    };

    private void AddRow(Control control, int gap)
    {
        control.Margin = new Padding(0, 0, 0, gap);
        stack.Controls.Add(control);
    }

    private void BuildHeader(Icon appIcon, Action showSettings)
    {
        var brand = new PictureBox
        {
            Image = appIcon.ToBitmap(), SizeMode = PictureBoxSizeMode.Zoom,
            Location = new Point(0, 3), Size = new Size(28, 28), AccessibleName = "happylulu"
        };
        var title = Label(14, true, UiPalette.Ink, UiPalette.Page, 32);
        title.Text = "happylulu";
        title.SetBounds(37, 0, 220, 32);
        var more = new Button
        {
            Text = "⋯", Size = new Size(32, 32), FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 16), BackColor = UiPalette.Page,
            ForeColor = UiPalette.Ink, AccessibleName = Words.T("더 보기", "More")
        };
        more.FlatAppearance.BorderSize = 0;
        moreMenu.Items.Add(Words.T("설정", "Settings"), null, (_, _) =>
        {
            if (SaveClock()) showSettings();
        });
        moreMenu.Items.Add(Words.T("종료", "Quit"), null, (_, _) =>
        {
            if (SaveClock()) Application.Exit();
        });
        more.Click += (_, _) => moreMenu.Show(more, new Point(0, more.Height));
        header.Controls.AddRange(new Control[] { brand, title, more });
        header.Resize += (_, _) => more.Left = Math.Max(0, header.Width - more.Width);
    }

    private void BuildAttendanceCard()
    {
        dayType.SetBounds(12, 10, 244, 28);
        dayType.AccessibleName = Words.T("오늘 근무 유형", "Today's work type");
        dayType.Items.AddRange(new object[]
        {
            new DayTypeChoice(ManualDayType.Regular, Words.T("일반근무", "Regular work")),
            new DayTypeChoice(ManualDayType.MorningHalf, Words.T("오전반차", "Morning off")),
            new DayTypeChoice(ManualDayType.AfternoonHalf, Words.T("오후반차", "Afternoon off")),
            new DayTypeChoice(ManualDayType.LuluDay, Words.T("룰루데이", "Lulu day")),
            new DayTypeChoice(ManualDayType.AnnualLeave, Words.T("연차/공가", "Annual / official leave"))
        });
        dayType.SelectionChangeCommitted += (_, _) =>
        {
            var choice = dayType.SelectedItem as DayTypeChoice;
            if (!SaveClock()) { RefreshView(); return; }
            if (choice is not null && !controller.SetDayType(choice.Type))
                RefreshView();
        };
        stateNote.SetBounds(12, 40, 300, 24);
        arrivalTitle.SetBounds(12, 66, 145, 20);
        arrivalTime.SetBounds(9, 85, 145, 46);
        arrivalTime.Font = new Font("Segoe UI", 26, FontStyle.Bold);
        arrivalTime.FlatStyle = FlatStyle.Flat;
        arrivalTime.FlatAppearance.BorderSize = 0;
        arrivalTime.BackColor = UiPalette.Card;
        arrivalTime.ForeColor = UiPalette.Mint;
        arrivalTime.TextAlign = ContentAlignment.MiddleLeft;
        arrivalTime.AccessibleName = Words.T("출근 시각 수정", "Edit arrival time");
        arrivalTime.Click += (_, _) => BeginEditing();
        clockInput.SetBounds(12, 88, 132, 42);
        clockInput.Font = new Font("Segoe UI", 24, FontStyle.Bold);
        clockInput.ForeColor = UiPalette.Mint;
        clockInput.BackColor = UiPalette.Card;
        clockInput.BorderStyle = BorderStyle.FixedSingle;
        clockInput.MaxLength = 5;
        clockInput.Visible = false;
        clockInput.AccessibleName = Words.T("출근 시각 HH:mm", "Arrival time HH:mm");
        clockInput.KeyDown += (_, args) =>
        {
            if (args.KeyCode == Keys.Enter)
            {
                args.SuppressKeyPress = true;
                if (SaveClock()) SelectNextControl(clockInput, true, true, true, true);
            }
            else if (args.KeyCode == Keys.Escape)
            {
                args.SuppressKeyPress = true;
                FinishEditing();
                inputError = null;
                RefreshView();
            }
        };
        clockInput.Leave += (_, _) => SaveClock();
        hints.SetToolTip(clockInput, Words.T("HH:mm 입력 · Enter 저장 · Esc 취소", "Enter HH:mm · Enter to save · Esc to cancel"));
        arrivalNote.SetBounds(12, 132, 145, 22);
        departureTitle.SetBounds(176, 66, 145, 20);
        departureTime.SetBounds(176, 85, 145, 46);
        departureNote.SetBounds(176, 132, 145, 22);
        attendanceCard.Controls.AddRange(new Control[]
        {
            dayType, stateNote, arrivalTitle, arrivalTime, clockInput, arrivalNote,
            departureTitle, departureTime, departureNote
        });
        attendanceCard.Resize += (_, _) =>
        {
            int column = Math.Max(125, (attendanceCard.Width - 40) / 2);
            dayType.Width = Math.Max(244, attendanceCard.Width - 24);
            stateNote.Width = attendanceCard.Width - 24;
            arrivalTitle.Width = arrivalTime.Width = arrivalNote.Width = column;
            int right = column + 28;
            departureTitle.Left = departureTime.Left = departureNote.Left = right;
            departureTitle.Width = departureTime.Width = departureNote.Width = column;
        };
    }

    private void BuildOvertimeCard()
    {
        overtimeTitle.SetBounds(12, 8, 300, 28);
        mealStatus.SetBounds(12, 36, 300, 36);
        overtimeNote.SetBounds(12, 74, 300, 42);
        overtimeCard.Controls.AddRange(new Control[] { overtimeTitle, mealStatus, overtimeNote });
        overtimeCard.Resize += (_, _) =>
        {
            overtimeTitle.Width = mealStatus.Width = overtimeNote.Width = Math.Max(150, overtimeCard.Width - 24);
        };
    }

    private void BuildActions()
    {
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        editButton.Text = Words.T("출근 시각 수정", "Edit arrival");
        editButton.Click += (_, _) => BeginEditing();
        dayOffButton.Text = Words.T("오늘 쉬는 날", "Day off today");
        dayOffButton.Click += (_, _) => SkipToday();
        foreach (Button button in new[] { editButton, dayOffButton })
        {
            button.Dock = DockStyle.Fill;
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderColor = UiPalette.Border;
            button.ForeColor = UiPalette.MintDeep;
            button.BackColor = UiPalette.Page;
            button.AccessibleName = button.Text;
        }
        editButton.Margin = new Padding(0, 0, 4, 0);
        dayOffButton.Margin = new Padding(4, 0, 0, 0);
        actions.Controls.Add(editButton, 0, 0);
        actions.Controls.Add(dayOffButton, 1, 0);
    }

    private void LayoutWidths()
    {
        int width = Math.Max(300, viewport.ClientSize.Width - stack.Padding.Horizontal -
            (viewport.VerticalScroll.Visible ? SystemInformation.VerticalScrollBarWidth : 0));
        foreach (Control row in stack.Controls) row.Width = width;
        ResizeMessages();
    }

    private static int WrappedHeight(Label label, int minimum) => Math.Max(minimum,
        TextRenderer.MeasureText(label.Text, label.Font,
            new Size(Math.Max(120, label.Width), 1000), TextFormatFlags.WordBreak).Height + 4);

    private void ResizeMessages()
    {
        countdown.Height = WrappedHeight(countdown, 30);
        lastUnlock.Height = WrappedHeight(lastUnlock, 32);
        if (errorLabel.Visible) errorLabel.Height = WrappedHeight(errorLabel, 36);
        if (!overtimeCard.Visible) return;
        mealStatus.Height = WrappedHeight(mealStatus, 36);
        overtimeNote.Top = mealStatus.Bottom + 2;
        overtimeNote.Height = WrappedHeight(overtimeNote, 42);
        overtimeCard.Height = overtimeNote.Bottom + 10;
    }

    public void RefreshView(DateTimeOffset? snapshot = null)
    {
        DateTimeOffset now = snapshot ?? controller.Now;
        string today = Attendance.DayKey(now);
        Arrival? arrival = Attendance.Today(controller.State, now);
        Arrival? storedArrival = controller.State.Arrivals.GetValueOrDefault(today);
        ManualDayType? selectedType = Attendance.EffectiveDayType(controller.State, now);
        bool annualLeave = selectedType == ManualDayType.AnnualLeave;
        bool skipped = controller.State.SuppressedDays.Contains(today);
        dateLabel.Text = Words.Korean
            ? now.ToString("M월 d일 dddd", CultureInfo.GetCultureInfo("ko-KR"))
            : now.ToString("ddd, MMM d", CultureInfo.GetCultureInfo("en-US"));
        if (!dayType.DroppedDown) dayType.SelectedIndex = (int)(selectedType ?? ManualDayType.Regular);
        arrivalTitle.Text = Words.T("출근", "Arrival");
        departureTitle.Text = Words.T("퇴근 예정", "Departure");
        if (!editing) arrivalTime.Text = storedArrival?.Time.ToString("HH:mm", CultureInfo.InvariantCulture) ?? "—";
        arrivalNote.Text = storedArrival is null ? Words.T("클릭해서 입력", "Click to enter")
            : storedArrival.Source == ArrivalSource.Unlock ? Words.T("잠금 해제", "Unlock") : Words.T("직접 입력", "Manual");
        if (arrival is null)
        {
            stateNote.Text = annualLeave ? Words.T("기존 기록은 보존해요.", "Existing arrival is preserved.")
                : skipped ? Words.T("오늘 자동 기록을 쉬고 있어요.", "Automatic recording is paused today.")
                : Words.T("출근 기록 대기", "Waiting for arrival");
            countdown.Text = annualLeave ? Words.T("오늘은 연차/공가", "Annual / official leave today")
                : skipped ? Words.T("오늘은 쉬어가요", "Taking today off")
                : Words.T("잠금 해제 후 자동으로 기록해요", "Recorded after a session unlock");
            departureTime.Text = "—";
            departureNote.Text = annualLeave || skipped ? Words.T("오늘 계산 중지", "Paused today")
                                                       : Words.T("출근 후 계산", "After arrival");
            progress.Fraction = 0;
        }
        else
        {
            DateTimeOffset leave = Attendance.Departure(arrival, controller.State.Settings);
            bool ready = Attendance.RemainingMinutes(leave, now) == 0;
            stateNote.Text = ready ? Words.T("예정 퇴근 시각이 지났어요.", "Planned departure has passed.") : "";
            countdown.Text = ready ? Words.T("오늘도 수고했어요", "Great work today")
                : Words.T("퇴근까지 ", "Leave in ") + RemainingTimeDisplay.Format(leave, now, controller.State.RemainingTimeUnit, Words.Korean);
            departureTime.Text = leave.ToString("HH:mm", CultureInfo.InvariantCulture);
            departureNote.Text = arrival.Mode != WorkdayMode.Normal ? Words.T("휴게 없이 4시간", "4 hours, no break")
                : selectedType == ManualDayType.LuluDay ? Words.T("2시간 단축", "2 hours early")
                : Words.T("휴게시간 포함", "Includes break");
            progress.Fraction = Attendance.Progress(arrival, leave, now);
        }
        OvertimeStatus? overtime = Attendance.Overtime(controller.State, now);
        overtimeCard.Visible = overtime is not null;
        if (overtime is { } status && arrival is not null)
        {
            string mealClock = Attendance.MealThresholdAt(arrival, controller.State.Settings).ToString("HH:mm", CultureInfo.InvariantCulture);
            overtimeTitle.Text = status.ElapsedMinutes >= Attendance.ExtraTimeDisplayDelayMinutes
                ? Words.T($"추가 {status.ElapsedMinutes}분 중", $"Extra {status.ElapsedMinutes} min in progress")
                : Words.T("예정 퇴근 시각 지남", "Planned departure passed");
            mealStatus.Text = status.MealThresholdReached
                ? Words.T($"식대 기준 {mealClock} · 시각 도달", $"Meal threshold {mealClock} · reached")
                : Words.T($"식대 기준 {mealClock} · {status.MinutesToMealThreshold}분 남음", $"Meal threshold {mealClock} · {status.MinutesToMealThreshold} min left");
            overtimeNote.Text = Words.T("예정 시각 기준 안내입니다. 실제 근무·식대 지급 승인 여부는 확인하지 않아요.",
                "Timing guide only; actual work and meal reimbursement approval are not verified.");
        }
        lastUnlock.Text = controller.State.LastUnlockAt is { } seen
            ? Words.T($"최근 잠금 해제 감지 · {seen:MM-dd HH:mm}", $"Last unlock detected · {seen:MMM d, HH:mm}")
            : Words.T("잠금 해제 감지 대기 · 일반 06–10시, 오전 반차 13–15시", "Waiting for unlock · full day 06–10, morning off 13–15");
        errorLabel.Text = inputError ?? controller.Error ?? "";
        errorLabel.Visible = !string.IsNullOrEmpty(errorLabel.Text);
        dayOffButton.Enabled = !skipped;
        ResizeMessages();
    }

    private void BeginEditing()
    {
        if (editing) { clockInput.Focus(); return; }
        DateTimeOffset now = controller.Now;
        editDay = Attendance.DayKey(now);
        Arrival? arrival = controller.State.Arrivals.GetValueOrDefault(editDay);
        originalClock = arrival?.Time.ToString("HH:mm", CultureInfo.InvariantCulture) ?? "";
        clockInput.Text = originalClock.Length == 0 ? now.ToString("HH:mm", CultureInfo.InvariantCulture) : originalClock;
        inputError = null;
        editing = true;
        arrivalTime.Visible = false;
        clockInput.Visible = true;
        clockInput.Focus();
        clockInput.SelectAll();
        RefreshView();
    }

    private bool SaveClock()
    {
        if (!editing || saving) return true;
        if (clockInput.Text == originalClock)
        {
            FinishEditing();
            inputError = null;
            RefreshView();
            return true;
        }
        DateTimeOffset now = controller.Now;
        if (Attendance.DayKey(now) != editDay)
            inputError = Words.T("날짜가 바뀌었어요. Esc로 취소한 뒤 오늘 시각을 다시 입력해 주세요.", "The date changed. Press Esc, then enter today's arrival again.");
        else if (!TimeOnly.TryParseExact(clockInput.Text, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out TimeOnly clock))
            inputError = Words.T("출근 시각을 HH:mm 형식으로 입력해 주세요.", "Enter arrival in HH:mm format.");
        else
        {
            DateTime local = now.LocalDateTime.Date.Add(clock.ToTimeSpan());
            if (TimeZoneInfo.Local.IsInvalidTime(local))
                inputError = Words.T("현재 시간대에 존재하지 않는 시각이에요.", "This time does not exist in the current time zone.");
            else
            {
                saving = true;
                try
                {
                    inputError = null;
                    if (controller.ManualArrival(new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local)), null))
                    {
                        FinishEditing();
                        RefreshView();
                        return true;
                    }
                }
                finally { saving = false; }
            }
        }
        RefreshView();
        return false;
    }

    private void FinishEditing()
    {
        editing = false;
        clockInput.Visible = false;
        arrivalTime.Visible = true;
    }

    private void SkipToday()
    {
        var answer = MessageBox.Show(this,
            Words.T("오늘 출근 기록과 근무 유형을 지우고 이후 자동 기록을 중지할까요? 연차/공가는 근무 유형에서 선택하면 기존 기록을 보존해요.",
                "Clear today's arrival and work type, and pause automatic recording? Choose annual / official leave to preserve the arrival."),
            Words.T("오늘 쉬는 날", "Day off today"), MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer != DialogResult.Yes) return;
        if (controller.SkipToday())
        {
            FinishEditing();
            inputError = null;
        }
        RefreshView();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            moreMenu.Dispose();
            hints.Dispose();
            foreach (PictureBox picture in header.Controls.OfType<PictureBox>()) picture.Image?.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed record DayTypeChoice(ManualDayType Type, string Label)
    {
        public override string ToString() => Label;
    }
}
