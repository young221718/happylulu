using System.Drawing;
using System.Globalization;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal sealed class TodayForm : Form
{
    private readonly AppController controller;
    private readonly OwlStateIcons owlIcons;
    private readonly PictureBox brand = new()
    {
        SizeMode = PictureBoxSizeMode.Zoom, Location = new Point(0, 0),
        Size = new Size(28, 28), AccessibleName = "happylulu"
    };
    private readonly Panel viewport = new() { Dock = DockStyle.Fill, AutoScroll = true, BackColor = UiPalette.Page };
    private readonly FlowLayoutPanel stack = new()
    {
        Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
        FlowDirection = FlowDirection.TopDown, WrapContents = false,
        Padding = new Padding(16), BackColor = UiPalette.Page
    };
    private readonly Panel header = new() { Height = 28, BackColor = UiPalette.Page };
    private readonly RoundedCard attendanceCard = new(UiPalette.Card) { Height = 156 };
    private readonly FlowLayoutPanel dayTypes = new()
    {
        Height = 27, FlowDirection = FlowDirection.LeftToRight, WrapContents = false,
        BackColor = UiPalette.Card, Margin = Padding.Empty
    };
    private readonly Dictionary<ManualDayType, DayTypeButton> typeButtons = new();
    private readonly Label stateNote = Label(7.5f, false, UiPalette.Muted, UiPalette.Card, 18);
    private readonly Label arrivalTitle = Label(8.25f, false, UiPalette.Muted, UiPalette.Card, 18);
    private readonly Button arrivalTime = new();
    private readonly TextBox clockInput = new();
    private readonly Label departureTitle = Label(8.25f, false, UiPalette.Muted, UiPalette.Card, 18);
    private readonly Label departureTime = Label(23.25f, true, UiPalette.Mint, UiPalette.Card, 58);
    private readonly Panel timeDivider = new() { BackColor = UiPalette.Border };
    private readonly Panel divider = new() { Height = 1, BackColor = UiPalette.Border };
    private readonly Panel agenda = new() { Height = 96, BackColor = UiPalette.Page };
    private readonly Label agendaNote = Label(9, false, UiPalette.Muted, UiPalette.Page, 50);
    private readonly Label errorLabel = Label(7.5f, false, UiPalette.Warning, UiPalette.Card, 18);
    private readonly ToolStripMenuItem dayOffMenu = new();
    private readonly ToolStripMenuItem workStatusMenu = new() { Enabled = false };
    private readonly ToolStripMenuItem lastUnlockMenu = new() { Enabled = false };
    private readonly ToolStripMenuItem overtimeMenu = new() { Enabled = false, Visible = false };
    private readonly ContextMenuStrip moreMenu = new();
    private readonly ToolTip hints = new();
    private bool editing;
    private bool saving;
    private string editDay = "";
    private string originalClock = "";
    private string? inputError;
    private bool typesExpanded;
    private Point? popupAnchor;
    private ManualDayType? displayedType;
    private bool displayedExpanded;
    private int displayedTypeWidth = -1;
    private bool modalOpen;

    public TodayForm(AppController controller, Action showSettings, Icon appIcon)
    {
        this.controller = controller;
        owlIcons = new OwlStateIcons(appIcon);
        Text = "happylulu";
        Icon = appIcon;
        Font = new Font("Segoe UI", 10);
        BackColor = UiPalette.Page;
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        MaximizeBox = false;
        MinimizeBox = false;
        KeyPreview = true;
        TopMost = true;
        ClientSize = new Size(364, 350);
        Controls.Add(viewport);
        viewport.Controls.Add(stack);

        BuildHeader(showSettings);
        BuildAttendanceCard();
        BuildAgenda();
        AddRow(header, 12);
        AddRow(attendanceCard, 12);
        AddRow(divider, 12);
        AddRow(agenda, 0);
        errorLabel.Visible = false;
        viewport.Resize += (_, _) => LayoutWidths();
        Shown += (_, _) => LayoutWidths();
        Deactivate += (_, _) =>
        {
            // Tray mouse-up toggles the panel; do not dismiss it on that click's focus loss first.
            bool onAnchor = popupAnchor is { } anchor && new Rectangle(anchor.X - 16, anchor.Y - 16, 32, 32).Contains(Cursor.Position);
            if (!modalOpen && !moreMenu.Visible && !onAnchor) Dismiss();
        };
        FormClosing += (_, args) =>
        {
            if (args.CloseReason != CloseReason.UserClosing) return;
            args.Cancel = true;
            Dismiss();
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

    private void BuildHeader(Action showSettings)
    {
        var title = Label(12, true, UiPalette.Ink, UiPalette.Page, 28);
        title.Text = "happylulu";
        title.SetBounds(37, 0, 220, 28);
        var more = new Button
        {
            Text = "⋯", Size = new Size(28, 28), FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 12), BackColor = UiPalette.Page,
            ForeColor = UiPalette.Ink, AccessibleName = Words.T("더 보기", "More")
        };
        more.FlatAppearance.BorderSize = 0;
        moreMenu.Items.Add(Words.T("설정", "Settings"), null, (_, _) =>
        {
            if (Dismiss()) showSettings();
        });
        moreMenu.Items.Add(Words.T("종료", "Quit"), null, (_, _) =>
        {
            if (SaveClock()) Application.Exit();
        });
        moreMenu.Items.Add(new ToolStripSeparator());
        dayOffMenu.Text = Words.T("오늘 쉬는 날", "Day off today");
        dayOffMenu.Click += (_, _) => SkipToday();
        moreMenu.Items.Add(dayOffMenu);
        moreMenu.Items.Add(new ToolStripSeparator());
        moreMenu.Items.Add(workStatusMenu);
        moreMenu.Items.Add(lastUnlockMenu);
        moreMenu.Items.Add(overtimeMenu);
        moreMenu.Closed += (_, _) =>
        {
            if (!IsHandleCreated) return;
            BeginInvoke(new Action(() =>
            {
                if (!IsDisposed && Visible && !ContainsFocus && !modalOpen) Dismiss();
            }));
        };
        more.Click += (_, _) => moreMenu.Show(more, new Point(0, more.Height));
        header.Controls.AddRange(new Control[] { brand, title, more });
        header.Resize += (_, _) => more.Left = Math.Max(0, header.Width - more.Width);
    }

    private void BuildAttendanceCard()
    {
        dayTypes.SetBounds(10, 10, 312, 27);
        dayTypes.AccessibleName = Words.T("오늘 근무 유형", "Today's work type");
        foreach (ManualDayType type in Enum.GetValues<ManualDayType>())
        {
            var button = new DayTypeButton
            {
                Text = TypeTitle(type), AccessibleName = TypeName(type), Height = 27,
                Margin = new Padding(0, 0, 4, 0), Font = new Font("Segoe UI", 8.25f),
                BackColor = UiPalette.Card
            };
            button.Click += (_, _) => SelectType(type);
            hints.SetToolTip(button, TypeName(type));
            typeButtons.Add(type, button);
        }
        stateNote.SetBounds(10, 38, 312, 18);
        arrivalTitle.SetBounds(10, 58, 145, 18);
        arrivalTime.SetBounds(7, 76, 145, 58);
        arrivalTime.Font = new Font("Segoe UI", 23.25f, FontStyle.Bold);
        arrivalTime.FlatStyle = FlatStyle.Flat;
        arrivalTime.FlatAppearance.BorderSize = 0;
        arrivalTime.BackColor = UiPalette.Card;
        arrivalTime.ForeColor = UiPalette.Mint;
        arrivalTime.TextAlign = ContentAlignment.MiddleLeft;
        arrivalTime.AccessibleName = Words.T("출근 시각 수정", "Edit arrival time");
        arrivalTime.Click += (_, _) => BeginEditing();
        clockInput.SetBounds(10, 85, 132, 42);
        clockInput.Font = new Font("Segoe UI", 23.25f, FontStyle.Bold);
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
                CancelEditing();
            }
        };
        clockInput.Leave += (_, _) => SaveClock();
        hints.SetToolTip(clockInput, Words.T("HH:mm 입력 · Enter 저장 · Esc 취소", "Enter HH:mm · Enter to save · Esc to cancel"));
        departureTitle.SetBounds(182, 58, 140, 18);
        departureTime.SetBounds(182, 76, 140, 58);
        timeDivider.SetBounds(165, 58, 1, 52);
        errorLabel.SetBounds(10, 134, 312, 18);
        errorLabel.AutoEllipsis = true;
        attendanceCard.Controls.AddRange(new Control[]
        {
            dayTypes, stateNote, arrivalTitle, arrivalTime, clockInput,
            departureTitle, departureTime, timeDivider, errorLabel
        });
        attendanceCard.Resize += (_, _) =>
        {
            int inset = Scale(10);
            int column = Math.Max(Scale(100), (attendanceCard.Width - Scale(53)) / 2);
            dayTypes.Width = stateNote.Width = errorLabel.Width = attendanceCard.Width - inset * 2;
            arrivalTitle.Width = arrivalTime.Width = column;
            int right = inset + column + Scale(33);
            departureTitle.Left = departureTime.Left = right;
            departureTitle.Width = departureTime.Width = column;
            timeDivider.Left = inset + column + Scale(16);
            LayoutTypeButtons();
        };
    }

    private static string TypeTitle(ManualDayType type) => type switch
    {
        ManualDayType.Regular => Words.T("일반근무", "Regular"),
        ManualDayType.MorningHalf => Words.T("오전반차", "AM off"),
        ManualDayType.AfternoonHalf => Words.T("오후반차", "PM off"),
        ManualDayType.LuluDay => Words.T("룰루데이", "Lulu"),
        _ => Words.T("연차/공가", "Leave")
    };

    private static string TypeName(ManualDayType type) => type switch
    {
        ManualDayType.Regular => Words.T("일반근무", "Regular work"),
        ManualDayType.MorningHalf => Words.T("오전반차", "Morning off"),
        ManualDayType.AfternoonHalf => Words.T("오후반차", "Afternoon off"),
        ManualDayType.LuluDay => Words.T("룰루데이", "Lulu day"),
        _ => Words.T("연차/공가", "Annual / official leave")
    };

    private void SelectType(ManualDayType type)
    {
        if (!typesExpanded)
        {
            typesExpanded = true;
            LayoutTypeButtons();
            return;
        }
        if (SaveClock() && controller.SetDayType(type)) typesExpanded = false;
        RefreshView();
    }

    private void LayoutTypeButtons()
    {
        ManualDayType selected = Attendance.EffectiveDayType(controller.State, controller.Now) ?? ManualDayType.Regular;
        if (displayedType == selected && displayedExpanded == typesExpanded && displayedTypeWidth == dayTypes.ClientSize.Width) return;
        displayedType = selected;
        displayedExpanded = typesExpanded;
        displayedTypeWidth = dayTypes.ClientSize.Width;
        ManualDayType[] ordered = new[] { selected }.Concat(Enum.GetValues<ManualDayType>().Where(type => type != selected)).ToArray();
        dayTypes.SuspendLayout();
        foreach (ManualDayType type in ordered)
            typeButtons[type].Text = TypeTitle(type) + (!typesExpanded && type == selected ? " ▾" : "");
        int visibleCount = typesExpanded ? ordered.Length : 1;
        int gap = Scale(4);
        int available = Math.Max(1, dayTypes.ClientSize.Width - gap * (visibleCount - 1));
        int[] textWidths = ordered.Take(visibleCount).Select(type => TextRenderer.MeasureText(
            typeButtons[type].Text, typeButtons[type].Font, Size.Empty,
            TextFormatFlags.SingleLine | TextFormatFlags.NoPadding).Width).ToArray();
        int textTotal = textWidths.Sum();
        int padding = Math.Min(Scale(14), Math.Max(0, available - textTotal) / visibleCount);
        dayTypes.Controls.Clear();
        for (int index = 0; index < ordered.Length; index++)
        {
            ManualDayType type = ordered[index];
            DayTypeButton button = typeButtons[type];
            button.Selected = type == selected;
            button.AccessibleDescription = button.Selected
                ? (typesExpanded ? Words.T("선택됨", "Selected")
                    : Words.T("선택됨. 오늘 근무 유형 선택을 엽니다.", "Selected. Open today's workday choices."))
                : Words.T("이 근무 유형을 선택합니다.", "Select this workday type.");
            button.Visible = typesExpanded || button.Selected;
            if (index < visibleCount)
            {
                button.Width = textTotal <= available ? textWidths[index] + padding
                    : Math.Max(1, available * textWidths[index] / textTotal);
                button.Margin = new Padding(0, 0, index == visibleCount - 1 ? 0 : gap, 0);
            }
            dayTypes.Controls.Add(button);
        }
        dayTypes.ResumeLayout();
    }

    private void BuildAgenda()
    {
        var title = Label(9.75f, true, UiPalette.Ink, UiPalette.Page, 20);
        title.Text = Words.T("오늘 일정", "Today's agenda");
        title.SetBounds(0, 0, 300, 20);
        agendaNote.Text = Words.T("Windows에서 일정 연동은 아직 지원하지 않아요.",
            "Calendar integration is not available on Windows yet.");
        agendaNote.SetBounds(0, 29, 300, 50);
        agenda.Controls.AddRange(new Control[] { title, agendaNote });
        agenda.Resize += (_, _) => title.Width = agendaNote.Width = agenda.Width;
    }

    private void LayoutWidths()
    {
        int width = Math.Max(Scale(240), viewport.ClientSize.Width - stack.Padding.Horizontal -
            (viewport.VerticalScroll.Visible ? SystemInformation.VerticalScrollBarWidth : 0));
        foreach (Control row in stack.Controls) row.Width = width;
    }

    private int Scale(int value) => (int)Math.Round(value * DeviceDpi / 96.0);

    internal static Rectangle PopupBounds(Point anchor, Rectangle workingArea, Size requestedSize)
    {
        int margin = Math.Min(8, Math.Max(0, Math.Min(workingArea.Width, workingArea.Height) / 4));
        int width = Math.Min(requestedSize.Width, Math.Max(1, workingArea.Width - margin * 2));
        int height = Math.Min(requestedSize.Height, Math.Max(1, workingArea.Height - margin * 2));
        int left = Math.Clamp(anchor.X - width / 2, workingArea.Left + margin, workingArea.Right - margin - width);
        int top = anchor.Y - height - margin;
        if (top < workingArea.Top + margin) top = anchor.Y + margin;
        top = Math.Clamp(top, workingArea.Top + margin, workingArea.Bottom - margin - height);
        return new Rectangle(left, top, width, height);
    }

    internal void ShowPopover(Point anchor)
    {
        popupAnchor = anchor;
        RefreshView();
        Bounds = PopupBounds(anchor, Screen.FromPoint(anchor).WorkingArea, new Size(Scale(364), Scale(350)));
        Show();
        Activate();
    }

    internal bool Dismiss()
    {
        if (!SaveClock()) return false;
        typesExpanded = false;
        LayoutTypeButtons();
        Hide();
        return true;
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == Keys.Escape)
        {
            if (editing) CancelEditing();
            else if (typesExpanded)
            {
                typesExpanded = false;
                LayoutTypeButtons();
            }
            else Dismiss();
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        if (ClientSize.Width < 1 || ClientSize.Height < 1) return;
        using var path = RoundedCard.RoundedPath(new RectangleF(0, 0, ClientSize.Width, ClientSize.Height), Scale(20));
        Region? previous = Region;
        Region = new Region(path);
        previous?.Dispose();
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
        DateTimeOffset? departure = arrival is null ? null : Attendance.Departure(arrival, controller.State.Settings);
        OwlState iconState = annualLeave ? OwlState.AnnualLeave
            : skipped ? OwlState.DayOff
            : arrival is null ? OwlState.Waiting
            : departure <= now ? OwlState.ReadyToLeave
            : selectedType switch
            {
                ManualDayType.MorningHalf => OwlState.MorningHalf,
                ManualDayType.AfternoonHalf => OwlState.AfternoonHalf,
                ManualDayType.LuluDay => OwlState.LuluDay,
                _ => OwlState.Regular
            };
        Image iconImage = owlIcons.Get(iconState);
        if (!ReferenceEquals(brand.Image, iconImage)) brand.Image = iconImage;
        LayoutTypeButtons();
        arrivalTitle.Text = Words.T("출근", "Arrival");
        departureTitle.Text = Words.T("퇴근 예정", "Departure");
        if (!editing) arrivalTime.Text = storedArrival?.Time.ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture) ?? "—";
        hints.SetToolTip(arrivalTime, storedArrival is null ? Words.T("클릭해서 입력", "Click to enter")
            : storedArrival.Source == ArrivalSource.Unlock ? Words.T("잠금 해제", "Unlock") : Words.T("직접 입력", "Manual"));
        if (arrival is null)
        {
            stateNote.Text = annualLeave ? Words.T("연차/공가", "Leave day")
                : skipped ? Words.T("오늘 쉬는 날", "Day off today")
                : Words.T("출근 대기", "Waiting for arrival");
            workStatusMenu.Text = annualLeave ? Words.T("오늘은 연차/공가", "Annual / official leave today")
                : skipped ? Words.T("오늘은 쉬어가요", "Taking today off")
                : Words.T("잠금 해제 후 자동으로 기록해요", "Recorded after a session unlock");
            departureTime.Text = "—";
        }
        else
        {
            DateTimeOffset leave = Attendance.Departure(arrival, controller.State.Settings);
            bool ready = Attendance.RemainingMinutes(leave, now) == 0;
            stateNote.Text = ready ? Words.T("예정 퇴근 시각이 지났어요.", "Planned departure has passed.") : "";
            workStatusMenu.Text = ready ? Words.T("오늘도 수고했어요", "Great work today")
                : Words.T("퇴근까지 ", "Leave in ") + RemainingTimeDisplay.Format(leave, now, controller.State.RemainingTimeUnit, Words.Korean);
            departureTime.Text = leave.ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture);
            hints.SetToolTip(departureTime, arrival.Mode != WorkdayMode.Normal ? Words.T("휴게 없이 4시간", "4 hours, no break")
                : selectedType == ManualDayType.LuluDay ? Words.T("2시간 단축", "2 hours early")
                : Words.T("휴게시간 포함", "Includes break"));
        }
        OvertimeStatus? overtime = Attendance.Overtime(controller.State, now);
        overtimeMenu.Visible = overtime is not null;
        if (overtime is { } status && arrival is not null)
        {
            string mealClock = Attendance.MealThresholdAt(arrival, controller.State.Settings).ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture);
            string elapsed = RemainingTimeDisplay.Elapsed(Attendance.Departure(arrival, controller.State.Settings),
                now, controller.State.RemainingTimeUnit, Words.Korean);
            stateNote.Text = status.ElapsedMinutes >= Attendance.ExtraTimeDisplayDelayMinutes
                ? Words.T($"추가 {elapsed} 중", $"Extra {elapsed} in progress")
                : Words.T("예정 퇴근 시각 지남", "Planned departure passed");
            overtimeMenu.Text = status.MealThresholdReached
                ? Words.T($"식대 기준 {mealClock} · 시각 도달", $"Meal threshold {mealClock} · reached")
                : Words.T($"식대 기준 {mealClock} · {status.MinutesToMealThreshold}분 남음", $"Meal threshold {mealClock} · {status.MinutesToMealThreshold} min left");
            overtimeMenu.ToolTipText = Words.T("예정 시각 기준 안내입니다. 실제 근무·식대 지급 승인 여부는 확인하지 않아요.",
                "Timing guide only; actual work and meal reimbursement approval are not verified.");
            hints.SetToolTip(stateNote, overtimeMenu.Text + Environment.NewLine + overtimeMenu.ToolTipText);
        }
        else hints.SetToolTip(stateNote, stateNote.Text);
        lastUnlockMenu.Text = controller.State.LastUnlockAt is { } seen
            ? Words.T($"최근 잠금 해제 감지 · {seen:MM-dd HH:mm}", $"Last unlock detected · {seen:MMM d, HH:mm}")
            : Words.T("잠금 해제 감지 대기 · 일반 06–10시, 오전 반차 13–15시", "Waiting for unlock · full day 06–10, morning off 13–15");
        errorLabel.Text = inputError ?? controller.Error ?? "";
        errorLabel.Visible = !string.IsNullOrEmpty(errorLabel.Text);
        hints.SetToolTip(errorLabel, errorLabel.Text);
        dayOffMenu.Enabled = !skipped;
    }

    private void BeginEditing()
    {
        if (editing) { clockInput.Focus(); return; }
        DateTimeOffset now = controller.Now;
        editDay = Attendance.DayKey(now);
        Arrival? arrival = controller.State.Arrivals.GetValueOrDefault(editDay);
        originalClock = arrival?.Time.ToLocalTime().ToString("HH:mm", CultureInfo.InvariantCulture) ?? "";
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

    private void CancelEditing()
    {
        FinishEditing();
        inputError = null;
        RefreshView();
    }

    private void SkipToday()
    {
        DialogResult answer;
        modalOpen = true;
        try
        {
            answer = MessageBox.Show(this,
                Words.T("오늘 출근 기록과 근무 유형을 지우고 이후 자동 기록을 중지할까요? 연차/공가는 근무 유형에서 선택하면 기존 기록을 보존해요.",
                    "Clear today's arrival and work type, and pause automatic recording? Choose annual / official leave to preserve the arrival."),
                Words.T("오늘 쉬는 날", "Day off today"), MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        }
        finally { modalOpen = false; }
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
            brand.Image = null;
            owlIcons.Dispose();
        }
        base.Dispose(disposing);
    }

    private sealed class DayTypeButton : Button
    {
        private bool selected;

        [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
        public bool Selected
        {
            get => selected;
            set { selected = value; Invalidate(); }
        }

        public DayTypeButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.Clear(BackColor);
            using var path = RoundedCard.RoundedPath(new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), (Height - 1) / 2f);
            using var brush = new SolidBrush(Selected ? UiPalette.Mint : UiPalette.MintWash);
            e.Graphics.FillPath(brush, path);
            const TextFormatFlags textFlags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.SingleLine | TextFormatFlags.NoPadding;
            int textWidth = TextRenderer.MeasureText(Text, Font, Size.Empty, textFlags).Width;
            using Font? fittedFont = textWidth > ClientSize.Width
                ? new Font(Font.FontFamily, Font.Size * ClientSize.Width / textWidth, Font.Style) : null;
            TextRenderer.DrawText(e.Graphics, Text, fittedFont ?? Font, ClientRectangle,
                Selected ? Color.White : UiPalette.Ink, textFlags);
            if (Focused && ShowFocusCues)
            {
                using var focus = new Pen(UiPalette.MintDeep, 1);
                e.Graphics.DrawPath(focus, path);
            }
        }
    }
}
