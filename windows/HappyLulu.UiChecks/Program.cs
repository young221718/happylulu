using System.Drawing;
using System.Globalization;
using System.Reflection;
using HappyLulu.Core;
using HappyLulu.Tray;

internal static class Program
{
    private static int checks;

    [STAThread]
    private static int Main(string[] args)
    {
        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Words.Preference = UiLanguage.English;
        try
        {
            if (args.SequenceEqual(new[] { "--interactive" }))
            {
                InteractiveQa.Run();
                return 0;
            }
            if (args.Length != 0) throw new ArgumentException("Use no arguments for checks, or --interactive for isolated GUI QA.");
            Run(nameof(ClockEditing), ClockEditing);
            Run(nameof(DayTypeSelection), DayTypeSelection);
            Run(nameof(InvalidClockTypeSelection), InvalidClockTypeSelection);
            Run(nameof(EscapeFromOtherControl), EscapeFromOtherControl);
            Run(nameof(PopoverPlacement), PopoverPlacement);
            Run(nameof(OwlAssets), OwlAssets);
            Run(nameof(DayTypeLayout), DayTypeLayout);
            Run(nameof(DayTypeDiscovery), DayTypeDiscovery);
            Run(nameof(MonthHistory), MonthHistory);
            Run(nameof(TrayDepartureSetting), TrayDepartureSetting);
            Run(nameof(OvertimeDisplayUnit), OvertimeDisplayUnit);
            Run(nameof(SettingsLayout), SettingsLayout);
            Run(nameof(StorageFailures), StorageFailures);
            Run(nameof(InteractiveSafety), InteractiveSafety);
            Console.WriteLine($"PASS Windows form behavior: {checks} assertions (isolated storage, no desktop input)");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("FAIL Windows form behavior: " + ex);
            return 1;
        }
    }

    private static void Run(string name, Action check)
    {
        Console.WriteLine("BEGIN " + name);
        check();
        Console.WriteLine("PASS " + name);
    }

    private static void ClockEditing()
    {
        using var fixture = new Fixture();
        using var form = fixture.Today();
        TextBox input = Find<TextBox>(form, "Arrival time HH:mm");
        Button edit = Find<Button>(form, "Edit arrival time");
        Click(edit);
        input.Text = "09:15";
        Key(input, Keys.Enter);
        Equal("09:15", fixture.StoredClock(), "Enter persists the edited clock");

        byte[] before = File.ReadAllBytes(fixture.Store.Path);
        Click(edit);
        input.Text = "09:45";
        Key(input, Keys.Escape);
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Escape preserves stored bytes");

        Click(edit);
        input.Text = "25:61";
        Key(input, Keys.Enter);
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Invalid clock preserves stored bytes");
        Equal("25:61", input.Text, "Invalid input remains available to correct");
        input.Text = "09:30";
        Raise(typeof(Control), input, "OnLeave", EventArgs.Empty);
        Equal("09:30", fixture.StoredClock(), "Leaving the editor persists a valid clock");

        Click(edit);
        input.Text = "09:45";
        var closing = new FormClosingEventArgs(CloseReason.UserClosing, false);
        Raise(typeof(Form), form, "OnFormClosing", closing);
        Equal("09:45", fixture.StoredClock(), "Closing commits a valid clock");
        Equal(true, closing.Cancel, "User close keeps the resident window reusable");

        Click(edit);
        input.Text = "09:50";
        before = File.ReadAllBytes(fixture.Store.Path);
        fixture.Now = fixture.Now.AddDays(1);
        Key(input, Keys.Enter);
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Midnight rollover cannot move the old edit to another day");
        Equal(false, fixture.Store.Load().Arrivals.ContainsKey("2026-11-06"), "Rollover does not fabricate today's arrival");
    }

