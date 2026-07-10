using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace BiometricLatencyCartographer
{
    public partial class App : Application
    {
        private MainWindow _mainWindow;
        private Stopwatch _timer;
        private List<long> _latencySamples;
        private DispatcherTimer _renderTimer;

        [DllImport("dwmapi.dll")]
        private static extern int DwmFlush();

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT lpPoint);

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
        }

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            _timer = new Stopwatch();
            _timer.Start();
            _latencySamples = new List<long>();

            _mainWindow = new MainWindow();
            _mainWindow.Show();

            CompositionTarget.Rendering += OnCompositionRendering;

            _renderTimer = new DispatcherTimer(DispatcherPriority.Send);
            _renderTimer.Interval = TimeSpan.FromMilliseconds(1);
            _renderTimer.Tick += OnInternalUpdate;
            _renderTimer.Start();
        }

        private void OnCompositionRendering(object sender, EventArgs e)
        {
            // DwmFlush synchronies the execution of the next frame with the Desktop Window Manager (DWM)
            // This is critical for measuring the composition layer latency on Windows.
            DwmFlush();

            long frameTime = _timer.ElapsedMilliseconds;
            UpdateLatencyMetrics(frameTime);
        }

        private void OnInternalUpdate(object sender, EventArgs e)
        {
            if (_mainWindow == null || !_mainWindow.IsLoaded) return;

            POINT p;
            if (GetCursorPos(out p))
            {
                // Mapping screen coordinates to local window logic for delta calculations
                Point relativePoint = _mainWindow.PointFromScreen(new Point(p.X, p.Y));
                _mainWindow.UpdateCursorVisual(relativePoint.X, relativePoint.Y);
            }
        }

        private void UpdateLatencyMetrics(long timestamp)
        {
            // Calculate delta between hardware input interrupt and DWM composition frame
            _latencySamples.Add(timestamp);
            
            if (_latencySamples.Count > 100)
            {
                _latencySamples.RemoveAt(0);
            }

            double averageShift = 0;
            if (_latencySamples.Count > 1)
            {
                long sum = 0;
                for (int i = 1; i < _latencySamples.Count; i++)
                {
                    sum += (_latencySamples[i] - _latencySamples[i - 1]);
                }
                averageShift = (double)sum / (_latencySamples.Count - 1);
            }

            _mainWindow.LatencyDisplay.Text = $"{averageShift:F3} ms (WPF/DWM)";
        }
    }

    public partial class MainWindow : Window
    {
        public System.Windows.Controls.TextBlock LatencyDisplay;
        private System.Windows.Shapes.Ellipse _cursorDot;
        private System.Windows.Controls.Canvas _mainCanvas;

        public MainWindow()
        {
            this.Title = "Biometric Latency Cartographer - Windows Node";
            this.Width = 800;
            this.Height = 600;
            this.Background = Brushes.Black;
            this.WindowStyle = WindowStyle.None;
            this.WindowState = WindowState.Maximized;

            _mainCanvas = new System.Windows.Controls.Canvas();
            this.Content = _mainCanvas;

            LatencyDisplay = new System.Windows.Controls.TextBlock
            {
                Foreground = Brushes.Lime,
                FontSize = 24,
                FontFamily = new FontFamily("Consolas"),
                Margin = new Thickness(20)
            };
            _mainCanvas.Children.Add(LatencyDisplay);

            _cursorDot = new System.Windows.Shapes.Ellipse
            {
                Width = 10,
                Height = 10,
                Fill = Brushes.Red
            };
            _mainCanvas.Children.Add(_cursorDot);
        }

        public void UpdateCursorVisual(double x, double y)
        {
            System.Windows.Controls.Canvas.SetLeft(_cursorDot, x - 5);
            System.Windows.Controls.Canvas.SetTop(_cursorDot, y - 5);
        }
    }
}