using System.Windows;
using System.Windows.Threading;

namespace DR2AutosaveSetup
{
    public partial class App : Application
    {
        void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
        {
            MessageBox.Show("Something went wrong:\n\n" + e.Exception.Message, "DR2 Autosave Setup",
                            MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        }
    }
}
