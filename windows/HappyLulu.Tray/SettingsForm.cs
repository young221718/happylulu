using System.Drawing;
using System.Globalization;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal sealed class SettingsForm : Form
{
    private readonly AppController controller;
    private readonly ComboBox language = Choice();
    private readonly ComboBox remainingUnit = Choice();
    private readonly CheckBox startup = new() { AutoSize = true };
    private readonly Label startupHint = Help("");
    private readonly TextBox dataPath = new() { ReadOnly = true, Dock = DockStyle.Fill };
    private readonly NumericUpDown work = new() { Minimum = 60, Maximum = 960, Increment = 30, Width = 120 };
    private readonly NumericUpDown rest = new() { Minimum = 0, Maximum = 240, Increment = 15, Width = 120 };
    private readonly Panel content = new() { Dock = DockStyle.Fill };
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
        ClientSize = new Size(920, 680);
        MinimumSize = new Size(820, 620);

        var shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1 };
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 176));
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var sidebar = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            BackColor = UiPalette.MintWash, Padding = new Padding(14, 22, 14, 14)
        };
        sidebar.Controls.Add(new Label
        {
            Text = "happylulu", Font = new Font(Font.FontFamily, 17, FontStyle.Bold),
            AutoSize = true, Margin = new Padding(6, 0, 0, 28)
        });
        AddPage(sidebar, Words.T("일반", "General"), GeneralPage());
        AddPage(sidebar, Words.T("근무", "Work"), WorkPage());
        AddPage(sidebar, Words.T("출근 기록", "Attendance"), HistoryPage());
        sidebar.Controls.Add(new Label
        {
            Text = $"Windows {Application.ProductVersion}", AutoSize = true,
            ForeColor = UiPalette.Muted, Font = new Font(Font.FontFamily, 8),
            Margin = new Padding(6, 28, 0, 0)
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

    private void AddPage(FlowLayoutPanel sidebar, string title, Control page)
    {
        var button = new Button
        {
            Text = title, AccessibleName = title, Width = 142, Height = 42,
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
            button.BackColor = active ? UiPalette.Card : UiPalette.MintWash;
            button.ForeColor = active ? UiPalette.Mint : UiPalette.Ink;
            button.AccessibleDescription = active ? Words.T("선택됨", "Selected") : "";
        }
        selected.BringToFront();
    }

    private Control GeneralPage()
    {
        FlowLayoutPanel stack = PageStack(Words.T("일반", "General"),
            Words.T("언어와 시간 표시, Windows 시작 동작을 관리해요.",
                    "Choose your language, time display, and Windows startup behavior."));
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
        stack.Controls.Add(SettingRow(Words.T("표시 언어", "Display language"),
            Words.T("화면의 언어를 바꿔요.", "Change the language used in the app."), language));
        remainingUnit.Items.AddRange(new object[]
        {
            Words.T("시간/분 (기본)", "Hours/minutes (default)"),
            Words.T("밀리초", "Milliseconds"), Words.T("초", "Seconds"),
            Words.T("분", "Minutes"), Words.T("시간", "Hours")
        });
        remainingUnit.AccessibleName = Words.T("남은 시간 표시", "Remaining time display");
        remainingUnit.SelectedIndexChanged += (_, _) =>
        {
            if (refreshing || remainingUnit.SelectedIndex < 0) return;
            if (!controller.SetRemainingTimeUnit((RemainingTimeUnit)remainingUnit.SelectedIndex))
            {
                refreshing = true;
                remainingUnit.SelectedIndex = (int)controller.State.RemainingTimeUnit;
                refreshing = false;
            }
        };
        stack.Controls.Add(SettingRow(Words.T("남은 시간", "Remaining time"),
            Words.T("트레이와 오늘 창에 표시할 단위예요.", "The unit used in the tray and Today window."), remainingUnit));
        startup.Text = Words.T("자동 실행", "Start at sign-in");
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
        stack.Controls.Add(SettingRow(Words.T("Windows 로그인", "Windows sign-in"),
            Words.T("로그인할 때 이 앱을 열어요.", "Open the app when you sign in."), startup));
        startupHint.Text = Words.T("이 앱 파일을 옮기면 자동 실행을 다시 설정해야 합니다.",
                                   "Set startup again if you move this portable app.");
        stack.Controls.Add(startupHint);
        stack.Controls.Add(Heading(Words.T("로컬 기록 파일", "Local attendance file"), 11));
        dataPath.Text = controller.DataPath;
        dataPath.AccessibleName = Words.T("로컬 기록 파일 경로", "Local attendance file path");
        stack.Controls.Add(dataPath);
        stack.Controls.Add(Help(Words.T("기록은 이 PC에만 저장됩니다. 창을 열어도 자동 실행 설정은 바뀌지 않습니다.",
                           "Records stay on this PC. Opening Settings does not change startup.")));
        return stack;
    }

    private Control WorkPage()
    {
        FlowLayoutPanel stack = PageStack(Words.T("근무", "Work"),
            Words.T("퇴근 예정 시각을 계산할 기준을 정해요.", "Set the basis for your planned departure."));
        work.AccessibleName = Words.T("근무 시간 (분)", "Work minutes");
        rest.AccessibleName = Words.T("휴게 시간 (분)", "Break minutes");
        stack.Controls.Add(SettingRow(Words.T("근무 시간", "Work time"),
            Words.T("일반 근무의 분 단위 시간", "Minutes for a full workday"), work));
        stack.Controls.Add(SettingRow(Words.T("휴게 시간", "Break time"),
            Words.T("일반 근무에 더할 휴게 시간", "Break minutes added to a full workday"), rest));
        var apply = new Button
        {
            Text = Words.T("근무 시간 저장", "Save work hours"), AutoSize = true,
            BackColor = UiPalette.Mint, ForeColor = Color.White, FlatStyle = FlatStyle.Flat,
            Padding = new Padding(12, 6, 12, 6), Margin = new Padding(0, 12, 0, 18)
        };
        apply.FlatAppearance.BorderSize = 0;
        apply.FlatAppearance.MouseOverBackColor = UiPalette.MintDeep;
        apply.Click += (_, _) =>
        {
            if (!controller.SetWork((int)work.Value, (int)rest.Value))
                MessageBox.Show(this, controller.Error ?? Words.T("저장할 수 없어요.", "Could not save."),
                    "happylulu", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        };
        stack.Controls.Add(apply);
        stack.Controls.Add(Help(Words.T(
            "일반 근무는 근무·휴게 시간을 더합니다. 자동 일반 근무는 마지막 금요일에 2시간 단축됩니다. 오늘 유형을 일반 근무로 직접 고르면 단축하지 않고, 룰루데이는 2시간 단축합니다. 반차는 휴게 없이 4시간입니다.",
            "Full days include work and break. Automatic full days end 2 hours earlier on the last Friday. Choosing Full day explicitly removes the reduction; Lulu day reduces it by 2 hours. Half days last 4 hours without a break.")));
        stack.Controls.Add(Help(Words.T(
            "오늘의 근무 유형과 출근 시각은 트레이의 오늘 창에서 바꿀 수 있어요.",
            "Change today's work type and arrival time in the Today window from the tray.")));
        return stack;
    }

    private Control HistoryPage()
    {
        var viewport = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = UiPalette.Page };
        var page = new TableLayoutPanel
        {
            Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            ColumnCount = 1, RowCount = 6,
            BackColor = UiPalette.Page, Padding = new Padding(24, 20, 24, 16)
        };
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        // Keep six weeks readable at the minimum window size; the page scrolls instead of shrinking cells.
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 324));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 156));
        page.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        page.Controls.Add(Heading(Words.T("출근 기록", "Attendance"), 20), 0, 0);
        var navigation = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 1 };
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 62));
        navigation.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38));
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
        monthLabel.Font = new Font(Font, FontStyle.Bold);
        navigation.Controls.Add(previousMonth, 0, 0);
        navigation.Controls.Add(monthLabel, 1, 0);
        navigation.Controls.Add(today, 2, 0);
        navigation.Controls.Add(nextMonth, 3, 0);
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
        dayDetail.BackColor = UiPalette.Card;
        dayDetail.Font = new Font(Font.FontFamily, 9);
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
                var day = new Button
                {
                    Dock = DockStyle.Fill, Margin = new Padding(2), FlatStyle = FlatStyle.Flat,
                    Text = number + (note.Length == 0 ? "" : "\n" + note),
                    AccessibleName = key + (note.Length == 0 ? Words.T(" 기록 없음", " No record") : " " + note),
                    BackColor = date == selectedDay ? UiPalette.MintWash : UiPalette.Card,
                    ForeColor = date == DateOnly.FromDateTime(DateTime.Today) ? UiPalette.Mint : UiPalette.Ink,
                    Font = new Font(Font.FontFamily, 9), UseVisualStyleBackColor = false, Tag = date
                };
                day.FlatAppearance.BorderColor = date == selectedDay ? UiPalette.Mint : UiPalette.Border;
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
            day.BackColor = selected ? UiPalette.MintWash : UiPalette.Card;
            day.FlatAppearance.BorderColor = selected ? UiPalette.Mint : UiPalette.Border;
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
            AutoScroll = true, Padding = new Padding(24, 22, 24, 20), BackColor = UiPalette.Page
        };
        stack.Controls.Add(Heading(title, 20));
        Label intro = Help(description);
        intro.Margin = new Padding(0, 6, 0, 22);
        stack.Controls.Add(intro);
        stack.SizeChanged += (_, _) =>
        {
            int width = Math.Max(200, stack.ClientSize.Width - stack.Padding.Horizontal - SystemInformation.VerticalScrollBarWidth);
            foreach (Control child in stack.Controls)
            {
                if (child is TableLayoutPanel || child is TextBox) child.Width = width;
                if (child is Label label) label.MaximumSize = new Size(width, 0);
            }
        };
        return stack;
    }

    private static TableLayoutPanel SettingRow(string title, string description, Control control)
    {
        var row = new TableLayoutPanel
        {
            AutoSize = true, ColumnCount = 3, RowCount = 1, Width = 660,
            BackColor = UiPalette.Card, Padding = new Padding(12, 14, 12, 14), Margin = new Padding(0, 0, 0, 10)
        };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 125));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 210));
        row.Controls.Add(new Label { Text = title, AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        Label help = Help(description);
        help.Dock = DockStyle.Fill;
        row.Controls.Add(help, 1, 0);
        control.Anchor = AnchorStyles.Right;
        row.Controls.Add(control, 2, 0);
        row.SizeChanged += (_, _) => help.MaximumSize = new Size(Math.Max(60, row.ClientSize.Width - row.Padding.Horizontal - 350), 0);
        return row;
    }

    private static ComboBox Choice() => new() { Width = 200, DropDownStyle = ComboBoxStyle.DropDownList };
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
}