    private static void DayTypeSelection()
    {
        using var fixture = new Fixture();
        fixture.SaveArrival("09:00");
        using var form = fixture.Today();
        TextBox input = Find<TextBox>(form, "Arrival time HH:mm");
        Click(Find<Button>(form, "Edit arrival time"));
        input.Text = "09:30";
        ChooseType(form, "Lulu day");
        AttendanceState stored = fixture.Store.Load();
        Equal("09:30", fixture.StoredClock(), "Changing type commits an active valid clock edit");
        Equal(ManualDayType.LuluDay, stored.ManualDayTypes["2026-11-05"], "Refresh during clock save does not replace the requested type");
        Equal(120, stored.Arrivals["2026-11-05"].EarlyLeaveOverrideMinutes, "Lulu day saves its two-hour reduction");

        ChooseType(form, "Annual / official leave");
        Equal("09:30", fixture.StoredClock(), "Annual leave preserves the arrival file record");
        Equal(null, Attendance.Today(fixture.Controller.State, fixture.Now), "Annual leave pauses the active workday");
        Equal("—", Field<Label>(form, "departureTime").Text, "Annual leave removes the planned departure display");

        byte[] before = File.ReadAllBytes(fixture.Store.Path);
        ChooseType(form, "Morning off");
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Incompatible half-day selection preserves the previous state");
        Equal(true, Find<Button>(form, "Annual / official leave").AccessibleDescription?.StartsWith("Selected", StringComparison.Ordinal) == true, "Rejected type restores the displayed selection");
    }

    private static void InvalidClockTypeSelection()
    {
        using var fixture = new Fixture();
        fixture.SaveArrival("09:00");
        using var form = fixture.Today();
        TextBox input = Find<TextBox>(form, "Arrival time HH:mm");
        byte[] before = File.ReadAllBytes(fixture.Store.Path);
        Click(Find<Button>(form, "Edit arrival time"));
        input.Text = "25:61";
        ChooseType(form, "Lulu day");
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Invalid clock blocks type changes without altering the saved file");
        Equal("25:61", input.Text, "Rejected type change preserves the invalid clock for correction");
        Equal(true, Find<Button>(form, "Regular work").AccessibleDescription?.StartsWith("Selected", StringComparison.Ordinal) == true, "Invalid clock keeps the original work type selected");

        Raise(typeof(Form), form, "OnDeactivate", EventArgs.Empty);
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Deactivation with invalid input preserves the saved file");
        Equal("25:61", input.Text, "Deactivation keeps invalid input available to correct");
        Equal(false, form.Dismiss(), "Invalid input prevents popover dismissal");
        var closing = new FormClosingEventArgs(CloseReason.UserClosing, false);
        Raise(typeof(Form), form, "OnFormClosing", closing);
        Equal(true, closing.Cancel, "Closing with invalid input keeps the window reusable");
        Equal("25:61", input.Text, "Closing keeps invalid input available to correct");

        Key(input, Keys.Escape);
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Escape after a rejected type change preserves saved bytes");
        Equal("09:00", Find<Button>(form, "Edit arrival time").Text, "Escape restores the persisted arrival display");
    }

    private static void PopoverPlacement()
    {
        foreach (var sample in new[]
        {
            (Anchor: new Point(1900, 1060), Work: new Rectangle(0, 0, 1920, 1040), Size: new Size(364, 350)),
            (Anchor: new Point(20, 16), Work: new Rectangle(0, 40, 1920, 1040), Size: new Size(364, 350)),
            (Anchor: new Point(24, 700), Work: new Rectangle(48, 0, 1872, 1080), Size: new Size(364, 350)),
            (Anchor: new Point(-1900, 1050), Work: new Rectangle(-1920, 0, 1920, 1040), Size: new Size(364, 350)),
            (Anchor: new Point(-400, -1050), Work: new Rectangle(-960, -1080, 1920, 1080), Size: new Size(364, 350)),
            (Anchor: new Point(80, 120), Work: new Rectangle(0, 0, 160, 120), Size: new Size(800, 700))
        })
        {
            Rectangle popup = TodayForm.PopupBounds(sample.Anchor, sample.Work, sample.Size);
            Equal(true, sample.Work.Contains(popup), "Popover remains inside the working area for edge trays, negative monitors, and small screens");
            Equal(true, popup.Width > 0 && popup.Height > 0, "Popover retains a usable positive size");
            Equal(true, popup.Width <= sample.Size.Width && popup.Height <= sample.Size.Height, "Working-area fitting does not enlarge the requested popover");
        }
    }

