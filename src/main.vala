public class AcmeApp : Gtk.Application {
    public AcmeApp () {
        Object (
            application_id: "com.example.valacme",
            flags: ApplicationFlags.FLAGS_NONE
        );
    }

    protected override void activate () {
        // Initialize theme manager and command manager singletons
        AcmeThemeManager.get_instance();
        AcmeCommandManager.get_instance();
        
        // Create the main window if it doesn't exist yet or bring it to front
        AcmeWindow win = null;
        foreach (var window in this.get_windows ()) {
            if (window is AcmeWindow) {
                win = (AcmeWindow) window;
                break;
            }
        }

        if (win == null) {
            win = new AcmeWindow (this);
        }

        win.present ();
    }

    public static int main (string[] args) {
        // Disable GTK features globally
        var settings = Gtk.Settings.get_default();
        if (settings != null) {
            // Disable middle-click paste globally
            settings.gtk_enable_primary_paste = false;
            
            // Disable right-click menus globally
            settings.gtk_enable_accels = false;
        }
    
        // Create and run the application
        var app = new AcmeApp ();
        return app.run (args);
    }
}