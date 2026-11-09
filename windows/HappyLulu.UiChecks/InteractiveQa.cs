using System.Drawing;
using HappyLulu.Core;
using HappyLulu.Tray;

internal sealed class InteractiveQa : Form
{
    private readonly AppController controller;
    private readonly DateTimeOffset now;
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    private TodayForm? today;
    private SettingsForm? settings;
    private UiLanguage displayedLanguage;

    private InteractiveQa()
    {
        string directory = Path.Combine(Path.GetTempPath(), "happylulu-interactive-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var store = new StateStore(Path.Combine(directory, "state.json"));
        DateTime local = DateTime.Today.AddHours(17);
        now = new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local));
        controller = new AppController(store, () => now);
        if (!controller.Apply(state => state.Language = UiLanguage.Korean))
            throw new InvalidOperationException(controller.Error);
        displayedLanguage = controller.State.Language;
        Words.Preference = displayedLanguage;
        Seed();

        Text = "happylulu Windows QA";
        Font = new Font("Segoe UI", 10);
        ClientSize = new Size(650, 260);
        StartPosition = FormStartPosition.CenterScreen;
        var stack = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            Padding = new Padding(16), AutoScroll = true
        };
        stack.Controls.Add(new Label
        {
            Text = "격리된 Windows 화면 QA / Isolated Windows GUI QA", AutoSize = true,
            Font = new Font(Font, FontStyle.Bold)
        });
        stack.Controls.Add(new Label
        {
            Text = $"테스트 시각: {now:yyyy-MM-dd HH:mm} (고정)\n아래 임시 기록만 사용합니다. 자동 실행 변경·잠금 해제 감지는 실행하지 않습니다.",
            AutoSize = true, Margin = new Padding(0, 10, 0, 8)
        });
        stack.Controls.Add(new TextBox
        {
            Text = store.Path, ReadOnly = true, Width = 605,
            AccessibleName = "Isolated QA attendance path"
        });
        var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Width = 605 };
        AddButton(actions, "오늘 / Today", ShowToday);
        AddButton(actions, "설정 / Settings", ShowSettings);
        AddButton(actions, "테스트 기록 초기화 / Reset fixture", Seed);
        AddButton(actions, "QA 종료 / Exit", Close);
        stack.Controls.Add(actions);
        Controls.Add(stack);
        controller.Changed += RefreshForms;
        timer.Tick += (_, _) =>
        {
            if (displayedLanguage != controller.State.Language)
            {
                bool todayVisible = today is { Visible: true };
                bool settingsVisible = settings is { Visible: true };
                today?.Dispose();
                settings?.Dispose();
                today = null;
                settings = null;
                displayedLanguage = controller.State.Language;
                Words.Preference = displayedLanguage;
                if (todayVisible) ShowToday();
                if (settingsVisible) ShowSettings();
            }
            if (today is { IsDisposed: false }) today.RefreshView();
        };
        timer.Start();
        Shown += (_, _) => ShowToday();
        Console.WriteLine("Interactive QA state: " + store.Path);
    }

    public static void Run()
    {
        using var launcher = new InteractiveQa();
        Application.Run(launcher);
    }

    internal static SettingsForm CreateSettings(AppController controller)
    {
        var form = new SettingsForm(controller, SystemIcons.Application);
        CheckBox startup = Descendants(form).OfType<CheckBox>().Single(control =>
            control.AccessibleName == "Windows 로그인 시 자동 실행" ||
            control.AccessibleName == "Start when signing in to Windows");
        startup.Enabled = false;
        startup.AccessibleDescription = "Disabled in isolated QA; Windows startup is never changed.";
        return form;
    }

    private void Seed()
    {
        bool saved = controller.Apply(state =>
        {
            state.Arrivals.Clear();
            state.ManualDayTypes.Clear();
            state.SuppressedDays.Clear();
            foreach (int daysAgo in new[] { 0, 1, 30, 365, 550 })
            {
                DateTime local = now.Date.AddDays(-daysAgo).AddHours(9);
                DateTimeOffset at = new(local, TimeZoneInfo.Local.GetUtcOffset(local));
                string day = Attendance.DayKey(at);
                state.Arrivals[day] = new Arrival
                {
                    Day = day, Time = at, Source = ArrivalSource.Manual,
                    Mode = WorkdayMode.Normal, EarlyLeaveOverrideMinutes = 0
                };
                state.ManualDayTypes[day] = ManualDayType.Regular;
            }
        });
        if (!saved) throw new InvalidOperationException(controller.Error);
    }

    private void ShowToday()
    {
        today ??= new TodayForm(controller, ShowSettings, SystemIcons.Application);
        today.Show();
        today.Activate();
        today.RefreshView();
    }

    private void ShowSettings()
    {
        settings ??= CreateSettings(controller);
        settings.Show();
        settings.Activate();
        settings.RefreshView();
    }

    private void RefreshForms()
    {
        if (today is { IsDisposed: false }) today.RefreshView();
        if (settings is { IsDisposed: false }) settings.RefreshView();
    }

    private static void AddButton(FlowLayoutPanel actions, string text, Action action)
    {
        var button = new Button { Text = text, AutoSize = true, AccessibleName = text };
        button.Click += (_, _) => action();
        actions.Controls.Add(button);
    }

    private static IEnumerable<Control> Descendants(Control root)
    {
        foreach (Control child in root.Controls)
        {
            yield return child;
            foreach (Control nested in Descendants(child)) yield return nested;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            timer.Stop();
            timer.Dispose();
            today?.Dispose();
            settings?.Dispose();
        }
        base.Dispose(disposing);
    }
}