    private static void EscapeFromOtherControl()
    {
        foreach (string focusName in new[] { "Regular work", "More" })
        {
            using var fixture = new Fixture();
            fixture.SaveArrival("09:00");
            using var form = fixture.Today();
            byte[] before = File.ReadAllBytes(fixture.Store.Path);
            TextBox input = Find<TextBox>(form, "Arrival time HH:mm");
            Click(Find<Button>(form, "Edit arrival time"));
            input.Text = "25:61";
            Raise(typeof(Control), input, "OnLeave", EventArgs.Empty);
            form.ActiveControl = Find<Button>(form, focusName);
            Equal(focusName, form.ActiveControl?.AccessibleName, "Escape regression places focus outside the clock editor");

            Equal(true, CommandKey(form, Keys.Escape), "The form consumes Escape after focus leaves an invalid clock edit");
            Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Escape outside the editor preserves saved bytes");
            Equal("09:00", Find<Button>(form, "Edit arrival time").Text, "Escape outside the editor restores the persisted arrival display");
            Equal(true, form.Dismiss(), "Escape outside the editor cancels the invalid draft so the popover can dismiss");
        }
    }

    private static void OwlAssets()
    {
        using var icons = new OwlStateIcons(SystemIcons.Application);
        Image fallback = icons.Get((OwlState)(-1));
        using var canvas = new Bitmap(28, 28);
        using Graphics graphics = Graphics.FromImage(canvas);
        graphics.DrawImage(fallback, new Rectangle(0, 0, 28, 28));
        foreach (OwlState state in Enum.GetValues<OwlState>())
        {
            Image image = icons.Get(state);
            Equal(false, ReferenceEquals(fallback, image), $"{state} loads its packaged owl asset instead of falling back");
            graphics.DrawImage(image, new Rectangle(0, 0, 28, 28));
        }
    }

