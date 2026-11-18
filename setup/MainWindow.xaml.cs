using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Resources;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace DR2AutosaveSetup
{
    public partial class MainWindow : Window
    {
        const int SlideCount = 6; // odd slides show Nagito, even slides show Hajime

        readonly DispatcherTimer slideTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4.5) };
        readonly Random random = new Random();
        readonly bool motion = SystemParameters.ClientAreaAnimation;
        readonly Image[] images = { new Image(), new Image() };
        readonly TranslateTransform[] shifts = { new TranslateTransform(), new TranslateTransform() };
        readonly ScaleTransform[] scales = { new ScaleTransform(), new ScaleTransform() };
        List<string> nagitoPoses, hajimePoses;
        readonly Queue<string> nagitoQueue = new Queue<string>(), hajimeQueue = new Queue<string>();
        int slide = -1, frontImage = 1;
        string folder;
        bool busy;

        public MainWindow()
        {
            InitializeComponent();
            foreach (var m in Installer.Intervals) IntervalBox.Items.Add(new ComboBoxItem { Content = m + " minutes", Tag = m });
            Loaded += (s, e) => Start();
            StateChanged += (s, e) => slideTimer.IsEnabled = WindowState != WindowState.Minimized;
        }

        void Start()
        {
            StartSlideshow();
            folder = Installer.FindGameFolder();
            LoadSettings();
            Refresh();
        }

        void StartSlideshow()
        {
            var sprites = SpriteNames();
            nagitoPoses = sprites.Where(n => n.Contains("nagito")).ToList();
            hajimePoses = sprites.Where(n => n.Contains("hajime")).ToList();

            for (var i = 0; i < images.Length; i++)
            {
                var group = new TransformGroup();
                group.Children.Add(scales[i]);
                group.Children.Add(shifts[i]);
                images[i].RenderTransform = group;
                images[i].RenderTransformOrigin = new Point(.5, 1);
                images[i].VerticalAlignment = VerticalAlignment.Bottom;
                images[i].Stretch = Stretch.Uniform;
                images[i].Opacity = 0;
                RenderOptions.SetBitmapScalingMode(images[i], BitmapScalingMode.HighQuality);
                Actor.Children.Add(images[i]);
            }

            for (var i = 0; i < SlideCount; i++)
            {
                var target = i;
                var dot = new RadioButton { Style = (Style)FindResource("SlideDot") };
                AutomationProperties.SetName(dot, "Slide " + (i + 1));
                dot.Click += (s, e) => { if (target != slide) ShowSlide(target, target > slide ? 1 : -1); };
                SlideDots.Children.Add(dot);
            }

            if (motion)
            {
                Spin(RingLeft, 360, 46);
                Spin(RingRight, -360, 62);
                ActorBob.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, -5, TimeSpan.FromSeconds(2))
                { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } });
            }

            ShowSlide(0, 1);
            // Pauses while the pointer is over the picture, so a pose can be looked at.
            slideTimer.Tick += (s, e) => { if (!Stage.IsMouseOver) ShowSlide((slide + 1) % SlideCount, 1); };
            slideTimer.Start();
        }

        static void Spin(RotateTransform ring, double angle, int seconds) =>
            ring.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, angle, TimeSpan.FromSeconds(seconds)) { RepeatBehavior = RepeatBehavior.Forever });

        static List<string> SpriteNames()
        {
            var assembly = typeof(MainWindow).Assembly;
            using (var stream = assembly.GetManifestResourceStream(assembly.GetName().Name + ".g.resources"))
            using (var reader = new ResourceReader(stream))
                return reader.Cast<DictionaryEntry>().Select(e => (string)e.Key).Where(k => k.StartsWith("sprites/")).OrderBy(k => k).ToList();
        }

        // Every pose appears once before any repeats.
        string NextPose(Queue<string> queue, List<string> poses)
        {
            if (queue.Count == 0)
                foreach (var pose in poses.OrderBy(_ => random.Next())) queue.Enqueue(pose);
            return queue.Dequeue();
        }

        void ShowSlide(int index, int direction)
        {
            slide = index;
            ((RadioButton)SlideDots.Children[index]).IsChecked = true;
            var name = index % 2 == 0 ? NextPose(nagitoQueue, nagitoPoses) : NextPose(hajimeQueue, hajimePoses);

            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.UriSource = new Uri("pack://application:,,,/" + name);
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.EndInit();
            bitmap.Freeze();

            var old = frontImage;
            frontImage = 1 - frontImage;
            images[frontImage].Source = bitmap;
            Panel.SetZIndex(images[frontImage], 1);
            Panel.SetZIndex(images[old], 0);

            if (!motion)
            {
                images[old].Opacity = 0;
                images[frontImage].Opacity = 1;
                return;
            }

            IEasingFunction accelerate = new QuadraticEase { EasingMode = EasingMode.EaseIn };
            IEasingFunction spring = new BackEase { Amplitude = .4, EasingMode = EasingMode.EaseOut };
            Animate(images[old], OpacityProperty, 1, 0, 210, accelerate);
            Animate(shifts[old], TranslateTransform.XProperty, 0, -130 * direction, 250, accelerate);
            Animate(images[frontImage], OpacityProperty, 0, 1, 170, null, 130);
            Animate(shifts[frontImage], TranslateTransform.XProperty, 170 * direction, 0, 520, spring, 130);
            Animate(scales[frontImage], ScaleTransform.ScaleXProperty, .92, 1, 520, spring, 130);
            Animate(scales[frontImage], ScaleTransform.ScaleYProperty, .92, 1, 520, spring, 130);
            Animate(Wipe, TranslateTransform.XProperty, 620 * direction, -620 * direction, 560, new CubicEase { EasingMode = EasingMode.EaseInOut });
            Animate(BandShift, TranslateTransform.XProperty, 46 * direction, 0, 760, new CubicEase { EasingMode = EasingMode.EaseOut });
        }

        static void Animate(IAnimatable target, DependencyProperty property, double from, double to, int ms, IEasingFunction ease, int delay = 0) =>
            target.BeginAnimation(property, new DoubleAnimation(from, to, TimeSpan.FromMilliseconds(ms))
            { EasingFunction = ease, BeginTime = TimeSpan.FromMilliseconds(delay) });

        void StepSlide(int direction)
        {
            slideTimer.Stop();
            ShowSlide((slide + direction + SlideCount) % SlideCount, direction);
            slideTimer.Start();
        }

        void OnPreviousSlide(object sender, RoutedEventArgs e) => StepSlide(-1);
        void OnNextSlide(object sender, RoutedEventArgs e) => StepSlide(1);

        void LoadSettings()
        {
            var s = Installer.ReadSettings(folder);
            IntervalBox.SelectedItem = IntervalBox.Items.Cast<ComboBoxItem>().First(i => (int)i.Tag == s.IntervalMinutes);
            NotifyCheck.IsChecked = s.ShowNotification;
            BackupCheck.IsChecked = s.KeepBackups;
        }

        void Refresh()
        {
            var game = Installer.CheckGame(folder);
            var dx = Installer.DirectXPresent();
            var installed = Installer.IsModInstalled(folder);
            var taken = Installer.PlayerSavesInAutosaveSlots(Installer.SaveFolder);

            FolderText.Text = folder ?? "Not found";
            DiagGame.Text = game == GameState.Supported ? "Supported" : game == GameState.WrongVersion ? "Not supported" : "Game not found";
            DiagDx.Text = dx ? "Found" : "Missing";
            DiagMod.Text = installed ? "Installed" : "Not installed";
            DiagSlots.Text = taken == 0 ? "3 of 3 available" : taken == 3 ? "None: slots 28-30 hold your saves" : $"{3 - taken} of 3 available";
            SaveLabel.Text = installed ? "Save Settings" : "Install Mod";
            SaveButton.IsEnabled = !busy && game == GameState.Supported && dx && taken < 3;
            UninstallButton.IsEnabled = !busy && installed;

            if (game == GameState.Missing) SetStatus("Game not found. Open Settings and choose the game folder.", true);
            else if (game == GameState.WrongVersion) SetStatus("This game version is not supported. The mod needs the current Steam version.", true);
            else if (!dx) SetStatus("DirectX 9 files are missing. Start the game once from Steam, then reopen this setup.", true);
            else if (taken == 3) SetStatus("Slots 28, 29 and 30 hold your saves. Free at least one to use autosave.", true);
            else if (installed) SetStatus("Mod installed. Change your settings or start the game.", false);
            else SetStatus("Ready to install the mod.", false);
        }

        void SetStatus(string text, bool problem)
        {
            StatusText.Text = text;
            StatusIcon.Text = problem ? "" : "";
            StatusIcon.Foreground = problem ? (Brush)FindResource("Yellow") : Brushes.White;
        }

        async Task Run(Action work, string done)
        {
            busy = true;
            SaveButton.IsEnabled = UninstallButton.IsEnabled = false;
            SetStatus("Working...", false);
            string error = null;
            try { await Task.Run(work); }
            catch (InstallerException e) { error = e.Message; }
            busy = false;
            Refresh();
            if (error != null) SetStatus(error, true);
            else SetStatus(done, false);
        }

        async void OnSave(object sender, RoutedEventArgs e)
        {
            var settings = new ModSettings
            {
                IntervalMinutes = (int)((ComboBoxItem)IntervalBox.SelectedItem).Tag,
                ShowNotification = NotifyCheck.IsChecked == true,
                KeepBackups = BackupCheck.IsChecked == true
            };
            var target = folder;
            await Run(() => Installer.Install(target, settings), "All set! Start the game and autosave will run on its own.");
        }

        async void OnUninstall(object sender, RoutedEventArgs e)
        {
            if (MessageBox.Show(this, "Remove the Autosave mod from the game?\n\nYour saves, including autosaves already made, are kept.",
                                "Uninstall Mod", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
            var target = folder;
            await Run(() => Installer.Uninstall(target), "Mod removed. Your saves were not touched.");
        }

        void OnBrowse(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog { Title = "Select " + Installer.GameExe, Filter = "Danganronpa 2|" + Installer.GameExe, CheckFileExists = true };
            if (dialog.ShowDialog(this) != true) return;
            folder = System.IO.Path.GetDirectoryName(dialog.FileName);
            LoadSettings();
            Refresh();
        }

        void OnDetect(object sender, RoutedEventArgs e)
        {
            folder = Installer.FindGameFolder();
            LoadSettings();
            Refresh();
        }

        void OnOpenLog(object sender, RoutedEventArgs e)
        {
            var path = folder == null ? null : Installer.LogPath(folder);
            if (path != null && File.Exists(path)) Process.Start(path);
            else SetStatus("No log yet. It appears after the game runs with the mod.", false);
        }

        void OnOpenBackups(object sender, RoutedEventArgs e)
        {
            if (Directory.Exists(Installer.BackupFolder)) Process.Start("explorer.exe", "\"" + Installer.BackupFolder + "\"");
            else SetStatus("No backups yet. They appear after the game runs with the mod.", false);
        }

        void OnNav(object sender, RoutedEventArgs e)
        {
            if (Pages == null) return;
            PageGeneral.Visibility = NavGeneral.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            PageSettings.Visibility = NavSettings.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            PageAdvanced.Visibility = NavAdvanced.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            PageAbout.Visibility = NavAbout.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
            if (!motion) return;
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            Pages.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
            PagesShift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(26, 0, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease });
        }

        void OnTitleDrag(object sender, MouseButtonEventArgs e) => DragMove();
        void OnMinimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
        void OnExit(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosing(CancelEventArgs e)
        {
            e.Cancel = busy; // closing mid-install could leave the game folder half changed
            base.OnClosing(e);
        }
    }
}
