using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal sealed class SettingsForm : Form
{
    private static readonly Color SidebarSurface = Color.FromArgb(244, 244, 246);
    private static readonly Color GroupSurface = Color.FromArgb(245, 245, 247);
    private static readonly Color SelectionSurface = Color.FromArgb(225, 226, 230);
    private readonly AppController controller;
    private readonly ComboBox language = Choice();
    private readonly ComboBox remainingUnit = Choice();
    private readonly CheckBox startup = new SettingsSwitch();
    private readonly Label startupHint = Help("");
    private readonly Label countdownPreview = Preview("");
    private readonly Label workPreview = Preview("");
    private readonly Label restPreview = Preview("");
    private readonly TextBox dataPath = new() { ReadOnly = true, Dock = DockStyle.Fill };
    private readonly NumericUpDown work = new() { Minimum = 60, Maximum = 960, Increment = 30, Width = 120 };
    private readonly NumericUpDown rest = new() { Minimum = 0, Maximum = 240, Increment = 15, Width = 120 };
    private readonly Panel content = new() { Dock = DockStyle.Fill, Margin = Padding.Empty };
    private readonly List<(Button Button, Control Page)> pages = new();
    private readonly TableLayoutPanel calendar = new() { Dock = DockStyle.Fill, ColumnCount = 7, RowCount = 6 };
    private readonly Label monthLabel = new() { AutoSize = true, Anchor = AnchorStyles.Left };
    private readonly Label dayDetail = new() { AutoSize = false, Dock = DockStyle.Fill, Padding = new Padding(14) };
    private readonly Button previousMonth = new();
    private readonly Button nextMonth = new();
    private readonly Label error = new() { Dock = DockStyle.Bottom, Height = 48, ForeColor = Color.DarkOrange };
    private DateOnly month = new(DateTime.Today.Year, DateTime.Today.Month, 1);
    private DateOnly selectedDay = DateOnly.FromDateTime(DateTime.Today);
    private bool refreshing;
    private bool settingsLoaded;

    public SettingsForm(AppController controller, Icon appIcon)
    {
        this.controller = controller;
        Text = Words.T("happylulu 설정", "happylulu Settings");
        Icon = appIcon;
        Font = new Font("Segoe UI", 10);
        ForeColor = UiPalette.Ink;
        BackColor = UiPalette.Page;
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(960, 700);
        MinimumSize = new Size(820, 620);

        var shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1 };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 205));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var sidebar = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            BackColor = SidebarSurface, Padding = new Padding(10, 20, 10, 14), AutoScroll = true,
            Margin = Padding.Empty
        };
        var brand = new FlowLayoutPanel
        {
            AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false, Margin = new Padding(6, 0, 0, 22)
        };
        brand.Controls.Add(new PictureBox
        {
            Image = appIcon.ToBitmap(), SizeMode = PictureBoxSizeMode.Zoom,
            Size = new Size(24, 24), Margin = new Padding(0, 1, 8, 0), AccessibleName = "happylulu"
        });
        brand.Controls.Add(new Label
        {
            Text = "happylulu", Font = new Font(Font.FontFamily, 14, FontStyle.Bold),
            AutoSize = true, Margin = Padding.Empty
        });
        sidebar.Controls.Add(brand);
        sidebar.Controls.Add(new Label
        {
            Text = Words.T("기본 설정", "Core settings"), AutoSize = true,
            ForeColor = UiPalette.Muted, Font = new Font(Font.FontFamily, 9), Margin = new Padding(8, 0, 0, 8)
        });
        AddPage(sidebar, Words.T("일반", "General"), "\uE713", GeneralPage());
        AddPage(sidebar, Words.T("근무", "Work"), "\uE917", WorkPage());
        AddPage(sidebar, Words.T("출근 기록", "Attendance"), "\uE787", HistoryPage());
        sidebar.Controls.Add(new Label
        {
            Text = $"Windows · {Application.ProductVersion.Split('+')[0]}", AutoSize = true,
            ForeColor = UiPalette.Muted, Font = new Font(Font.FontFamily, 8),
            Margin = new Padding(8, 24, 0, 0)
        });
        shell.Controls.Add(sidebar, 0, 0);
        shell.Controls.Add(content, 1, 0);
        Controls.Add(shell);
        error.BackColor = UiPalette.Page;
        error.Padding = new Padding(16, 6, 16, 0);
        Controls.Add(error);
        SelectPage(pages[0].Page);
        FormClosing += (_, args) =>
        {
            if (args.CloseReason == CloseReason.UserClosing)
            {
                args.Cancel = true;
                Hide();
            }
        };
        RefreshView();
    }

    private void AddPage(FlowLayoutPanel sidebar, string title, string symbol, Control page)
    {
        var button = new SettingsNavigationButton(symbol)
        {
            Text = title, AccessibleName = title, Width = 181, Height = 38,
            TextAlign = ContentAlignment.MiddleLeft, FlatStyle = FlatStyle.Flat,
            Padding = new Padding(12, 0, 0, 0), Margin = new Padding(0, 0, 0, 5),
            UseVisualStyleBackColor = false
        };
        button.FlatAppearance.BorderSize = 0;
        button.Click += (_, _) => SelectPage(page);
        pages.Add((button, page));
        page.Dock = DockStyle.Fill;
        content.Controls.Add(page);
        sidebar.Controls.Add(button);
    }

    private void SelectPage(Control selected)
    {
        foreach (var (button, page) in pages)
        {
            bool active = page == selected;
            page.Visible = active;
            button.BackColor = active ? SelectionSurface : SidebarSurface;
            button.ForeColor = UiPalette.Ink;
            button.AccessibleDescription = active ? Words.T("선택됨", "Selected") : "";
        }
        selected.BringToFront();
    }

    private Control GeneralPage()
    {
        FlowLayoutPanel stack = PageStack(Words.T("일반", "General"),
            Words.T("언어와 앱 실행 방식을 관리합니다.", "Manage language and app launch behavior."));
        SettingsGroup group = Group(Words.T("일반", "General"));
        group.Controls.Add(PreviewHeader());
        language.Items.AddRange(new object[]
        {
            Words.T("시스템 언어", "System language"), "한국어", "English"
        });
        language.AccessibleName = Words.T("표시 언어", "Display language");
        language.SelectedIndexChanged += (_, _) =>
        {
            if (refreshing || language.SelectedIndex < 0) return;
            if (!controller.SetLanguage((UiLanguage)language.SelectedIndex))
            {
                refreshing = true;
                language.SelectedIndex = (int)controller.State.Language;
                refreshing = false;
            }
        };
        group.Controls.Add(SettingRow(Words.T("언어", "Language"),
            Preview(Words.T("안녕하세요, happylulu예요", "Hello from happylulu")), language));
        remainingUnit.Items.AddRange(new object[]
        {
            Words.T("시간/분 (기본)", "Hours/minutes (default)"),
            Words.T("밀리초", "Milliseconds"), Words.T("초", "Seconds"),
            Words.T("분", "Minutes"), Words.T("시간", "Hours")
        });
        remainingUnit.AccessibleName = Words.T("남은 시간 표시", "Remaining time display");
        remainingUnit.SelectedIndexChanged += (_, _) =>
        {
            RefreshPreviews();
            if (refreshing || remainingUnit.SelectedIndex < 0) return;
            if (!controller.SetRemainingTimeUnit((RemainingTimeUnit)remainingUnit.SelectedIndex))
            {
                refreshing = true;
                remainingUnit.SelectedIndex = (int)controller.State.RemainingTimeUnit;
                refreshing = false;
                RefreshPreviews();
            }
        };
        group.Controls.Add(SettingRow(Words.T("퇴근까지 남은 시간 표시", "Countdown display"),
            countdownPreview, remainingUnit));
        startup.Text = "";
        startup.AccessibleName = Words.T("Windows 로그인 시 자동 실행", "Start when signing in to Windows");
        startup.CheckedChanged += (_, _) =>
        {
            if (refreshing) return;
            try
            {
                StartupRegistration.SetEnabled(startup.Checked);
                startupHint.Text = Words.T("자동 실행 설정을 저장했습니다.", "Startup preference saved.");
            }
            catch (Exception ex)
            {
                startupHint.Text = ex.Message;
                SyncStartup();
            }
        };
        group.Controls.Add(SettingRow(Words.T("로그인 시 자동 실행", "Launch at login"),
            Help(Words.T("Windows 로그인 시 이 앱을 실행합니다.", "Opens the app when you sign in to Windows.")), startup));
        stack.Controls.Add(group);
        startupHint.Text = Words.T("이 앱 파일을 옮기면 자동 실행을 다시 설정해야 합니다.",
                                   "Set startup again if you move this portable app.");
        stack.Controls.Add(startupHint);
        SettingsGroup records = Group(Words.T("로컬 기록 파일", "Local attendance file"));
        dataPath.Text = controller.DataPath;
        dataPath.AccessibleName = Words.T("로컬 기록 파일 경로", "Local attendance file path");
        records.Controls.Add(dataPath);
        records.Controls.Add(Help(Words.T("기록은 이 PC에만 저장됩니다. 창을 열어도 자동 실행 설정은 바뀌지 않습니다.",
                           "Records stay on this PC. Opening Settings does not change startup.")));
        stack.Controls.Add(records);
        return stack;
    }

    private Control WorkPage()
    {
        FlowLayoutPanel stack = PageStack(Words.T("근무", "Work"),
            Words.T("근무 시간과 휴게 시간을 설정합니다.", "Set your work and break hours."));
        SettingsGroup group = Group(Words.T("근무", "Work"));
        work.AccessibleName = Words.T("근무 시간 (분)", "Work minutes");
        rest.AccessibleName = Words.T("휴게 시간 (분)", "Break minutes");
        work.ValueChanged += (_, _) => RefreshPreviews();
        rest.ValueChanged += (_, _) => RefreshPreviews();
        group.Controls.Add(SettingRow(Words.T("근무 시간", "Work time"), workPreview, work));
        group.Controls.Add(SettingRow(Words.T("휴게 시간", "Break time"), restPreview, rest));
        var apply = new Button
        {
            Text = Words.T("근무 시간 저장", "Save work hours"), AutoSize = true,
            BackColor = SystemColors.Highlight, ForeColor = Color.White, FlatStyle = FlatStyle.Flat,
            Padding = new Padding(12, 6, 12, 6), Margin = new Padding(0, 12, 0, 18)
        };
        apply.FlatAppearance.BorderSize = 0;
        apply.FlatAppearance.MouseOverBackColor = SystemColors.HotTrack;
        apply.Click += (_, _) =>
        {
            if (!controller.SetWork((int)work.Value, (int)rest.Value))
                MessageBox.Show(this, controller.Error ?? Words.T("저장할 수 없어요.", "Could not save."),
                    "happylulu", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        };
        group.Controls.Add(apply);
        group.Controls.Add(Help(Words.T(
            "일반 근무는 근무·휴게 시간을 더합니다. 자동 일반 근무는 마지막 금요일에 2시간 단축됩니다. 오늘 유형을 일반 근무로 직접 고르면 단축하지 않고, 룰루데이는 2시간 단축합니다. 반차는 휴게 없이 4시간입니다.",
            "Full days include work and break. Automatic full days end 2 hours earlier on the last Friday. Choosing Full day explicitly removes the reduction; Lulu day reduces it by 2 hours. Half days last 4 hours without a break.")));
        group.Controls.Add(Help(Words.T(
            "오늘의 근무 유형과 출근 시각은 트레이의 오늘 창에서 바꿀 수 있어요.",
            "Change today's work type and arrival time in the Today window from the tray.")));
        stack.Controls.Add(group);
        return stack;
    }

    private Control HistoryPage()
    {
        var viewport = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = UiPalette.Page };
        var page = new TableLayoutPanel
        {
            Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1, RowCount = 6,
            BackColor = UiPalette.Page, Padding = new Padding(28, 24, 28, 16)
        };
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 84));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        // Keep six weeks readable at the minimum window size; the page scrolls instead of shrinking cells.
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 564));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 156));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        var heading = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false };
        heading.Controls.Add(Heading(Words.T("출근 기록", "Attendance"), 26));
        heading.Controls.Add(Help(Words.T("저장된 출근 기록을 월별로 확인합니다.", "Browse saved arrivals by month.")));
        page.Controls.Add(heading, 0, 0);
        var navigation = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 5, RowCount = 1 };
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 62));
        ConfigureMonthButton(previousMonth, "‹", Words.T("이전 달", "Previous month"));
        ConfigureMonthButton(nextMonth, "›", Words.T("다음 달", "Next month"));
        previousMonth.Click += (_, _) => ChangeMonth(-1);
        nextMonth.Click += (_, _) => ChangeMonth(1);
        var today = new Button { Text = Words.T("오늘", "Today"), Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat };
        today.FlatAppearance.BorderColor = UiPalette.Border;
        today.Click += (_, _) =>
        {
            selectedDay = DateOnly.FromDateTime(DateTime.Today);
            month = new DateOnly(selectedDay.Year, selectedDay.Month, 1);
            RefreshHistory();
        };
        monthLabel.Font = new Font(Font.FontFamily, 14, FontStyle.Bold);
        navigation.Controls.Add(previousMonth, 0, 0);
        navigation.Controls.Add(monthLabel, 1, 0);
        navigation.Controls.Add(nextMonth, 2, 0);
        navigation.Controls.Add(today, 4, 0);
        page.Controls.Add(navigation, 0, 1);
        var weekdays = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 7, RowCount = 1 };
        string[] names = Words.Korean ? ["일", "월", "화", "수", "목", "금", "토"] : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        for (int column = 0; column < 7; column++)
        {
            weekdays.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / 7));
            calendar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / 7));
            weekdays.Controls.Add(new Label
            {
                Text = names[column], Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter,
                ForeColor = UiPalette.Muted, Font = new Font(Font.FontFamily, 9)
            }, column, 0);
        }
        for (int row = 0; row < 6; row++) calendar.RowStyles.Add(new RowStyle(SizeType.Percent, 100f / 6));
        page.Controls.Add(weekdays, 0, 2);
        page.Controls.Add(calendar, 0, 3);
        dayDetail.BackColor = UiPalette.Page;
        dayDetail.Font = new Font(Font.FontFamily, 10);
        dayDetail.Margin = new Padding(0, 12, 0, 0);
        dayDetail.AccessibleName = Words.T("선택한 날짜의 출근 기록", "Attendance for the selected day");
        page.Controls.Add(dayDetail, 0, 4);
        page.Controls.Add(Help(Words.T("양력 달력 · 출근 날짜와 시각은 기록 당시 시간대로 표시합니다.",
                                     "Gregorian calendar · arrivals use their recorded time zone.")), 0, 5);
        viewport.Controls.Add(page);
        return viewport;
    }

    private void ChangeMonth(int offset)
    {
        month = month.AddMonths(offset);
        selectedDay = new DateOnly(month.Year, month.Month, Math.Min(selectedDay.Day, DateTime.DaysInMonth(month.Year, month.Month)));
        RefreshHistory();
    }

    private static void ConfigureMonthButton(Button button, string text, string name)
    {
        button.Text = text;
        button.AccessibleName = name;
        button.Dock = DockStyle.Fill;
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
    }

    private void RefreshHistory()
    {
        CultureInfo culture = CultureInfo.GetCultureInfo(Words.Korean ? "ko-KR" : "en-US");
        monthLabel.Text = month.ToDateTime(TimeOnly.MinValue).ToString(Words.Korean ? "yyyy년 M월" : "MMMM yyyy", culture);
        previousMonth.Enabled = month.Year > 1 || month.Month > 1;
        nextMonth.Enabled = month.Year < 9999 || month.Month < 12;
        calendar.SuspendLayout();
        try
        {
            foreach (Control cell in calendar.Controls.Cast<Control>().ToArray()) cell.Dispose();
            calendar.Controls.Clear();
            int offset = (int)month.DayOfWeek;
            int days = DateTime.DaysInMonth(month.Year, month.Month);
            for (int slot = 0; slot < 42; slot++)
            {
                int number = slot - offset + 1;
                if (number < 1 || number > days) continue;
                var date = new DateOnly(month.Year, month.Month, number);
                string key = date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                controller.State.Arrivals.TryGetValue(key, out Arrival? arrival);
                bool hasType = controller.State.ManualDayTypes.TryGetValue(key, out ManualDayType type);
                bool skipped = controller.State.SuppressedDays.Contains(key);
                string note = hasType && type == ManualDayType.AnnualLeave ? Words.T("연차/공가", "Leave")
                    : arrival is not null ? arrival.Time.ToString("HH:mm", CultureInfo.InvariantCulture)
                    : hasType ? DayTypeLabel(type) : skipped ? Words.T("쉬는 날", "Day off") : "";
                var day = new SettingsCalendarDay
                {
                    Dock = DockStyle.Fill, Margin = new Padding(2), FlatStyle = FlatStyle.Flat,
                    Text = number + (note.Length == 0 ? "" : "\n" + note),
                    AccessibleName = key + (note.Length == 0 ? Words.T(" 기록 없음", " No record") : " " + note),
                    BackColor = date == selectedDay ? Color.FromArgb(214, 233, 229) : GroupSurface,
                    ForeColor = date == DateOnly.FromDateTime(DateTime.Today) ? Color.FromArgb(41, 122, 107) : UiPalette.Ink,
                    Font = new Font(Font.FontFamily, 10), UseVisualStyleBackColor = false, Tag = date
                };
                day.FlatAppearance.BorderColor = date == selectedDay ? Color.FromArgb(41, 122, 107) : GroupSurface;
                day.Click += (_, _) => SelectHistoryDay(date);
                calendar.Controls.Add(day, slot % 7, slot / 7);
            }
        }
        finally { calendar.ResumeLayout(); }
        RefreshDayDetail(culture);
    }

    private void SelectHistoryDay(DateOnly date)
    {
        selectedDay = date;
        foreach (Button day in calendar.Controls.OfType<Button>())
        {
            bool selected = day.Tag is DateOnly value && value == selectedDay;
            day.BackColor = selected ? Color.FromArgb(214, 233, 229) : GroupSurface;
            day.FlatAppearance.BorderColor = selected ? Color.FromArgb(41, 122, 107) : GroupSurface;
        }
        RefreshDayDetail(CultureInfo.GetCultureInfo(Words.Korean ? "ko-KR" : "en-US"));
    }

    private void RefreshDayDetail(CultureInfo culture)
    {
        string key = selectedDay.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var lines = new List<string>
        {
            selectedDay.ToDateTime(TimeOnly.MinValue).ToString(Words.Korean ? "yyyy년 M월 d일 dddd" : "dddd, MMMM d, yyyy", culture)
        };
        bool hasType = controller.State.ManualDayTypes.TryGetValue(key, out ManualDayType type);
        if (hasType) lines.Add(DayTypeLabel(type) + Words.T(" · 직접 지정", " · Chosen manually"));
        if (controller.State.Arrivals.TryGetValue(key, out Arrival? arrival))
        {
            if (hasType && type == ManualDayType.AnnualLeave)
                lines.Add(Words.T("연차 지정 전의 출근 기록을 보존했어요.", "Arrival saved before annual leave is preserved."));
            lines.Add(Words.T("출근 ", "Arrived ") + arrival.Time.ToString("HH:mm", CultureInfo.InvariantCulture) + " · " + Words.Mode(arrival.Mode));
            lines.Add(arrival.Source == ArrivalSource.Unlock ? Words.T("잠금 해제 감지", "Unlock detected") : Words.T("직접 입력", "Manual entry"));
            lines.Add(Words.T("기록 시간대: UTC", "Recorded time zone: UTC") + arrival.Time.ToString("zzz", CultureInfo.InvariantCulture));
        }
        else
        {
            lines.Add(controller.State.SuppressedDays.Contains(key)
                ? Words.T("자동 기록을 쉬는 날이에요.", "Automatic recording is paused for this day.")
                : Words.T("저장된 출근 기록이 없어요.", "No arrival saved for this day."));
        }
        dayDetail.Text = string.Join(Environment.NewLine, lines);
    }

    private static string DayTypeLabel(ManualDayType type) => type switch
    {
        ManualDayType.Regular => Words.T("일반 근무", "Full day"),
        ManualDayType.MorningHalf => Words.T("오전 반차", "Morning off"),
        ManualDayType.AfternoonHalf => Words.T("오후 반차", "Afternoon off"),
        ManualDayType.LuluDay => Words.T("룰루데이", "Lulu day"),
        ManualDayType.AnnualLeave => Words.T("연차/공가", "Annual/official leave"),
        _ => throw new ArgumentOutOfRangeException(nameof(type))
    };

    private FlowLayoutPanel PageStack(string title, string description)
    {
        var stack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            AutoScroll = true, Padding = new Padding(28, 24, 28, 20), BackColor = UiPalette.Page
        };
        stack.Controls.Add(Heading(title, 26));
        Label intro = Help(description);
        intro.Margin = new Padding(0, 6, 0, 22);
        stack.Controls.Add(intro);
        stack.SizeChanged += (_, _) => FitStack(stack);
        return stack;
    }

    private static void FitStack(FlowLayoutPanel stack)
    {
        int width = Math.Max(200, stack.ClientSize.Width - stack.Padding.Horizontal -
            (stack.AutoScroll ? SystemInformation.VerticalScrollBarWidth : 0));
        foreach (Control child in stack.Controls)
        {
            if (child is TableLayoutPanel || child is SettingsGroup)
            {
                // Flow layout otherwise replaces Width with the auto-sized preferred width.
                child.MinimumSize = new Size(width, 0);
                child.MaximumSize = new Size(width, 0);
                child.Width = width;
            }
            if (child is TextBox) child.Width = width;
            if (child is Label label) label.MaximumSize = new Size(width, 0);
        }
    }

    private static SettingsGroup Group(string title)
    {
        var group = new SettingsGroup();
        group.Controls.Add(Heading(title, 12));
        group.SizeChanged += (_, _) => FitStack(group);
        return group;
    }

    private static TableLayoutPanel PreviewHeader()
    {
        var row = new SettingsRow
        {
            AutoSize = true, ColumnCount = 3, RowCount = 1, Width = 660,
            BackColor = Color.Transparent, Margin = new Padding(0, 4, 0, 10)
        };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
        row.Controls.Add(Help(Words.T("미리보기", "Preview")), 1, 0);
        row.SizeChanged += (_, _) => FitSettingColumns(row);
        return row;
    }

    private static TableLayoutPanel SettingRow(string title, Label example, Control control)
    {
        var row = new SettingsRow
        {
            AutoSize = true, ColumnCount = 3, RowCount = 1, Width = 660,
            BackColor = Color.Transparent, Padding = Padding.Empty, Margin = new Padding(0, 0, 0, 20)
        };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
        var label = new Label
        {
            Text = title, AutoSize = true, Anchor = AnchorStyles.Left,
            MaximumSize = new Size(180, 0), Margin = new Padding(0, 0, 10, 0)
        };
        row.Controls.Add(label, 0, 0);
        example.Dock = DockStyle.Fill;
        example.Margin = new Padding(0, 0, 12, 0);
        row.Controls.Add(example, 1, 0);
        control.Anchor = AnchorStyles.Right;
        row.Controls.Add(control, 2, 0);
        row.SizeChanged += (_, _) => FitSettingColumns(row);
        return row;
    }

    private static void FitSettingColumns(TableLayoutPanel row)
    {
        if (row.ColumnStyles.Count < 3) return;
        int Scale(int value) => (int)Math.Round(value * row.DeviceDpi / 96f);
        int controlWidth = Scale(190);
        // Give long labels room at the default size while preserving the preview at the minimum size.
        int labelWidth = Math.Min(Scale(190), Math.Max(Scale(140), row.ClientSize.Width - controlWidth - Scale(152)));
        if (row.ColumnStyles[0].Width != labelWidth) row.ColumnStyles[0].Width = labelWidth;
        if (row.ColumnStyles[2].Width != controlWidth) row.ColumnStyles[2].Width = controlWidth;
        if (row.GetControlFromPosition(0, 0) is Label label)
        {
            var limit = new Size(Math.Max(1, labelWidth - label.Margin.Horizontal), 0);
            if (label.MaximumSize != limit) label.MaximumSize = limit;
        }
        if (row.GetControlFromPosition(1, 0) is Label example)
        {
            var limit = new Size(Math.Max(60, row.ClientSize.Width - labelWidth - controlWidth - example.Margin.Horizontal), 0);
            if (example.MaximumSize != limit) example.MaximumSize = limit;
        }
    }

    private static ComboBox Choice() => new() { Width = 184, DropDownStyle = ComboBoxStyle.DropDownList };
    private static Label Heading(string text, int size) => new()
    {
        Text = text, AutoSize = true, Font = new Font("Segoe UI", size, FontStyle.Bold),
        Margin = new Padding(0, 0, 0, 6)
    };
    private static Label Help(string text) => new()
    {
        Text = text, AutoSize = true, ForeColor = UiPalette.Muted,
        MaximumSize = new Size(610, 0), Margin = new Padding(0, 4, 0, 12)
    };

    private static Label Preview(string text) => new()
    {
        Text = text, AutoSize = true, BackColor = Color.Transparent,
        AccessibleName = Words.T("표시 예시", "Display example")
    };

    private void RefreshPreviews()
    {
        // Match the Mac's fictional example without reading attendance or a clock.
        var now = new DateTimeOffset(2000, 1, 1, 0, 0, 0, TimeSpan.Zero);
        RemainingTimeUnit unit = remainingUnit.SelectedIndex >= 0
            ? (RemainingTimeUnit)remainingUnit.SelectedIndex : controller.State.RemainingTimeUnit;
        string remaining = RemainingTimeDisplay.Format(now.AddSeconds(5320), now, unit, Words.Korean);
        countdownPreview.Text = remaining + Words.T(" 남음", " left");
        workPreview.Text = Words.Duration((int)work.Value);
        restPreview.Text = Words.Duration((int)rest.Value);
    }

    public void RefreshView()
    {
        if (!settingsLoaded)
        {
            SyncStartup();
            refreshing = true;
            language.SelectedIndex = (int)controller.State.Language;
            remainingUnit.SelectedIndex = (int)controller.State.RemainingTimeUnit;
            work.Value = controller.State.Settings.WorkMinutes;
            rest.Value = controller.State.Settings.BreakMinutes;
            refreshing = false;
            settingsLoaded = true;
        }
        RefreshPreviews();
        RefreshHistory();
        error.Text = controller.Error ?? "";
        error.Visible = error.Text.Length > 0;
    }

    private void SyncStartup()
    {
        refreshing = true;
        try { startup.Checked = StartupRegistration.Enabled(); }
        catch (Exception ex) { startupHint.Text = ex.Message; }
        finally { refreshing = false; }
    }

    private sealed class SettingsRow : TableLayoutPanel
    {
        protected override void ScaleControl(SizeF factor, BoundsSpecified specified)
        {
            base.ScaleControl(factor, specified);
            // TableLayoutPanel scales absolute column styles after the bounds change.
            FitSettingColumns(this);
        }

        protected override void OnLayout(LayoutEventArgs e)
        {
            FitSettingColumns(this);
            base.OnLayout(e);
        }
    }

    private sealed class SettingsGroup : FlowLayoutPanel
    {
        public SettingsGroup()
        {
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            FlowDirection = FlowDirection.TopDown;
            WrapContents = false;
            Width = 660;
            Padding = new Padding(14);
            Margin = new Padding(0, 0, 0, 20);
            BackColor = GroupSurface;
            DoubleBuffered = true;
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(Parent?.BackColor ?? UiPalette.Page);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using GraphicsPath path = RoundedCard.RoundedPath(new RectangleF(0, 0, Width - 1, Height - 1), 10f * DeviceDpi / 96);
            using var brush = new SolidBrush(GroupSurface);
            e.Graphics.FillPath(brush, path);
        }
    }

    private sealed class SettingsNavigationButton(string symbol) : Button
    {
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(SidebarSurface);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            int Scale(int value) => (int)Math.Round(value * DeviceDpi / 96f);
            bool hovered = ClientRectangle.Contains(PointToClient(MousePosition));
            using GraphicsPath path = RoundedCard.RoundedPath(new RectangleF(0, 0, Width - 1, Height - 1), Scale(6));
            using var brush = new SolidBrush(hovered && BackColor == SidebarSurface ? Color.FromArgb(234, 234, 238) : BackColor);
            e.Graphics.FillPath(brush, path);
            using var iconFont = new Font("Segoe Fluent Icons", 12);
            TextRenderer.DrawText(e.Graphics, symbol, iconFont, new Rectangle(Scale(10), 0, Scale(24), Height), ForeColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(Scale(42), 0, Width - Scale(48), Height), ForeColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -3, -3), ForeColor, BackColor);
        }
    }

    private sealed class SettingsSwitch : CheckBox
    {
        public SettingsSwitch()
        {
            AutoSize = false;
            Size = new Size(42, 26);
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer, true);
            CheckedChanged += (_, _) => Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(GroupSurface);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            float scale = Height / 26f;
            using GraphicsPath track = RoundedCard.RoundedPath(new RectangleF(2 * scale, 3 * scale, 38 * scale, 20 * scale), 10 * scale);
            using var trackBrush = new SolidBrush(Checked && Enabled ? SystemColors.Highlight : Color.FromArgb(196, 198, 204));
            using var knob = new SolidBrush(Enabled ? Color.White : Color.FromArgb(235, 235, 238));
            e.Graphics.FillPath(trackBrush, track);
            e.Graphics.FillEllipse(knob, (Checked ? 23 : 5) * scale, 6 * scale, 14 * scale, 14 * scale);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics, ClientRectangle, UiPalette.Ink, GroupSurface);
        }
    }

    private sealed class SettingsCalendarDay : Button
    {
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(UiPalette.Page);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            int inset = (int)Math.Round(8f * DeviceDpi / 96);
            using GraphicsPath path = RoundedCard.RoundedPath(new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), 6f * DeviceDpi / 96);
            using var brush = new SolidBrush(BackColor);
            using var border = new Pen(FlatAppearance.BorderColor);
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(border, path);
            TextRenderer.DrawText(e.Graphics, Text, Font, new Rectangle(inset, inset, Width - inset * 2, Height - inset * 2), ForeColor,
                TextFormatFlags.Top | TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            if (Focused && ShowFocusCues)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -4, -4), ForeColor, BackColor);
        }
    }
}