    private static void DayTypeLayout()
    {
        foreach (UiLanguage language in new[] { UiLanguage.English, UiLanguage.Korean })
        {
            foreach (ManualDayType selectedType in Enum.GetValues<ManualDayType>())
            {
                Console.WriteLine($"BEGIN workday layout {language} {selectedType}");
                using var fixture = new Fixture();
                Equal(true, fixture.Controller.SetDayType(selectedType), "Layout fixture can select each work type without an arrival");
                Words.Preference = language;
                using var form = fixture.Today();
                form.StartPosition = FormStartPosition.Manual;
                form.Location = new Point(-10000, -10000);
                form.Show();
                Application.DoEvents();
                Control choices = Find<FlowLayoutPanel>(form, Words.T("오늘 근무 유형", "Today's work type"));
                Button selected = choices.Controls.OfType<Button>().Single(button => button.AccessibleDescription?.StartsWith(Words.T("선택됨", "Selected"), StringComparison.Ordinal) == true);
                Click(selected);
                Application.DoEvents();
                Button[] buttons = choices.Controls.OfType<Button>().ToArray();
                Equal(5, buttons.Length, "Expanding a work type makes all five choices available");
                foreach (Button button in buttons)
                {
                    Equal(true, choices.ClientRectangle.Contains(button.Bounds),
                        $"{language} {selectedType} expanded {button.Text} remains fully inside its container");
                    Size text = TextRenderer.MeasureText(button.Text, button.Font, Size.Empty,
                        TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
                    Equal(true, text.Width <= button.ClientSize.Width && text.Height <= button.ClientSize.Height,
                        $"{language} {selectedType} expanded {button.Text} fits its button without clipping");
                }
                Console.WriteLine($"PASS workday layout {language} {selectedType}");
            }
        }
        Words.Preference = UiLanguage.English;
    }

    private static void DayTypeDiscovery()
    {
        foreach (UiLanguage language in new[] { UiLanguage.English, UiLanguage.Korean })
        {
            Words.Preference = language;
            using var fixture = new Fixture();
            fixture.SaveArrival("09:00");
            using var form = fixture.Today();
            Button selected = Find<Button>(form, Words.T("일반근무", "Regular work"));
            Equal(true, selected.Text.EndsWith(" ▾", StringComparison.Ordinal),
                "The collapsed workday button shows that choices can be opened");
            Equal(true, selected.AccessibleDescription?.Contains(Words.T("근무 유형 선택", "workday choices"), StringComparison.Ordinal) == true,
                "The collapsed workday button describes its action to assistive technology");
            Click(selected);
            Equal(false, selected.Text.EndsWith(" ▾", StringComparison.Ordinal),
                "The expand indicator disappears while choices are visible");
            Click(selected);
            Equal(true, selected.Text.EndsWith(" ▾", StringComparison.Ordinal),
                "The expand indicator returns after choosing a type");
            Equal("09:00", fixture.StoredClock(), "Opening workday choices preserves attendance");
        }
        Words.Preference = UiLanguage.English;
    }

    private static void MonthHistory()
    {
        using var fixture = new Fixture();
        DateOnly oldDay = DateOnly.FromDateTime(DateTime.Today).AddMonths(-18);
        string key = oldDay.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        DateTimeOffset oldArrival = new(oldDay.Year, oldDay.Month, oldDay.Day, 9, 17, 0, TimeSpan.FromHours(9));
        fixture.Controller.Apply(state =>
        {
            state.Arrivals[key] = new Arrival { Day = key, Time = oldArrival, Source = ArrivalSource.Manual, Mode = WorkdayMode.Normal };
            state.ManualDayTypes[key] = ManualDayType.AnnualLeave;
        });
        using var form = new SettingsForm(fixture.Controller, SystemIcons.Application);
        Click(Find<Button>(form, "Attendance"));
        Button previous = Find<Button>(form, "Previous month");
        for (int i = 0; i < 18; i++) Click(previous);
        Button day = Descendants(form).OfType<Button>().Single(button => button.AccessibleName?.StartsWith(key + " ", StringComparison.Ordinal) == true);
        Click(day);
        Label detail = Find<Label>(form, "Attendance for the selected day");
        Equal(true, detail.Text.Contains("09:17", StringComparison.Ordinal), "Old month displays the recorded clock without host timezone conversion");
        Equal(true, detail.Text.Contains("UTC+09:00", StringComparison.Ordinal), "History retains the recorded UTC offset");
        Equal(true, detail.Text.Contains("preserved", StringComparison.Ordinal), "Annual leave detail exposes the preserved arrival");
        Equal(true, detail.Text.Contains("Manual entry", StringComparison.Ordinal), "History retains the original input source");

        ComboBox language = Find<ComboBox>(form, "Display language");
        language.SelectedIndex = (int)UiLanguage.Korean;
        Equal(UiLanguage.Korean, fixture.Store.Load().Language, "Language selection persists through the settings event");
        ComboBox remaining = Find<ComboBox>(form, "Remaining time display");
        remaining.SelectedIndex = (int)RemainingTimeUnit.Seconds;
        Equal(RemainingTimeUnit.Seconds, fixture.Store.Load().RemainingTimeUnit, "Countdown unit persists through the settings event");
    }

    private static void SettingsLayout()
    {
        foreach (UiLanguage language in new[] { UiLanguage.English, UiLanguage.Korean })
        {
            Words.Preference = language;
            using var fixture = new Fixture();
            using var form = new SettingsForm(fixture.Controller, SystemIcons.Application)
            {
                ShowInTaskbar = false, StartPosition = FormStartPosition.Manual,
                Location = new Point(-10000, -10000)
            };
            // Native layout must run; constructor-only checks miss first-display sizing.
            form.Show();
            Application.DoEvents();
            CheckSettingRows(form, "language", "remainingUnit", "showDeparture", "startup");
            CheckDefaultSettingLabels(form, "language", "remainingUnit", "showDeparture", "startup");
            Click(Find<Button>(form, Words.T("근무", "Work")));
            Application.DoEvents();
            CheckSettingRows(form, "work", "rest");
            Click(Find<Button>(form, Words.T("일반", "General")));
            Application.DoEvents();
            CheckSettingRows(form, "language", "remainingUnit", "showDeparture", "startup");
            CheckDefaultSettingLabels(form, "language", "remainingUnit", "showDeparture", "startup");

            form.Size = form.MinimumSize;
            Application.DoEvents();
            CheckSettingRows(form, "language", "remainingUnit", "showDeparture", "startup");
            Click(Find<Button>(form, Words.T("근무", "Work")));
            Application.DoEvents();
            CheckSettingRows(form, "work", "rest");
        }
        Words.Preference = UiLanguage.English;
    }

    private static void TrayDepartureSetting()
    {
        using var fixture = new Fixture();
        fixture.SaveArrival("09:00");
        using var form = new SettingsForm(fixture.Controller, SystemIcons.Application);
        CheckBox visibility = Find<CheckBox>(form, "Show departure time in tray");
        Equal(true, visibility.Checked, "Departure clock is shown by default for existing users");
        visibility.Checked = false;
        var restarted = new AppController(fixture.Store, () => fixture.Now);
        using var reopened = new SettingsForm(restarted, SystemIcons.Application);
        Equal(false, Find<CheckBox>(reopened, "Show departure time in tray").Checked,
            "Hiding the departure clock survives restart");
        Equal("09:00", fixture.StoredClock(), "Changing display settings preserves attendance");
        using (var locked = new FileStream(fixture.Store.Path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            visibility.Checked = true;
            Equal(false, visibility.Checked, "Failed save restores the previous setting");
        }
    }

    private static void OvertimeDisplayUnit()
    {
        using var fixture = new Fixture();
        fixture.SaveArrival("09:00");
        fixture.Now = fixture.Now.AddHours(1).AddMinutes(30).AddSeconds(1);
        using var form = fixture.Today();
        Equal(true, fixture.Controller.SetRemainingTimeUnit(RemainingTimeUnit.Seconds), "Seconds unit saves");
        Equal("Extra 1801 s in progress", Field<Label>(form, "stateNote").Text,
            "Today panel displays overtime in selected seconds");
        fixture.Now = fixture.Now.AddMilliseconds(250);
        Equal(true, fixture.Controller.SetRemainingTimeUnit(RemainingTimeUnit.Milliseconds), "Milliseconds unit saves");
        Equal("Extra 1801250 ms in progress", Field<Label>(form, "stateNote").Text,
            "Today panel displays overtime in selected milliseconds");
        Equal("09:00", fixture.StoredClock(), "Changing overtime display preserves attendance");
    }

    private static void CheckSettingRows(SettingsForm form, params string[] controlNames)
    {
        foreach (string name in controlNames)
        {
            Control input = Field<Control>(form, name);
            var row = (TableLayoutPanel)input.Parent!;
            Control stack = row.Parent!;
            int available = stack.ClientSize.Width - stack.Padding.Horizontal - SystemInformation.VerticalScrollBarWidth;
            Control label = row.GetControlFromPosition(0, 0)!;
            Control example = row.GetControlFromPosition(1, 0)!;
            string geometry = $"example.Width={example.Width}, row.Width={row.Width}, columns=[{string.Join(",", row.GetColumnWidths())}], form.Size={form.Size}, form.ClientSize={form.ClientSize}, DPI={form.DeviceDpi}";
            Equal(true, row.Width >= available - row.Margin.Horizontal,
                $"{Words.Preference} {name} row uses the available settings width on first display, revisit, and resize ({geometry})");
            Equal(true, example.Width >= 140,
                $"{Words.Preference} {name} description remains readable at the minimum window size ({geometry})");
            Equal(true, row.ClientRectangle.Contains(label.Bounds) && row.ClientRectangle.Contains(example.Bounds) && row.ClientRectangle.Contains(input.Bounds),
                $"{Words.Preference} {name} label, preview, and input stay inside the row at default and minimum sizes ({geometry}; label={label.Bounds}, example={example.Bounds}, input={input.Bounds})");
            Equal(true, label.Right <= example.Left && example.Right <= input.Left,
                $"{Words.Preference} {name} label, preview, and input do not overlap at default and minimum sizes ({geometry}; label={label.Bounds}, example={example.Bounds}, input={input.Bounds})");
        }
    }

    private static void CheckDefaultSettingLabels(SettingsForm form, params string[] controlNames)
    {
        foreach (string name in controlNames)
        {
            Control input = Field<Control>(form, name);
            var row = (TableLayoutPanel)input.Parent!;
            var label = (Label)row.GetControlFromPosition(0, 0)!;
            Size singleLine = TextRenderer.MeasureText(label.Text, label.Font, Size.Empty,
                TextFormatFlags.SingleLine | TextFormatFlags.NoPadding);
            Equal(true, singleLine.Width <= label.ClientSize.Width,
                $"{Words.Preference} {name} label fits one line at the default settings size");
        }
    }

    private static void StorageFailures()
    {
        using var fixture = new Fixture();
        File.WriteAllText(fixture.Store.Path, "broken attendance file");
        var blocked = new AppController(fixture.Store, () => fixture.Now);
        Equal(false, blocked.SetDayType(ManualDayType.LuluDay), "Load failure disables all later saving");
        Equal("broken attendance file", File.ReadAllText(fixture.Store.Path), "Load failure preserves the original file bytes");

        File.Delete(fixture.Store.Path);
        fixture.SaveArrival("09:00");
        byte[] before = File.ReadAllBytes(fixture.Store.Path);
        AttendanceState originalState = fixture.Controller.State;
        using (var locked = new FileStream(fixture.Store.Path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            Equal(false, fixture.Controller.SetDayType(ManualDayType.LuluDay), "Failed atomic replacement is reported as failure");
            Equal(true, ReferenceEquals(originalState, fixture.Controller.State), "Failed save does not publish the candidate state");
            Equal(ManualDayType.Regular, fixture.Controller.State.ManualDayTypes["2026-11-05"], "Failed save preserves the explicitly chosen regular type");
            Equal<int?>(0, fixture.Controller.State.Arrivals["2026-11-05"].EarlyLeaveOverrideMinutes, "Failed save preserves the original reduction");
        }
        Equal(true, before.SequenceEqual(File.ReadAllBytes(fixture.Store.Path)), "Failed save preserves the previous file");
    }

    private static void InteractiveSafety()
    {
        using var fixture = new Fixture();
        using SettingsForm form = InteractiveQa.CreateSettings(fixture.Controller);
        Equal(false, Find<CheckBox>(form, "Start when signing in to Windows").Enabled,
            "Interactive QA cannot change Windows startup registration");
        Equal(fixture.Store.Path, Find<TextBox>(form, "Local attendance file path").Text,
            "Interactive Settings keeps the supplied isolated state path");
    }

    private static T Field<T>(object target, string name) where T : class =>
        target.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(target) as T
        ?? throw new InvalidOperationException("Missing field: " + name);

    private static IEnumerable<Control> Descendants(Control root)
    {
        foreach (Control child in root.Controls)
        {
            yield return child;
            foreach (Control nested in Descendants(child)) yield return nested;
        }
    }

    private static T Find<T>(Control root, string accessibleName) where T : Control =>
        Descendants(root).OfType<T>().Single(control => control.AccessibleName == accessibleName);

    // Raise native control events without desktop input, app startup registration, or a real user profile.
    private static void Click(Button button) => Raise(typeof(Control), button, "OnClick", EventArgs.Empty);
    private static void Key(Control control, Keys key) => Raise(typeof(Control), control, "OnKeyDown", new KeyEventArgs(key));
    private static bool CommandKey(TodayForm form, Keys key)
    {
        object[] arguments = { new Message(), key };
        return (bool)(typeof(TodayForm).GetMethod("ProcessCmdKey", BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Missing command-key handler")).Invoke(form, arguments)!;
    }
    private static void ChooseType(TodayForm form, string accessibleName)
    {
        Control choices = Find<FlowLayoutPanel>(form, "Today's work type");
        Button selected = choices.Controls.OfType<Button>().Single(button => button.AccessibleDescription?.StartsWith("Selected", StringComparison.Ordinal) == true);
        Click(selected);
        Click(Find<Button>(choices, accessibleName));
    }

    private static void Raise(Type type, object target, string method, object argument) =>
        (type.GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic)
         ?? throw new InvalidOperationException("Missing event raiser: " + method)).Invoke(target, new[] { argument });

    private static void Equal<T>(T expected, T actual, string description)
    {
        checks++;
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{description}: expected {expected}, got {actual}");
    }

    private sealed class Fixture : IDisposable
    {
        private readonly string directory = Path.Combine(Path.GetTempPath(), "happylulu-ui-checks-" + Guid.NewGuid().ToString("N"));
        public DateTimeOffset Now { get; set; }
        public StateStore Store { get; }
        public AppController Controller { get; }

        public Fixture()
        {
            Directory.CreateDirectory(directory);
            DateTime local = new(2026, 11, 5, 17, 0, 0, DateTimeKind.Unspecified);
            Now = new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local));
            Store = new StateStore(Path.Combine(directory, "state.json"));
            Controller = new AppController(Store, () => Now);
            Equal(Store.Path, Controller.DataPath, "Controller uses only the isolated fixture path");
        }

        public TodayForm Today()
        {
            var form = new TodayForm(Controller, () => { }, SystemIcons.Application);
            Controller.Changed += () => form.RefreshView();
            return form;
        }

        public void SaveArrival(string clock)
        {
            TimeOnly time = TimeOnly.ParseExact(clock, "HH:mm", CultureInfo.InvariantCulture);
            DateTime local = Now.LocalDateTime.Date.Add(time.ToTimeSpan());
            Equal(true, Controller.ManualArrival(new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local)), WorkdayMode.Normal), "Fixture arrival can be saved");
        }

        public string StoredClock() => Store.Load().Arrivals["2026-11-05"].Time.ToString("HH:mm", CultureInfo.InvariantCulture);
        public void Dispose() => Directory.Delete(directory, true);
    }
}
