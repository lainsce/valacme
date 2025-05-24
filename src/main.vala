/* main.vala
 * Application entry point
 */

public class AcmeApp : Gtk.Application {
    public AcmeApp () {
        Object (
            application_id: "com.example.valacme",
            flags: ApplicationFlags.FLAGS_NONE
        );
    }

    protected override void activate () {
        // Initialize singletons early
        initialize_services();
        
        // Create or activate main window
        AcmeWindow? win = find_existing_window();
        
        if (win == null) {
            win = new AcmeWindow(this);
        }

        win.present();
    }
    
    private void initialize_services() {
        AcmeThemeManager.get_instance();
        AcmeCommandManager.get_instance();
    }
    
    private AcmeWindow? find_existing_window() {
        foreach (var window in this.get_windows()) {
            if (window is AcmeWindow) {
                return (AcmeWindow) window;
            }
        }
        return null;
    }
    
    protected override void shutdown() {
        // Clean up resources
        var cmd_manager = AcmeCommandManager.get_instance();
        cmd_manager.stop_all_watchers();
        
        base.shutdown();
    }

    public static int main (string[] args) {
        // Configure GTK behavior for Acme-like experience
        configure_gtk_behavior();
        
        // Create and run the application
        var app = new AcmeApp();
        return app.run(args);
    }
    
    private static void configure_gtk_behavior() {
        var settings = Gtk.Settings.get_default();
        if (settings != null) {
            // Disable middle-click paste globally (Acme handles this specially)
            settings.gtk_enable_primary_paste = false;
            
            // Disable default accelerators (Acme uses different key handling)
            settings.gtk_enable_accels = false;
        }
    }
}