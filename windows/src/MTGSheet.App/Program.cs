using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace MTGSheet.App;

public static class Program
{
    [STAThread]
    private static void Main()
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(_ =>
        {
            var queue = DispatcherQueue.GetForCurrentThread();
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(queue));
            _ = new App();
        });
    }
}

public sealed class App : Application
{
    public App() => Resources.MergedDictionaries.Add(new Microsoft.UI.Xaml.Controls.XamlControlsResources());

    protected override void OnLaunched(LaunchActivatedEventArgs args) => new MainWindow().Activate();
}
